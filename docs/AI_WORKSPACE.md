# AI Workspace

This workspace is configured for Godot 4.7 development with GitHub Copilot, the local Godot MCP plugin, and Meshy.ai asset generation.

## Toolchain

- Godot project version: 4.7, Forward Plus, Jolt Physics
- Preferred executable: `G:\Godot\Godot_v4.7-stable_win64_console.exe`
- Main scene: `scenes/main.tscn`
- Godot MCP: `http://localhost:9080/mcp`
- Meshy API: Text to 3D v2, using GLB output

`tools/validate_godot.ps1` discovers the 4.7 executable automatically. Override it when needed:

```powershell
$env:GODOT_PATH = "G:\Godot\Godot_v4.7-stable_win64_console.exe"
./tools/validate_godot.ps1
```

The validator imports/parses the project and starts the main scene headlessly for a bounded smoke test. It preserves `project.godot` around editor startup because the MCP plugin removes its runtime-probe autoload during editor shutdown.

## Godot MCP In VS Code

The workspace server is registered in `.vscode/mcp.json` as `godot-mcp`.

1. Open the project in Godot 4.7 with the Godot MCP Native plugin enabled.
2. In the plugin panel, use HTTP transport on port `9080` and start the server. The current endpoint is configured without authentication and should remain bound to localhost.
3. Reload the VS Code window after pulling the workspace configuration.
4. Accept the MCP trust prompt, then use **MCP: List Servers** to start or inspect `godot-mcp` if needed.
5. Select the **Godot Builder** custom agent for editor-aware implementation and runtime debugging.

A healthy endpoint responds to `GET http://localhost:9080/mcp` with the MCP and SSE routes. Godot MCP is the preferred path for scene structure, node ownership, editor state, project health, runtime logs, play/stop, and screenshots.

## Meshy Asset Generation

Store the Meshy key only in your environment. Do not add it to `.env`, VS Code tasks, prompts, manifests, or MCP configuration.

```powershell
$env:MESHY_API_KEY = "enter-the-key-directly-in-your-terminal"
```

Preview a request without consuming credits:

```powershell
./tools/meshy_asset.ps1 `
  -Name "arcane-tower" `
  -Prompt "A low-poly arcane defense tower with a pentagonal stone base, strong readable silhouette, isolated object, no ground plane" `
  -TexturePrompt "Weathered dark stone, brass runes, restrained cyan magical glow, game-ready PBR" `
  -DryRun
```

Remove `-DryRun` to submit preview and refine tasks. The default workflow requests a low-poly, auto-sized, bottom-origin GLB, then applies PBR textures with baked lighting removed. Output is stored under `assets/generated/<name>/` with a preview image and `.meshy.json` provenance manifest.

Use `-PreviewOnly` to evaluate geometry before paying for refinement. Use `-ModelType standard -TargetPolycount 12000` only when low-poly generation cannot deliver the required silhouette. Use `-HdTexture` only for assets that visibly benefit from a 4K base-color map.

After generation:

1. Run `./tools/validate_godot.ps1` to import the GLB.
2. Inspect the imported scene/materials through Godot MCP.
3. Add scale correction, collision, scripts, sockets, and effects in a wrapper scene.
4. Check silhouette at gameplay distance, texture memory, polygon count, origin, orientation, and license.
5. Run validation again and inspect runtime logs/screenshots.

## Project Ownership Map

- `scripts/main.gd`: map orchestration, navigation bake, mana pool, crystal health, startup
- `scripts/game_settings.gd`: reusable tuning and balance values
- `scripts/signal_bus.gd`: cross-system events
- `scripts/wave_manager.gd`: wave composition, spawn timing, lane selection
- `scripts/enemy_database.gd` and enemy data resources: enemy definitions
- `scripts/projectile_pool.gd`: reusable projectile lifetime management
- `scripts/player_animator.gd`: which player clip plays and how fast; owns `scenes/misc/player_visual.tscn`
- `scripts/spell_database.gd`: the one definition of every player spell (cooldown, charge, cast clip/duration, rooting, commit)
- `docs/SKILL_DESIGN.md`: the planned skill roster, skill tree and guild camps
- `docs/ECONOMY.md`: where mana comes from, how it is collected and what it competes for
- `docs/MULTIPLAYER_PLAN.md`: phased plan for five-player co-op, and the single-player assumptions it has to undo
- `scripts/sound_bank.gd`: which file every game event sounds like, and the pooled voices that play it
- `scripts/run_state.gd`: the run's three currencies - shared XP/levels, the team mana pool, enchantment stacks
- `scripts/player_registry.gd`: who is playing, and which one is local to this machine
- `scripts/upkeep_panel.gd`: the build phase between waves - shop, enchantment votes, ready checks
- `scripts/net.gd`: hosting, joining and the peer list; inert until someone hosts
- `scripts/lobby.gd`: the F9 host/join panel
- `tools/mcp.ps1`: shell client for the Godot MCP server, for when the editor holds the project lock
- `scripts/ember_fx.gd`: every fire effect (fireball trail/burst, Rain of Ember, flickering fire light) - see `docs/VFX_TEXTURES.md`
- `tools/build_vfx_textures.gd`: regenerates the placeholder VFX textures in `assets/vfx/`
- `tools/animation_impact.gd`: measures the frame an attack clip connects on; used by the enemy and boss builders
- `tools/player_character_builder.gd`: builds the player visual + `assets/animations/player/lib_player.tres` from `assets/player/`
- `scenes/main.tscn`: pentagonal map, five ordered lanes, navigation region, HUD

The lane order is a contract: White, Blue, Black, Red, Green. Node paths, mana identity, and spawn indices depend on it.

## Agent Customizations

- `.agents/AGENTS.md`: always-on repository contract and verification policy
- `.agents/learnings.md`: concise verified project facts discovered during work
- `.github/copilot-instructions.md`: Copilot entry point
- `.github/instructions/`: file-specific Godot and Meshy practices
- `.github/agents/godot-builder.agent.md`: editor-aware implementation agent
- `.github/skills/meshy-assets/SKILL.md`: reusable asset generation and integration workflow
- `.vscode/tasks.json`: **Godot: Validate Project** and a no-credit Meshy request preview

Official references:

- Godot latest documentation: https://docs.godotengine.org/en/latest/
- Godot 3D import pipeline: https://docs.godotengine.org/en/latest/tutorials/assets_pipeline/importing_3d_scenes/index.html
- Textures for VFX Database: https://simonschreibt.notion.site/Textures-for-VFX-Database-2c72eccccfa84a0eae927d778ad746cc
- Meshy Text to 3D API: https://docs.meshy.ai/en/api/text-to-3d
- VS Code MCP servers: https://code.visualstudio.com/docs/copilot/customization/mcp-servers
