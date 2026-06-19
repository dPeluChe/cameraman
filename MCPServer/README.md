# cameraman-mcp

An [MCP](https://modelcontextprotocol.io) (Model Context Protocol) server for
**Project Studio** (labs-cameraman). It lets an MCP client — Claude Desktop,
Claude Code, or any MCP-capable agent — inspect and edit your Project Studio
projects through tools, driving the same non-destructive `EngineKit` editing
logic the app uses.

> Because all editing is metadata in `project.json`, the server can split clips,
> toggle mute, add items, and apply effects without ever touching source media.

## What it can do

| Area | Tools |
|------|-------|
| **Inspect** | `list_projects`, `get_project`, `list_adjustments` |
| **Create / record** | `create_empty_project`, `start_recording`, `stop_recording` |
| **Cut / split** | `split_clip`, `delete_clip` |
| **Mute audio/video** | `set_track_muted`, `set_track_volume`, `set_clip_audio_muted` |
| **Add items** | `add_image_clip`, `add_video_clip`, `add_audio_clip`, `add_color_clip`, `add_text_overlay` |
| **Edit clips** | `move_clip`, `update_clip`, `trim_clip`, `delete_range` |
| **Tracks** | `add_track`, `remove_track`, `move_video_track`, `set_track_locked` |
| **Effects** | `add_adjustment`, `update_adjustment`, `remove_adjustment`, `clear_adjustments` |
| **Overlays** | `add_overlay`, `list_overlays`, `update_overlay`, `delete_overlay` |
| **Canvas** | `set_canvas_layout`, `set_background` |
| **Manage** | `duplicate_project`, `rename_project`, `set_tags`, `search_projects`, `merge_projects`, `export_bundle`, `import_bundle` |
| **AI (local)** | `suggest_silence_edits`, `suggest_chapters` |
| **Export** | `export_project`, `get_job_status`, `list_jobs`, `cancel_job` |
| **Transcribe** | `transcribe_project`, `get_captions` |

> **Export & transcription are async.** `export_project` / `transcribe_project`
> return a `jobId` immediately; poll `get_job_status` until `status` is `success`.
> Exports land in the project's `renders/` folder. Jobs are in-memory per server
> session. Transcription is on-device (Apple Silicon only).

> **Recording** captures the main display via `ScreenCaptureKit`. `start_recording`
> returns immediately and `stop_recording` finalizes the take into a new project.
> The host process must hold **Screen Recording** permission (and **Microphone**
> if `captureMicAudio` is set) — grant it to whichever app launches the server.

Typical flow: call `get_project` to discover track ids and clip ids, then call
an editing tool with those ids.

### Effects (`add_adjustment`)

Effects are extensible and target a **layer** so you can, e.g., make the camera
sepia while the background goes black & white in the same block:

- Visual kinds: `sepia`, `monochrome`, `brightness`, `contrast`, `saturation`,
  `colorControls`, `vibrance`, `hue`, `invert`, `vignette`, `gaussianBlur`
  (any CoreImage filter name also works as a fallback).
- Audio kinds: `audioPitch` (params `cents` or `semitones`), `audioGain`.
- `target`: `frame` (whole output), `screen`, `camera`, `background`, `audio`.
- `parameters`: effect-specific scalars, e.g. `{"intensity": 0.8}`,
  `{"semitones": -3}`.

Example: deepen the voice and sepia the camera for a recording clip

```jsonc
// 1) deeper voice
add_adjustment { projectId, trackId, clipId, kind: "audioPitch",
                 target: "audio", parameters: { "semitones": -4 } }
// 2) sepia camera only
add_adjustment { projectId, trackId, clipId, kind: "sepia",
                 target: "camera", parameters: { "intensity": 1.0 } }
// 3) black & white background only
add_adjustment { projectId, trackId, clipId, kind: "monochrome",
                 target: "background" }
```

## Build

Requires macOS 13+ and a Swift toolchain (it links `EngineKit`).

```bash
cd MCPServer
swift build -c release
# binary at: .build/release/cameraman-mcp
```

## Register with an MCP client

> **App users:** the binary ships inside the app at
> `CameramanApp.app/Contents/Helpers/cameraman-mcp` (built and signed by the
> Xcode build phase). Settings → Integrations auto-detects it and fills the
> snippets — no manual build needed. The instructions below are for running the
> package standalone (contributors / non-app use).

The server speaks MCP over **stdio**. Point your client at the built binary.

> **Point it at the app's projects.** The app is sandboxed and stores projects
> inside its container, but this server is a plain CLI binary that defaults to
> `~/Library/Application Support/ProjectStudio/Projects/`. Set
> **`CAMERAMAN_PROJECTS_DIR`** to the app's container Projects folder so both see
> the same projects. The app's Settings → Integrations panel shows the exact path
> and generates these snippets with it filled in. The container path is:
> `~/Library/Containers/dev.dpeluche.CameramanApp/Data/Library/Application Support/ProjectStudio/Projects`
> (append `.debug` to the bundle id for debug builds). Omit the env var to use the
> non-container default.

Claude Desktop (`claude_desktop_config.json`):

```json
{
  "mcpServers": {
    "cameraman": {
      "command": "/absolute/path/to/cameraman/MCPServer/.build/release/cameraman-mcp",
      "args": [],
      "env": { "CAMERAMAN_PROJECTS_DIR": "/Users/you/Library/Containers/dev.dpeluche.CameramanApp/Data/Library/Application Support/ProjectStudio/Projects" }
    }
  }
}
```

Claude Code:

```bash
claude mcp add cameraman -e CAMERAMAN_PROJECTS_DIR="$HOME/Library/Containers/dev.dpeluche.CameramanApp/Data/Library/Application Support/ProjectStudio/Projects" -- /absolute/path/to/cameraman/MCPServer/.build/release/cameraman-mcp
```

Codex CLI (`~/.codex/config.toml`):

```toml
[mcp_servers.cameraman]
command = "/absolute/path/to/cameraman/MCPServer/.build/release/cameraman-mcp"
args = []
env = { CAMERAMAN_PROJECTS_DIR = "/Users/you/Library/Containers/dev.dpeluche.CameramanApp/Data/Library/Application Support/ProjectStudio/Projects" }
```

> **One editor at a time.** The server and the app write `project.json` without
> cross-process locking — don't drive heavy edits from MCP while the same project
> is open in the app, or the app's autosave and the server can clobber each other.
> **Recording via MCP** (`start_recording`) needs Screen Recording permission
> granted to the MCP client app (Claude Desktop/Code/Codex), not to Cameraman.

## Protocol notes

- Transport: newline-delimited JSON-RPC 2.0 on stdin/stdout (implemented
  directly in Foundation — no external SDK).
- `stdout` is reserved for protocol messages; logs go to `stderr`.
- Implements `initialize`, `tools/list`, `tools/call`, and `ping`.
