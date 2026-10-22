# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic
Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

Needs Agentica 0.8.1 or later.

### Added

- Find references (`textDocument/references`): the uses of a name in the buffer and the files it imports, with the
  declaration unless `context.includeDeclaration` is false.
- Workspace symbols (`workspace/symbol`): where a name is declared in the `.agc` files below the workspace folder and
  in the open documents. The name must be written in full (no prefix or fuzzy match); an empty query or a client
  without a workspace folder gets an empty list.
- Hover on a function, struct, enum, variant, field or constant shows its signature and its `##` doc, then the type of
  the expression.
- Hover and go to definition on a type name in a signature, a field or a type argument, also through an import
  (`Models.User`), with the declaration and its doc (sonic182/agentica#531).
- Hover on a method call shows the one builtin it is, instead of every builtin with that name; the catalog still
  answers when the function has an error. A builtin is also shown from the program when the catalog cannot be loaded.
- Go to definition on a local, a parameter, a loop name and a pattern name.
- Definition and hover answer in the functions that check while another function has an error, and on the names that
  resolve in a function with an error.
- Typing in a file, and closing it with unsaved text, checks again the open files whose error points into it.

### Changed

- The checks and the queries run in-process with `std/analysis`, over one session that holds the text of every open
  document, instead of starting `agentica` for each. An unsaved change in an imported file is seen by the files that
  import it. Checks run one at a time and a check refreshes the session for its file; the refreshed session is kept
  only when no document changed meanwhile.
- Workspace symbols search the open documents as the editor shows them, besides the files on disk.
- `bin/agc-lsp` compiles the server once into `${XDG_CACHE_HOME:-$HOME/.cache}/agc-lsp`, named by the version of
  agentica and the text of `src/*.agc`, and runs the compiled program, which starts in a few tens of milliseconds
  instead of about 3 s. A server that does not compile prints the error of agentica and exits with status 1.
- `--agentica PATH` names only the binary that prints the catalog of builtins.
- CI and the docs need Agentica 0.8.1.
- A module without `main` is checked in one run (sonic182/agentica#516, #525).

### Removed

- The second check with a stub `main` appended to a module.
- The deadline of 10 s for a check or a query, the limit of 4 checks at once (checks run one at a time) and the
  processes that ran `agentica check`, `type-at`, `refs`, `outline` and `symbol`.

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
