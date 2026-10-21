# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic
Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

Needs Agentica 0.8.0 or later.

### Added

- Hover on a function, struct, enum, variant, field or constant shows its signature and its `##` doc, then the type of
  the expression (`type-at` gives them since sonic182/agentica#527).
- Hover on a method call shows the one builtin it is, from the `help` that `type-at` gives, instead of every builtin
  with that name; the catalog still answers when the function has an error. A builtin is also shown from the program
  when the catalog cannot be loaded.
- Go to definition on a local, a parameter, a loop name and a pattern name (sonic182/agentica#530).
- Definition and hover answer in the functions that check while another function has an error, and on the names that
  resolve in a function with an error (`type-at --partial`).

### Changed

- CI and the docs need Agentica 0.8.0.
- A module without `main` is checked in one run (sonic182/agentica#516, #525).

### Removed

- The second check with a stub `main` appended to a module.

## [0.0.1] - 2026-10-21

First release. Needs Agentica 0.7.0 or later.

### Added

- JSON-RPC over stdio with `Content-Length` framing: `initialize`, `shutdown`,
  `exit`; positions in UTF-16, or code points when the client offers `utf-32`.
- Diagnostics of the editor's buffer (full sync) from `agentica check --stdin`,
  200 ms after the last change; at most 4 checks at once, stale ones cancelled.
- Errors in an imported file or in `agentica.toml` shown at the start of the
  file, with `relatedInformation` pointing into that file; saving a file checks
  again the open files whose error points into it.
- Modules without `main` are checked with a stub `main` appended, until
  `agentica check` stops requiring it (sonic182/agentica#516).
- Hover and completion of the builtins from `agentica --json help`.
- Hover with the type of the expression, go to definition (`type-at`) and
  document symbols (`outline`); at most 4 queries at once, a newer request
  supersedes the older one, `$/cancelRequest` is honoured.
- Logs to stderr, the editor (`window/logMessage`) and an optional file, each
  with its own level.
- The `bin/agc-lsp` launcher, a Neovim 0.11+ config and a minimal VS Code
  extension (same version as the server).

[unreleased]: https://github.com/agentica-lang/agc-lsp/compare/0.0.1...HEAD
[0.0.1]: https://github.com/agentica-lang/agc-lsp/releases/tag/0.0.1
