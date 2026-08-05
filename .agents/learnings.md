# Verified Project Learnings

Add only durable facts that were confirmed by a command or controlling code path.

- 2026-07-23: The project targets Godot 4.7; the matching Windows console binary is `G:\Godot\Godot_v4.7-stable_win64_console.exe`. Verified with file metadata and `tools/validate_godot.ps1`.
- 2026-07-23: `http://localhost:9080/mcp` is a healthy Godot MCP Native HTTP endpoint using MCP protocol `2025-03-26`. Verified by an HTTP GET returning status 200.
- 2026-07-23: A headless 4.7 editor quit can report Jolt RID/ObjectDB/resource allocator leaks while scripts and scenes import successfully. `tools/validate_godot.ps1` filters only those known shutdown diagnostics and still fails on other engine errors.
- 2026-07-23: Main-scene startup depends on deferred navigation baking before `MainController.spawn_entities()`. Verified in `scripts/main.gd`; runtime smoke tests must allow enough time for the bake and startup path.
- 2026-07-23: Pooled projectiles must retain casters through `WeakRef` and resolve a live `Node3D` at impact; passing a freed typed caster fails argument validation before `take_damage()` runs. Verified in `scripts/projectile.gd` with import/startup validation and Godot MCP play mode.
- 2026-07-23: Lane `ManaSource` origins already sit on the gameplay surface, so bottom-origin Meshy wrappers must keep their model at local `y = 0`; a negative offset buries the asset. Verified from `scenes/main.tscn` placeholder bounds and Godot MCP wrapper AABBs.
