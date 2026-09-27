// TerraBrush's water include (addons/terrabrush/Resources/Shaders/water_clipmap_shader_include
// .gdshaderinc), copied so the ripples can be changed without editing the addon. Only the
// ripple normals differ - see the RIPPLES block in calculateWaterFragment. Everything else is
// TerraBrush's as shipped, and has to stay in step with it if the addon is updated.
#include "res://addons/terrabrush/Resources/Shaders/clipmap_shader_include.gdshaderinc"


uniform sampler2DArray WaterTextures : hint_default_transparent, repeat_disable;
uniform float WaterFactor;
uniform float WaterInnerOffset = 0.3;

// Water uniforms
uniform vec3 WaterColor: source_color;
uniform vec3 FresnelColor: source_color;
uniform float Metallic: hint_range(0.0, 1.0, 0.001);
uniform float Roughness: hint_range(0.0, 1.0, 0.001);
uniform sampler2D NormalMap;
uniform sampler2D NormalMap2;
uniform float TimeScale: hint_range(0.0, 0.2, 0.005) = 0.025;
uniform float Strength = 0.4;
uniform sampler2D Wave;
uniform float NoiseScale = 10.0;
uniform float HeightScale = 0.15;
uniform vec4 ColorDeep: source_color;
uniform vec4 ColorShallow: source_color;
uniform float BeersLaw =  2.0;
uniform float DepthOffset = -0.75;
uniform float EdgeScale = 0.1;
uniform float Near = 0.5;
uniform float Far = 100.0;
uniform vec3 EdgeColor: source_color;
uniform bool InvertedZ = true;

// Ripples: two layers of different size, travelling in different directions so they cross.
// Their interference is what makes water shimmer; TerraBrush's own version moves both layers
// the same way and cross-fades them, which reads as one pattern sliding along.
uniform float RippleScale1 = 4.0;             // metres per tile of the large ripples
uniform float RippleScale2 = 1.7;             // metres per tile of the small ripples
uniform vec2 RippleDirection1 = vec2(1.0, 0.35);
uniform vec2 RippleDirection2 = vec2(-0.45, 1.0);
uniform float RippleSpeed1 = 0.16;            // metres per second
uniform float RippleSpeed2 = 0.11;
uniform float RippleDepth: hint_range(0.0, 3.0) = 1.3;

float fresnel(float amount, vec3 normal, vec3 view) {
	return pow((1.0 - clamp(dot(normalize(normal), normalize(view)), 0.0, 1.0)), amount);
}

float edge(float depth) {
	// Invert the depth value
	if (InvertedZ) {
		depth = 1.0 - depth;
	}
	depth = 2.0 * depth - 1.0;
	return Near * Far / (Far + depth * (Near - Far));
}

void calculateWaterVertex(
	mat4 modelMatrix,
	inout vec4 color,
	inout vec3 vertex,
	inout vec3 worldVertex
) {
	calculateVertex(modelMatrix, color, vertex, worldVertex);

	vec3 zoneUV = calculateZoneUV(worldVertex);
	vec4 currentWaterColor = texture(WaterTextures, zoneUV);

	if (currentWaterColor.r > 0.0f) {
		vertex.y -= WaterInnerOffset;

		vec4 levelsMeta = color;
		if (levelsMeta.g > 0.0 || levelsMeta.b > 0.0) {
			// Calculate mid zones water height
			int level = int(levelsMeta.a * 100.0);
			float levelMultiplicator = exp2(float(level));
			vec2 neighbourWorldVertex = (vec2(levelsMeta.g, levelsMeta.b) * levelMultiplicator) * InitialCellWidth;
			vec3 previousWorldVertex = worldVertex - vec3(neighbourWorldVertex.x, 0.0, neighbourWorldVertex.y);
			vec3 nextWorldVertex = worldVertex + vec3(neighbourWorldVertex.x, 0.0, neighbourWorldVertex.y);

			float previousHeight = texture(Wave, (previousWorldVertex.xz / NoiseScale) + (TIME * TimeScale)).r;
			float nextHeight = texture(Wave, (nextWorldVertex.xz / NoiseScale) + (TIME * TimeScale)).r;

			vertex.y += ((previousHeight + nextHeight) / 2.0) * HeightScale;
		} else {
			float height = texture(Wave, (worldVertex.xz / NoiseScale) + (TIME * TimeScale)).r;
			vertex.y += height * HeightScale;
		}

		float rippleValue = currentWaterColor.a;
		vertex.y += rippleValue * 0.1;

		color = vec4(currentWaterColor.r, currentWaterColor.g, currentWaterColor.b, 1.0);
	} else {
		vertex.y -= 1.0;
		color = vec4(0.0f, 0.0f, 0.0f, 0.0);
	}
}

