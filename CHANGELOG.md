# Changelog

All notable changes to KeepAwake are documented here. The project follows [Semantic Versioning](https://semver.org).

## [1.1.0] - 2026-10-14

### Fixed
- **Follow Claude Code** didn't recognise sessions in the VS Code extension: the extension runs Claude Code without
  `caffeinate`, so a session only counted as busy while a shell command was running.
- Interactive sessions stayed "busy" for up to a few minutes after a turn ended, because Claude Code's own
  `caffeinate` outlives the turn.
- Claude Code's Chrome bridge process (`--chrome-native-host`) was listed as a session.

### Changed
- Turn state now comes from Claude Code's transcript (`~/.claude/projects/…/<session>.jsonl`, plus background
  subagents). The per-process session registry (`~/.claude/sessions/<pid>.json`) gives an exact process-to-session
  mapping. `caffeinate` is only a fallback.
- Respects `CLAUDE_CONFIG_DIR`. Detects tool shells regardless of the config directory location.
- The session list shows where each session runs: Terminal, iTerm2, VS Code, VS Code ext, Warp, Ghostty…

## [1.0.0] - 2026-10-11

First public release.

### Added
- Menu bar app with four modes: **Normal**, **Follow Claude Code**, **Running, display off** and **Always awake**.
- Claude Code detection (native and npm installs). It tracks turns in progress and running commands, including
  background tasks, with a configurable age limit.
- Optional **force sleep when done**. It respects system sleep set to *Never*, user `caffeinate`, Time Machine,
  and apps keeping the display on.
- **Lock now** button.
- System settings for *Display off & lock after* and *Sleep after*.
- Launch at login.
- English and Vietnamese UI.
- About screen with version, license and source links.
- Local diagnostic log at `~/Library/Logs/KeepAwake.log`.

[1.1.0]: https://github.com/quan105dn/KeepAwake/releases/tag/v1.1.0
[1.0.0]: https://github.com/quan105dn/KeepAwake/releases/tag/v1.0.0
