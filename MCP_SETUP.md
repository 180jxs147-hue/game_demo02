# Godot MCP Toolkit setup

This project uses Godot MCP Toolkit v1.0.2 in `addons/godot_mcp_toolkit`.
The plugin is enabled in `project.godot`.

## Requirements

- Godot 4.7 editor (the project targets Godot 4.7)
- Node.js 22 or newer
- `@npgamedev/godot-mcp-server` (installed globally on this machine, or fetched by `npx`)

## Connect

1. Open this project in Godot. The bottom **MCP Toolkit** panel should show a listener on `127.0.0.1:6550` (or another port in 6550–6560).
2. Restart the MCP client or start a new Codex chat in this trusted project so it loads the server configuration.
3. Run a read-only MCP tool such as `project_get_settings` to verify the editor connection. The panel should then show a connected peer.

The root `.mcp.json` is for clients that read that format. Codex reads the project-scoped `.codex/config.toml`; both launch the same Windows `cmd /c npx -y @npgamedev/godot-mcp-server` bridge with `GODOT_MCP_PROJECT_PATH` set to this project. No token is stored in either file; the plugin manages its local authentication token.
