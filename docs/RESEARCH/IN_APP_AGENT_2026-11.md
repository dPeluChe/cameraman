# In-app assistant: design and research (2026-11)

Decided 2026-11-07. The assistant inside Cameraman runs the agent CLIs the user already has, so it uses
their subscription, and Cameraman never handles AI credentials. First backend: Claude Code. Ships in 0.8.

## Decisions

| Question | Decision |
|---|---|
| Subscription or API key | The user's subscription, through the agent's own CLI and login |
| First agent | Claude Code, run as `claude -p` with stream-json |
| More agents | One internal `AgentBackend` interface; ACP next (Codex, Gemini CLI, Copilot, OpenCode, Goose…); pi and a plain API key later |
| Sandbox | Removed in 0.8. Distribution is the notarized DMG only; no Mac App Store build for now |
| Tools | Only Cameraman's MCP server (in-app HTTP, `127.0.0.1:8765`); the agent's own file, shell and web tools are off |

## Why not pi for Claude

pi (now `earendil-works/pi`, v1.5, MIT, Node ≥ 22.19, native MCP, RPC mode over JSONL) logs in to Claude with
its own OAuth. Anthropic's terms bar that: apps may not "offer Claude.ai login into their own applications" or
"route requests through Free, Pro, Max, or Ultra plan credentials", and tools that call Claude directly get no
subscription allowance. pi stays a good later backend for ChatGPT/Codex, Copilot, xAI and API keys of many
providers. Sources: https://github.com/earendil-works/pi, https://code.claude.com/docs/en/legal-and-compliance

## Claude subscriptions in third-party apps: where it stands

- Jan 2026: Anthropic blocked third-party harnesses that spoofed Claude Code; Apr 4, 2026: subscriptions cut off
  for third-party harnesses.
- May 13, 2026 (effective Jun 15): reinstated, with a catch. Programmatic use (`claude -p`, the Agent SDK,
  third-party apps such as T3 Code, Zed, Conductor, OpenClaw) draws from a separate monthly **Agent SDK credit**
  billed at API rates, not rolling over: Pro $20, Max 5x $100, Max 20x $200. Then extra usage, if enabled.
  Interactive use (Claude Code in a terminal, claude.ai) keeps the plan's normal limits.
  https://venturebeat.com/technology/anthropic-reinstates-openclaw-and-third-party-agent-usage-on-claude-subscriptions-with-a-catch
- The legal page allows "an end user […] signing in to the unmodified Claude Code binary with their own Claude
  subscription". The binary must not be modified and its login methods must stay; the app must not pay for,
  resell or intermediate usage, nor collect or store credentials. https://code.claude.com/docs/en/legal-and-compliance
- Others doing the same: T3 Code runs the installed `claude` with its login
  (https://github.com/pingdotgg/t3code/blob/main/docs/user/providers-claude.md); OpenCode 2.2.3 (Oct 30, 2026)
  runs the installed `claude` through the Agent SDK (https://cellcog.ai/blog/opencode-claude-subscription/).
- Risk to watch: the CLI help says `--bare` (which skips OAuth) may become the default for `-p`. If it does, pass
  whatever opts out, or move the chat to an interactive session.

So a chat turn in Cameraman spends the user's Agent SDK credit. A later "terminal" mode can open interactive
`claude` inside the app, already connected to the MCP server, to use the plan's normal limits.

## Claude Code backend

One process per turn, resumed by session id:

```
claude -p <message> --output-format stream-json --verbose --include-partial-messages
  --mcp-config <0600 temp file: {"mcpServers":{"cameraman":{"type":"http","url":…,"headers":{"Authorization":"Bearer …"}}}}>
  --strict-mcp-config --tools "" --allowedTools mcp__cameraman --permission-mode dontAsk
  --setting-sources "" --system-prompt <project context> [--resume <session id>]
```

- `--tools ""` turns off Claude Code's built-in tools; `--strict-mcp-config` ignores the user's other MCP servers;
  `dontAsk` denies anything not allowed, so the run never waits on a prompt nobody can answer.
- The MCP token goes in a temp file, not the command line, so other processes cannot read it from `ps`.
- Events read: `system/init` (session id), `stream_event` text deltas, `assistant` tool_use blocks, `user`
  tool_result blocks, `result` (final text, cost, errors).
- The binary is found through the user's login shell (`$SHELL -lc 'command -v claude'`), since apps launched from
  Finder do not get the terminal's PATH. Login stays `claude auth login` in a terminal.

Code: `EngineKit/Sources/EngineKit/Agent/`, app side `AssistantChatModel` / `AssistantChatView`. Opt-in end-to-end
tests that spend a few cents of the local plan: `CAMERAMAN_AGENT_E2E=1 swift test --filter ClaudeCodeBackendTests`
(EngineKit) and `--filter MCPAgentE2ETests` (MCPServer).

## Interface for more agents

```
AgentBackend: send(prompt, context) -> AsyncStream<AgentEvent>, cancel()
AgentEvent: started(session) · text(delta) · toolStarted(name) · toolFinished(name, ok) · finished(cost?) · failed(message)
```

- ACP (https://agentclientprotocol.com): JSON-RPC over stdio. The agent owns login; MCP servers go in
  `session/new` → `mcpServers` (http form). One client covers every ACP agent. No official Swift SDK; the wire
  format is small enough to write. Claude through ACP goes via the Agent SDK adapter, so the direct backend stays.
- Codex: OpenAI does not split interactive and programmatic plan usage; `codex app-server` and ACP adapters
  exist. "Sign in with ChatGPT" (Sep 2026) covers local and open-source apps.
- API key: the Messages API from Swift, for users without any CLI (and for a possible store build).

## Sandbox

A process launched by a sandboxed app inherits the sandbox, so the user's `claude` could not read `~/.claude` or
its keychain item. 0.8 drops the sandbox (hardened runtime and notarization stay). Data moves on first launch
from `~/Library/Containers/<bundle id>/Data` to `~/Library/Application Support/Cameraman/` (`ContainerMigration`):
projects, WhisperKit models (`Models/`, was `Documents/huggingface`), recordings and preferences. Debug builds
use `Cameraman-Debug`, keeping them apart from the release app as their containers did.