void calculateWaterFragment(
	sampler2D depthTexture,
	sampler2D screenTexture,
	vec2 screenUV,
	mat4 projectionMatrix,
	vec4 color,
	vec3 vertex,
	vec4 fragcoord,
	vec3 view,
	vec3 worldVertex,
	inout vec3 normal,
	inout vec3 albedo,
	inout vec3 normalMap,
	inout float normalMapDepth,
	inout float metallic,
	inout float roughness
) {
	if (color[0] > 0.0f) {
		float depthTextureValue = texture(depthTexture, screenUV).r * 2.0 - 1.0;
		float depth = projectionMatrix[3][2] / (depthTextureValue + projectionMatrix[2][2]);
		float depthBlend = exp((depth + vertex.z + DepthOffset) * -BeersLaw);
		depthBlend = clamp(1.0 - depthBlend, 0.0, 1.0);
		float depthBlendPower = clamp(pow(depthBlend, 2.5), 0.0, 1.0);

		vec3 screenColor = textureLod(screenTexture, screenUV, depthBlendPower * 2.5).rgb;
		vec3 depthColor = mix(ColorShallow.rgb, ColorDeep.rgb, depthBlendPower);
		vec3 color = mix(screenColor * depthColor, depthColor * 0.25, depthBlendPower * 0.5);

		float zDepth = edge(texture(depthTexture, screenUV).r);
		float zPos = edge(fragcoord.z);
		float zDif = zDepth - zPos;

		vec3 zoneUV = calculateZoneUV(worldVertex);
		vec4 waterTexture = texture(WaterTextures, zoneUV);
		vec2 flows = waterTexture.gb * 2.0 - 1.0;

		// RIPPLES - the one part changed from TerraBrush's shader. The painted current
		// still carries both layers (flows), but linearly over time rather than in the
		// cross-faded cycles the original uses, and each layer adds its own drift on top.
		vec2 current = flows * TIME * TimeScale * Strength;
		vec2 uv1 = worldVertex.xz / RippleScale1 + current + normalize(RippleDirection1) * TIME * RippleSpeed1 / RippleScale1;
		vec2 uv2 = worldVertex.xz / RippleScale2 + current + normalize(RippleDirection2) * TIME * RippleSpeed2 / RippleScale2;
		vec3 n1 = texture(NormalMap, uv1).rgb * 2.0 - 1.0;
		vec3 n2 = texture(NormalMap2, uv2).rgb * 2.0 - 1.0;
		// Whiteout blend in tangent space: both layers keep their full relief, where
		// averaging the encoded colours would flatten each by half.
		vec3 normalBlend = normalize(vec3(n1.xy + n2.xy, n1.z * n2.z)) * 0.5 + 0.5;

		float fresnel = fresnel(5.0, normal, view);
		vec3 surfaceColor = mix(WaterColor.rgb, FresnelColor.rgb, fresnel);

		vec3 depthColorAdj = mix(EdgeColor, color, step(EdgeScale, zDif));

		albedo = clamp(surfaceColor + depthColorAdj,vec3(0.0),vec3(1.0));
		metallic = Metallic;
		roughness = Roughness;
		normalMap = normalBlend;
		normalMapDepth = RippleDepth;

		if (waterTexture.a < 0.5) {
			normal = normal + (waterTexture.a * 10.0);
		}

		if (zoneUV.z < 0.0) {
			discard;
		} else {
			float hole = texture(HeightmapTextures, zoneUV).g;
			if (hole > 0.0f) {
				discard;
			}
		}
	} else {
		discard;
	}
}
