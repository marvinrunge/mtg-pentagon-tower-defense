---
name: meshy-assets
description: "Generate and integrate game-ready Meshy.ai text-to-3D assets for Godot. Use for 3D asset prompts, Meshy preview/refine tasks, GLB downloads, PBR textures, import, collision, scale, provenance, and validation."
argument-hint: "Describe the asset, gameplay role, visual identity, and target scale"
user-invocable: true
---
# Meshy Asset Workflow

## Before Spending Credits

1. Read `.github/instructions/meshy-assets.instructions.md`.
2. Confirm the requested asset's gameplay role, approximate world size, whether it moves, and the visual language it must match.
3. Write a geometry prompt emphasizing one isolated object, strong silhouette, game-readable proportions, no environment, and no ground plane.
4. Write a separate texture prompt with material, wear, palette, and restrained emissive direction.
5. Run a no-credit request preview:

```powershell
./tools/meshy_asset.ps1 -Name "asset-name" -Prompt "geometry prompt" -TexturePrompt "material prompt" -DryRun
```

6. Show the request and obtain explicit user intent before submitting paid generation unless the user's current request already clearly authorizes generation.

## Generate

Set `MESHY_API_KEY` in the terminal environment, never in a file:

```powershell
$env:MESHY_API_KEY = "set-this-directly-in-your-terminal"
./tools/meshy_asset.ps1 -Name "asset-name" -Prompt "geometry prompt" -TexturePrompt "material prompt"
```

The script creates preview and refine tasks, requests GLB/PBR output, polls task status, and saves the model, thumbnail, and provenance manifest under `assets/generated/<asset-name>/`.

Use `-PreviewOnly` to inspect geometry before texturing, `-ModelType standard -TargetPolycount 12000` for deliberate remeshing, and `-HdTexture` only when 4K base color is justified.

## Integrate In Godot

1. Run `./tools/validate_godot.ps1` so Godot imports the GLB.
2. Inspect the imported scene and materials through Godot MCP.
3. Create a wrapper `.tscn` for scale/orientation fixes, collision, gameplay scripts, sockets, and effects.
4. Use primitive or convex collision; do not use trimesh collision for moving objects.
5. Check silhouette and scale from the real gameplay camera, then inspect texture memory and polygon cost.
6. Run import/startup validation again and use MCP runtime logs/screenshots for the integrated scene.

API reference: https://docs.meshy.ai/en/api/text-to-3d
