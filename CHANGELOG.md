# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic
Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
