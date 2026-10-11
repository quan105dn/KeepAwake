# Changelog

All notable changes to KeepAwake are documented here. The project follows [Semantic Versioning](https://semver.org).

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

[1.0.0]: https://github.com/quan105dn/KeepAwake/releases/tag/v1.0.0
