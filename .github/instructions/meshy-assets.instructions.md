---
description: "Use when generating, importing, reviewing, optimizing, or integrating Meshy.ai 3D assets, GLB models, PBR textures, collision, LODs, or asset provenance."
applyTo: "assets/generated/**"
---
# Meshy Asset Guidelines

- Use `tools/meshy_asset.ps1`; the API key comes only from `MESHY_API_KEY`.
- Run `-DryRun` before paid generation. Generation requires explicit user intent because Meshy consumes credits.
- Default to `lowpoly`, GLB only, auto-size, bottom origin, PBR textures, and baked-light removal. Use `standard` with a deliberate polygon target only when silhouette quality requires it.
- Prompt for one isolated object, a readable gameplay silhouette, neutral pose where relevant, no ground plane, no environment, and materials matching the five-color fantasy direction.
- Keep the generated GLB, preview PNG, and `.meshy.json` provenance together under `assets/generated/<name>/`.
- Never edit generated import artifacts in `.godot`. Configure import settings or create a wrapper scene.
- Review scale, origin, orientation, materials, texture memory, polygon count, silhouette at gameplay distance, license, and collision before integration.
- Use simple primitive or convex collision for gameplay. Avoid trimesh collision on moving bodies.
- Run `./tools/validate_godot.ps1` after download/import and after scene integration.

Current API reference: https://docs.meshy.ai/en/api/text-to-3d
Godot glTF reference: https://docs.godotengine.org/en/latest/tutorials/assets_pipeline/importing_3d_scenes/index.html
