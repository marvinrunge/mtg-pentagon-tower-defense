shader_type spatial;
render_mode cull_back,blend_mix,depth_draw_opaque,diffuse_burley,specular_schlick_ggx;

#include "res://addons/terrabrush/Resources/Shaders/heightmap_clipmap_shader_include.gdshaderinc"

varying vec3 _worldVertex;
varying vec3 _worldNormal;
varying vec3 _triplanarPos;
varying vec3 _triplanarPowerNormal;

void vertex() {
	_worldVertex = vec3(0);
	_worldNormal = vec3(0);
	_triplanarPos = vec3(0);
	_triplanarPowerNormal = vec3(0);
	calculateHeightmapVertex(
		MODEL_MATRIX,
		COLOR,
		VERTEX,
		NORMAL,
		_worldVertex,
		_worldNormal,
		_triplanarPos,
		_triplanarPowerNormal
	);
}

void fragment() {
	// PROJECT PATCH: the view direction (towards the camera) and distance, for the parallax.
	vec3 viewWorld = normalize((INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz);
	calculateHeightmapFragment(
		_worldVertex,
		_worldNormal,
		_triplanarPos,
		_triplanarPowerNormal,
		ALBEDO,
		NORMAL_MAP,
		METALLIC,
		SPECULAR,
		ROUGHNESS,
		viewWorld,
		length(VERTEX)
	);
}