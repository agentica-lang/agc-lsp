# agc-lsp

An LSP server for Agentica, written in Agentica. Plan: sonic182/agentica#346.

## Map

```text
src/main.agc      entry point: options, logging, then the server loop
src/options.agc   command-line options and their defaults
src/logs.agc      the stderr, file and editor (window/logMessage) destinations of std/logger and their levels
src/server.agc    lifecycle and dispatch of requests and notifications; the text of each open file; which open files point into which file; the builtin catalog it keeps
src/events.agc    the reader, check and catalog tasks, and the events they send to the server loop
src/schedule.agc  which checks run (at most 4), wait or are stale, per file, each with the text to check and the time it is due (changes wait 200 ms)
src/rpc.agc       Content-Length framing and JSON-RPC envelopes on stdio
src/catalog.agc   the builtins from `agentica --json help`: loading, parsing, lookups by name, namespace and prefix
src/columns.agc   character indexes of a line to and from UTF-16 code units
src/words.agc     the words of one line: the word at an index, the receiver before a dot, strings and comments
src/cursor.agc    a request position as the line, its characters and the character index, in the negotiated encoding
src/hover.agc     textDocument/hover of a builtin: qualified name, bare call or method call
src/completion.agc textDocument/completion of builtins: after `Ns.` or at the start of a word
src/check.agc     runs `agentica --json check --stdin` on a buffer and maps its diagnostic to LSP (with relatedInformation)
src/uri.agc       file:// URIs to paths and back
bin/agc-lsp       the launcher editors run: finds the repo through symlinks, then `exec agentica --allow-run src/main.agc "$@"`
editors/nvim/     Neovim 0.11+ config (agentica.lua)
editors/vscode/   minimal VS Code extension (language client over stdio)
specs/            BDD features and their step program (steps.agc)
```

## Commands

- `make test`: `agentica check` of the sources and the step program, then `agentica test specs --steps specs/steps.agc`.
- CI (`.github/workflows/ci.yml`) runs `make test` on the release binary named by `AGENTICA_VERSION`.

## Rules

- Behavior changes start with a failing scenario in `specs/`.
- Before writing `.agc` or `.feature` files, load the `agentica-programming` skill (`.agents/skills/`).
- Before writing or reviewing `.agc` code, load the `agentica-code-guidelines` skill too (`.agents/skills/`) and follow
  `site/content/style.md` of Agentica.
- This repo has no `agentica.toml` on purpose: `agentica check` reads the first one it finds in the folders above a
  file, so a manifest here would reach the scenarios. Scenario folders live outside the repo (under `TMPDIR` or
  `/tmp`), and `with_folder` in `specs/steps.agc` fails if an `agentica.toml` exists in any folder above them.
