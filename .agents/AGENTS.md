# MTG Pentagon Tower Defense Agent Rules

## Project Boundaries

- Target Godot 4.7 and GDScript. Prefer `G:\Godot\Godot_v4.7-stable_win64_console.exe`; `tools/validate_godot.ps1` resolves it automatically.
- `scripts/main.gd` owns map orchestration, navigation baking, shared mana, and entity startup.
- `scripts/game_settings.gd` owns reusable tuning values. Do not hardcode new balance values, dimensions, cooldowns, spawn timing, or global debug switches in feature scripts.
- `scripts/signal_bus.gd` owns cross-system events. Prefer direct typed calls inside one scene and signals across unrelated systems.
- `scripts/wave_manager.gd` owns wave composition and enemy spawn cadence. Keep enemy definitions in the existing data/database layer.
- Preserve the five lane order: White, Blue, Black, Red, Green. Scene node paths and lane indices rely on it.

## Workflow

1. Inspect the owning script, scene, and nearest call site before editing.
2. Use the `godot-mcp` tools when `http://localhost:9080/mcp` is available for editor state, scene edits, script validation, project health, and runtime inspection. Use text edits for reviewable source changes.
3. Keep `.tscn` edits minimal. Prefer the Godot MCP scene/node tools for structural edits so node ownership and UndoRedo are preserved.
4. After changing scripts, scenes, resources, imports, project settings, or generated assets, run `./tools/validate_godot.ps1`. Do not complete the task until both import/parse and main-scene startup pass.
5. For runtime behavior changes, also exercise the affected behavior through Godot MCP when feasible and inspect editor/runtime logs.

## Godot Practices

- Use static types for public state, signals, exported properties, node references, function parameters, and return values.
- Use `_physics_process` for movement/physics and `_process` for presentation or non-physics timers.
- Cache stable node references with typed `@onready`; avoid repeated tree searches in per-frame code.
- Use `queue_free`, deferred calls, or awaited frames when changing the tree during physics/navigation callbacks.
- Prefer reusable scenes and `Resource` data over large procedural node construction in scripts.
- Connect signals once and disconnect only when the emitter can outlive the receiver in a way Godot cannot manage automatically.
- Treat generated GLB files as source assets: keep gameplay collision, navigation, scale correction, and scripts in wrapper scenes, not inside imported scenes.

## Meshy Assets And Secrets

- Use `tools/meshy_asset.ps1`; never call paid generation unless the user clearly requested it.
- Use `-DryRun` first. Default to low-poly, GLB, auto-size, bottom origin, PBR refine, and lighting removal for game assets.
- Store `MESHY_API_KEY` only in the environment. Never write or print it, commit `.env`, or place it in MCP/task configuration.
- Keep generated assets and their `.meshy.json` provenance in `assets/generated/<asset-name>/`. Review silhouette, scale, materials, polygon cost, license, and collision before use.

## Learnings

- After resolving a non-obvious, reusable project issue, append one concise dated entry to `.agents/learnings.md` with the verified fact and the command or code path that proved it.
- Do not record speculation, one-off task status, secrets, machine-specific credentials, or facts already documented there.

