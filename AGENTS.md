# agc-lsp

An LSP server for Agentica, written in Agentica. Plan: sonic182/agentica#346.

## Map

```text
src/main.agc      entry point: options, logging, then the server loop
src/options.agc   command-line options and their defaults
src/logs.agc      the stderr, file and editor (window/logMessage) destinations of std/logger and their levels
src/server.agc    lifecycle and dispatch of requests and notifications; the text of each open file and the std/analysis session that holds it, with its revision; which open files point into which file; the builtin catalog and the workspace folder it keeps
src/events.agc    the reader, check (refresh the session for a file, then check it), catalog and request (definition, references, hover, symbols, workspace symbols) tasks, and the events they send to the server loop
src/asks.agc      which definition, references, hover, symbols and workspace symbol queries run (at most 4), wait, are superseded or cancelled, per request id
src/schedule.agc  which checks run (one at a time, since a session is refreshed by one task), wait or are stale, per file, and the time each is due (changes wait 200 ms)
src/rpc.agc       Content-Length framing and JSON-RPC envelopes on stdio
src/catalog.agc   the builtins from `agentica --json help`, the only process the server starts: loading, parsing, lookups by name, namespace and prefix
src/columns.agc   character indexes of a line to and from UTF-16 code units
src/words.agc     the words of one line: the word at an index, the receiver before a dot, strings and comments
src/cursor.agc    a request position as the line, its characters and the character index, in the negotiated encoding
src/hover.agc     textDocument/hover of a builtin: qualified name, bare call or method call
src/lookup.agc    textDocument/definition, textDocument/references and the hover of names: `Analysis.type_at_partial` for the declaration (signature, doc), the builtin and the type of the expression, `Analysis.refs_partial` for the uses
src/symbols.agc   textDocument/documentSymbol: `Analysis.outline` of a buffer as a hierarchy, and the symbol kinds
src/workspace.agc the workspace folder from initialize, and workspace/symbol: `Analysis.symbol` for the declarations of a name on disk and in the open buffers
src/refusals.agc  which errors of a question to std/analysis only say that the program or the position is what it is
src/places.agc    regions of std/analysis to LSP positions and ranges (UTF-16 or code points); the lines of an open or saved file
src/fields.agc    reads fields of JSON objects with a default
src/completion.agc textDocument/completion of builtins: after `Ns.` or at the start of a word
src/check.agc     maps the first problem of `Analysis.check` to an LSP diagnostic (with relatedInformation)
src/uri.agc       file:// URIs to paths and back
bin/agc-lsp       the launcher editors run: finds the repo through symlinks, compiles src/main.agc once into a cache named by the agentica version and the text of src/*.agc, then `exec agentica run --allow-run -- CACHE.agcb "$@"`
editors/nvim/     Neovim 0.11+ config (agentica.lua)
editors/vscode/   minimal VS Code extension (language client over stdio)
specs/            BDD features and their step program (steps.agc); every scenario starts the server through bin/agc-lsp
VERSION           the release version; CHANGELOG.md lists what each release changed
```

## Commands

- `make test`: `agentica check` of the sources and the step program, then `agentica test specs --steps specs/steps.agc`.
  The first scenario compiles the server (about 3 s) into `$TMPDIR/agc-lsp-specs-cache`; the others reuse it.
- CI (`.github/workflows/ci.yml`) runs `make test` on the release binary named by `AGENTICA_VERSION`.

## Rules

- Behavior changes start with a failing scenario in `specs/`.
- Before writing `.agc` or `.feature` files, load the `agentica-programming` skill (`.agents/skills/`).
- Before writing or reviewing `.agc` code, load the `agentica-code-guidelines` skill too (`.agents/skills/`) and follow
  `site/content/style.md` of Agentica.
- This repo has no `agentica.toml` on purpose: `agentica check` reads the first one it finds in the folders above a
  file, so a manifest here would reach the scenarios. Scenario folders live outside the repo (under `TMPDIR` or
  `/tmp`), and `with_folder` in `specs/steps.agc` fails if an `agentica.toml` exists in any folder above them.
