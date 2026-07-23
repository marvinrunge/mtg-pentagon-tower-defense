---
description: "Use when editing Godot scenes, GDScript, resources, navigation, physics, UI, waves, enemies, player abilities, or project settings."
applyTo: "**/*.{gd,tscn,tres,godot}"
---
# Godot 4.7 Guidelines

- Follow `.agents/AGENTS.md` and target Godot 4.7 APIs: https://docs.godotengine.org/en/latest/
- Use typed GDScript and explicit return types. Type arrays and dictionaries when their shape is stable.
- Keep balance and globally reused timing/dimensions in `GameSettings`; use `SignalBus` only for cross-system communication.
- Keep the White, Blue, Black, Red, Green lane order stable.
- Put movement and collision decisions in `_physics_process`; use `move_and_slide` for `CharacterBody3D`.
- Cache stable node references with typed `@onready`; use groups for dynamic collections and exported `NodePath`/resources for configurable dependencies.
- Prefer composition with reusable `.tscn` scenes and custom `Resource` data. Avoid adding another autoload unless the service must exist across every scene.
- Keep imported 3D assets immutable. Add collision, scripts, scale fixes, sockets, and gameplay metadata in an inherited or wrapper scene.
- For scene structure edits, prefer Godot MCP node/scene tools and verify node `owner` persistence.
- After edits, run `./tools/validate_godot.ps1`; for behavior changes use Godot MCP runtime tools and inspect logs when available.
