# Project Instructions

Read `.agents/AGENTS.md` before changing this repository and follow it as the project contract.

This is a Godot 4.7 Forward Plus 3D tower-defense/action project. The main scene is `scenes/main.tscn`. The autoloads are `GameSettings`, `SignalBus`, `ProjectilePool`, and `MCPRuntimeProbe`.

For every implementation task:

1. Find the smallest owning script or scene and its nearest call site.
2. Preserve the existing typed GDScript, reusable scene, autoload, and signal patterns.
3. Use the workspace `godot-mcp` server for editor-aware scene/runtime operations when available.
4. Run `./tools/validate_godot.ps1` after any source, scene, resource, project setting, import, or generated-asset change. Report import and startup results.
5. Add a concise entry to `.agents/learnings.md` only when a newly verified fact will prevent future mistakes.

Never store API keys in the repository. Meshy generation uses `MESHY_API_KEY` and `tools/meshy_asset.ps1`; always dry-run before a paid request.
