# Changelog

## 1.3.1 — 2026-09-23

- Fixed zsh prompt and command redraw after the spinner.
- Discarded keys typed while a rewrite is pending, preventing a queued Enter from executing the result or original request.

## 1.3.0 — 2026-09-22

- Added Ctrl+G as a single-chord macOS zsh binding. The previous Ctrl+X Ctrl+I binding still works.

## 1.2.0 — 2026-09-22

- Show a terminal spinner during interactive rewrites on Bash and zsh, clearing it before the result or an error.

## 1.1.1 — 2026-09-22

- Fixed a ShellCheck portability warning in the uninstaller.

## 1.1.0 — 2026-09-22

- Added a self-contained online installer with a private API-key prompt.
- Added macOS zsh support with Ctrl+X Ctrl+I and a separate macOS installer.
- Added platform-specific command generation instructions.

## 1.0.0 — 2026-09-22

- First source release: Responses API CLI, Bash Alt+I binding, secure installer, mocked tests, and opt-in live smoke test.
