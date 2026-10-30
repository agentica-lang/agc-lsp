# agc-lsp

A Language Server Protocol (LSP) server for [Agentica](https://github.com/agentica-lang/agentica), a language for AI agents,
written in Agentica.

> **Status:** early stage. Diagnostics, hover, completion, go to definition, find references, document symbols and
> workspace symbols.

## Features

The server keeps one `std/analysis` session that holds the text of every open document, so an unsaved change is seen by
the checks and the queries of every open file, imported files included. It asks for full document sync.

- Diagnostics: on open, change and save it checks the text of the buffer (its imports and `agentica.toml` resolve from
  its folder) and publishes the first diagnostic. An error in an imported file, or in the `agentica.toml` above the
  file, is shown at the start of the opened file, with the file and position in the message and in
  `relatedInformation`. Typing in or saving a file checks again the open files whose error points into it.
- Hover: a builtin (`String.split`, `puts(`, `xs.split(",")`) shows its signature and description; a function, struct,
  enum, variant, field, constant or type name shows its declaration and `##` doc; any expression also shows its type.
- Completion (trigger `.`): the builtin namespaces and functions, after `String.` or at the start of a word.
- Go to definition and find references of a function, struct, enum, variant, field, constant, type name, local,
  parameter, loop name or pattern name, in the file and the files it imports.
- Document symbols: the outline of the buffer as a hierarchy.
- Workspace symbols: where a name is declared in the `.agc` files below the first workspace folder and in the open
  documents (hidden folders, `agc_libs/` and links are skipped, and a file that does not parse is left out). The query
  must be the whole name with its case (`area`, `Point.x`, `Shape.Circle`, `Models.greet`); there is no prefix or fuzzy
  match.
- Positions are UTF-16, or code points when the client offers `utf-32`.

## Limitations

- Only `.agc` files are checked.
- Queries answer from the session as it was when they arrived, so while you type they can use an older program until
  the next check ends.
- An error in an imported file is published on the opened file, never on the imported one. A file that imports it and
  showed no error is not checked again until it changes, is saved or is reopened.
- Completion knows the builtins only (not your own names, imports or `std/` modules), and `xs.` completes nothing.
  Strings and comments are found by scanning one line, so a heredoc, a string over several lines or code inside `#{}`
  is not recognised. If the builtin catalog cannot be loaded, completion stays empty.
- A function with an error gives no type: definition, hover and references work in the other functions and on the names
  that resolve in that one, not on the expression that has the error. A `std/` module is not on disk, so a name
  declared there has hover but no location. The name of a variant in a `case` pattern (`Shape.Circle(r)`) gives
  nothing yet.
- References are those in the buffer and the files it links; a file that imports the module but is not imported by
  the buffer is not searched.
- A diagnostic in a library or package file has the prefix in its message but no related location.
- Windows: CI runs the server, but neither editor extension has been tried there, and the VS Code extension has not
  been tested in VS Code. A UNC or `\\?\` path is not handled. Killing the editor hard can leave the server running as
  an orphan (the VS Code client starts `agc-lsp.bat` through `cmd.exe`). Paths are compared with case, except the drive
  letter.

## Usage

It needs `agentica` 0.17.0 or later on `PATH`, and `bash` on Linux and macOS or `cmd.exe` on Windows. The server
imports `std/analysis`, which compiles the compiler (about 3 s from source), so the launcher compiles the server once
and keeps the program:

```sh
bin/agc-lsp [--stdio] [--agentica PATH] [--log-level LEVEL] [--client-log-level LEVEL] \
  [--log-format text|json] [--log-file PATH]
```

On Windows the launcher is `bin\agc-lsp.bat`, with the same options. `--agentica PATH` names the binary that prints the
builtin catalog (default: `agentica` from `PATH`); the checks and queries are those of the binary that compiled the
server. `--stdio` is accepted and is the only transport.

The program is kept in the `agc-lsp` folder of the user cache:

| System | Cache folder |
| --- | --- |
| Linux, macOS | `$XDG_CACHE_HOME/agc-lsp`, else `$HOME/.cache/agc-lsp` |
| Windows | `%LOCALAPPDATA%\agc-lsp` |

`AGC_LSP_CACHE` names the cache folder itself, on every system, and wins over the table. A new `agentica` or a change
of `src/*.agc` compiles again (about 3 s); any other start takes about 0.03 s. When a new program is compiled, programs
not used for 30 days are removed. A file system whose rename cannot move a file into place (some network homes) makes
the launcher exit with status 1 and an error that names the cache folder: set `AGC_LSP_CACHE` (or `XDG_CACHE_HOME`) to
a local disk.

Once the program is compiled, a hover or a definition takes tens of milliseconds, and the first check of a file that
imports `std/analysis` (this server does) about a second.

## Editors

`bin/agc-lsp` (`bin\agc-lsp.bat` on Windows) starts the server from wherever the script lives (on Linux and macOS a
symlink to it works too) and passes its arguments on. It uses the `agentica` on `PATH`, or the binary named by the
`AGENTICA` environment variable. To have `agc-lsp` on `PATH`:

```sh
ln -s "$PWD/bin/agc-lsp" ~/.local/bin/agc-lsp
```

On Windows, add the `bin` folder of the repository to `PATH` (then `agc-lsp` finds `agc-lsp.bat`), or give the full
path of `bin\agc-lsp.bat` to the editor. Install `agentica` from the `windows-x86_64` archive of its release and put
its `bin` folder on `PATH` too. `AGENTICA` on Windows must name the `agentica.exe` itself, not a `.cmd` shim, because
the launcher hands it to `agentica` programs that start it as a process, which only runs `.exe` files.

- Neovim 0.11+: [editors/nvim/agentica.lua](editors/nvim/agentica.lua) (a note for 0.10 and for Windows is in the
  file).
- VS Code: [editors/vscode](editors/vscode), a minimal extension to install from a `.vsix` (see its README).

Syntax highlighting is not part of this repository; it will come from
[agentica-lang/agc-tmlanguage](https://github.com/agentica-lang/agc-tmlanguage).

## Logging

The server logs through `std/logger` to three destinations, each with its own level (`debug`, `info`, `warning` or
`error`):

| Destination | Default level | Set with |
| --- | --- | --- |
| stderr (what editors show in their LSP log) | `warning` | `--log-level`, `logLevel` |
| the editor, as `window/logMessage` notifications | `error` | `--client-log-level`, `clientLogLevel` |
| a file of JSON lines, one event per line | the level of stderr | `--log-file PATH`, with `--log-level`, `logLevel` |

- `--log-format text|json` sets the format of stderr (`text` by default). The log file is always JSON lines, appended
  to if it exists; one that cannot be written is warned about and not used.
- The editor can set the two levels in the `initializationOptions` of `initialize`, for example
  `{"logLevel": "debug", "clientLogLevel": "info"}`; an option on the command line wins.
- An invalid option or level is warned about and ignored.
- `debug` logs each message (method and id, never document text) and each check with its duration.

## Development

`make test` runs `agentica check` and the BDD specs in `specs/`; `make wine` checks the Windows build under Wine in
Docker. See [AGENTS.md](AGENTS.md).

## License

Licensed under the [Apache License 2.0](LICENSE).
