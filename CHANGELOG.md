# Changelog

All notable changes to KeepAwake are documented here. The project follows [Semantic Versioning](https://semver.org).

## [1.1.1] - 2026-10-14

### Fixed
- **Follow Claude Code** treated a working session as idle when the latest transcript entry was very large, such as
  a pasted screenshot, an image Claude read or long command output. Lines of several MB are common, and the reader
  only looked at the last 256 KB. It now reads backwards to the last complete entry, in linear time (a 40 MB line
  takes about 70 ms), up to 64 MB. Results are cached per file, and scanning runs off the main thread.
- Entries with lone UTF-16 surrogates (from output truncated mid-emoji) were rejected by the JSON parser. They are now
  repaired before parsing. A line that still can't be read falls back to Claude Code's `caffeinate` instead of being
  reported as idle. A final line that is still being written is skipped.
- A new session whose transcript has only metadata lines is idle, not "unknown".
- Helper processes run from the `claude` binary (`ugrep`, `rg`) are no longer counted as sessions.

### Added
- `KeepAwake --diagnose` prints how the app sees every Claude Code session and every skipped process, with the reason.
  It is read-only and uses your background-task limit. Command lines are redacted to flags, so prompt text is never
  printed. Run: `/Applications/KeepAwake.app/Contents/MacOS/KeepAwake --diagnose`

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

[1.1.1]: https://github.com/quan105dn/KeepAwake/releases/tag/v1.1.1
[1.1.0]: https://github.com/quan105dn/KeepAwake/releases/tag/v1.1.0
[1.0.0]: https://github.com/quan105dn/KeepAwake/releases/tag/v1.0.0
