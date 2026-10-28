# agc-lsp

An LSP server for Agentica, written in Agentica. Plan: agentica-lang/agentica#346.

## Map

```text
src/main.agc      entry point: options, logging, then the server loop
src/options.agc   command-line options and their defaults
src/logs.agc      the stderr, file and editor (window/logMessage) destinations of std/logger and their levels
src/server.agc    lifecycle and dispatch of requests and notifications; the text of each open file and the std/analysis session that holds it, and the table of entries the tasks share; which open files point into which file; the builtin catalog and the workspace folder it keeps
src/events.agc    the reader, check (start from the entry of a file, refresh, check, publish the new entry), catalog and request (definition, references, hover, symbols, workspace symbols) tasks, and the events they send to the server loop
src/asks.agc      which definition, references, hover, symbols and workspace symbol queries run (at most 4), wait, are superseded or cancelled, per request id
src/schedule.agc  which checks run (at most 4, one per file), wait or are stale, per file, and the time each is due (changes wait 200 ms)
src/entries.agc   the ATS table of std/analysis entries (`Analysis.entry`, `Analysis.adopt`) by path of the open file: start a session from one, publish one, drop those of closed files
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
agentica.toml     `[style]` only: the layout rules of every .agc file (see Rules)
bin/prepare.agc   cache key (agentica binary, version, src/*.agc), cache folder (AGC_LSP_CACHE, else per OS), compile once with an atomic rename (an error that suggests AGC_LSP_CACHE if the file system has none), prune; prints the path of the compiled server
bin/agc-lsp       the launcher for Linux and macOS: finds the repo through symlinks, asks prepare.agc for the program, then `exec agentica run -- PROGRAM "$@"`
bin/agc-lsp.bat   the same launcher for Windows (cmd.exe, `%~dp0`)
compose.yaml      Docker Compose service `wine`: the Windows build of agentica under Wine, the repo mounted read-only
docker/wine/      its Dockerfile (agentica.exe of `AGENTICA_VERSION`, verified against SHA256SUMS) and `smoke.sh`
editors/nvim/     Neovim 0.11+ config (agentica.lua)
editors/vscode/   minimal VS Code extension (language client over stdio)
specs/            BDD features and their step program (steps.agc); smoke.agc is the session that `make smoke` and the Windows CI run; every scenario starts the server through the shell launcher bin/agc-lsp (Git Bash on Windows), with AGC_LSP_CACHE set to its own cache; bin/agc-lsp.bat is covered by smoke.agc only; specs/unix/ holds the features that need env, bash, ln or a folder called c: (the Windows CI skips them)
VERSION           the release version; CHANGELOG.md lists what each release changed
```

## Commands

- `make test`: `agentica check` of the sources, `bin/prepare.agc`, `specs/smoke.agc` and the step program, then `make
  smoke` (a whole session through `bin/agc-lsp`), then `agentica test specs --steps specs/steps.agc`. The first
  scenario compiles the server (about 3 s) into `AGC_LSP_CACHE`, which the steps set to
  `$TMPDIR/agc-lsp-specs-cache` (`TEMP` or `TMP` when `TMPDIR` is not set, `/tmp` last); the others reuse it. `make
  smoke` uses the same folder.
- On Windows CI runs `bin\agc-lsp.bat` in `cmd` with `specs/smoke.agc`, then `agentica test specs/*.feature`, which
  leaves out `specs/unix/`.
- `make wine`: `wine-check` and `wine-smoke`, the Windows build of agentica under Wine in Docker (`compose.yaml`,
  `docker/wine/`; the version is `AGENTICA_VERSION` of the CI file). `wine-check` runs `agentica.exe check` on the
  sources and the step program; `wine-smoke` runs `bin/prepare.agc` with Windows paths (the cache folder is a Docker
  volume that already exists, so the folder creation of `prepare.agc`, `Dir.mkdir_private`, is not exercised) and the
  smoke session on the program. It does not run `bin\agc-lsp.bat` (Wine's `cmd` differs; real Windows CI is its
  authority) nor `agentica test` (`Dir.mkdir_private` fails under Wine). `make test` does not use
  Docker.
- CI (`.github/workflows/ci.yml`) runs `make test` on the release binary named by `AGENTICA_VERSION`.

## Rules

- Behavior changes start with a failing scenario in `specs/`.
- Before writing `.agc` or `.feature` files, load the `agentica-programming` skill (`.agents/skills/`).
- Before writing or reviewing `.agc` code, load the `agentica-code-guidelines` skill too (`.agents/skills/`) and follow
  `site/content/style.md` of Agentica.
- The `agentica.toml` at the root holds only `[style]` (`blank_line_after_end` and `max_line_width`, which `agentica
  check` and `agentica run` enforce on every file below it, so the launcher fails on badly laid out sources) and no
  `[package]` or dependencies. Agentica creates a self-ignored `_build/` next to it. `agentica check` reads the first
  manifest it finds in the folders above a file, so the scenarios must not sit below the repo: their folders live
  outside it (under `TMPDIR` or `/tmp`), and `with_folder` in `specs/steps.agc` fails if an `agentica.toml` exists in
  any folder above them.

## Design notes

- The cache of std/analysis is not threaded through the loop. A `Session` holds only the text of the open documents; what
  `refresh` kept for a file is an `Analysis.Entry` in an `ATS` table (`src/entries.agc`), by path. A check adopts the
  entry of its file, refreshes, checks and publishes the new entry; a definition, references or hover query adopts it
  and never publishes. So checks of different files run at once (each refreshes a session of its own, and two entries
  are two caches, never merged) and no refresh is lost to another.
- An entry is only a shortcut: std/analysis uses it while the files and buffers say what they said, and checks again
  otherwise. A check that was cancelled may or may not have published, one that ends late may publish an older entry
  over a newer one, and the loop drops the entries of closed files on every close and report: all of these cost time, never a wrong
  answer. Entries of two files share nothing, not even the modules both import.
- Two URIs for one path (a `localhost` authority, a double slash) share one open text and one session entry, the last
  text written wins; each URI is still checked and published on its own, and the text stays until the last is closed.
- Queries answer for the text the buffer had when they arrived, even if it changed or was closed meanwhile; a refusal
  of the analysis (an error in the program, no expression there) answers `null` and logs at debug level only.
- The compiled server is moved into the cache with `Path.rename` (atomic, never replaces a file), so two starts may
  both compile and no lock is needed. `KEY.agcb.used` stamps the use because agentica cannot set a modification time.
