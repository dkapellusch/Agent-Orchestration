# Changelog

All notable changes to Agent Orchestrator are documented in this file.

## [1.0.0] - 2026-02-09

### Added
- `--output` flag with `normal`, `brief`, and `verbose` modes
- Completion summary now shows session ID and modified files list
- Per-iteration summary lists modified files (when <= 10)
- `VERSION` file for release tracking
- `CHANGELOG.md` for change documentation
- `docs/ARCHITECTURE.md` with technical architecture documentation

### Security
- Set `chmod 600` on OpenCode MCP temp config files
- Mount OpenCode config directory as read-only (`:ro`) in Docker sandbox

## [0.1.0] - 2026-02-09

### Added
- GLM 4.7 to medium tier models

### Fixed
- OpenCode with Anthropic sandbox: avoid shell quoting issues by passing prompt as file

## [0.0.9] - 2026-02-08

### Added
- Integration tests for model selection, rate limiting, and cost tracking
- Iteration logs persisted to `.ralph/{session}/logs/`

### Fixed
- Gemini model hang during agent execution
- OpenCode hanging: pass prompt as arg instead of stdin
- Stall detection hanging on pipeline kill
- `local` usage outside function in stall kill code
- Empty agent output now triggers model failover
- OpenCode sandbox network allowlist and JSON parsing errors

## [0.0.1] - 2026-02-07

### Added
- Initial release
- Iterative agent loop with `ralph loop` / `ao` command
- Multi-sandbox support: Anthropic (`srt`), Docker, none
- Rate limit detection and automatic model failover
- Session management with human-readable IDs (e.g., `swift-fox-runs`)
- Struggle detection (no-progress, short iterations)
- File change tracking via `git status`
- Iteration history and summaries
- Mid-loop context injection (`--add-context`)
- Model tier selection (`high`, `medium`, `low`) with fallbacks
- Mission Control Protocol for agent behavior guidance
- Completion detection with `<promise>COMPLETE</promise>` markers
- Completion validation mode (`--completion-mode validate`)
- Budget tracking and limits (`--budget`)
- GSD (Get Shit Done) structured workflow mode
- Docker container sandbox with auth forwarding
- Cost tracking and reporting (`ralph cost`)
- Session statistics (`ralph stats`)
- Session cleanup (`ralph cleanup`)
- Shared agent management (`ralph agents`)
- One-line installer script
- Container renamed from generic to `agent-sandbox`
