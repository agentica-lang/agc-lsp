# agc-lsp

A Language Server Protocol (LSP) server for [Agentica](https://github.com/sonic182/agentica), a language for AI agents,
written in Agentica.

> **Status:** early stage. Diagnostics of the text in the editor's buffer.

## What it does

- Speaks JSON-RPC over stdio with `Content-Length` framing: `initialize`, `shutdown`, `exit`.
- It asks for full document sync. On `textDocument/didOpen`, `textDocument/didChange` and `textDocument/didSave` it
  runs `agentica --json check --stdin PATH` on the text of the buffer (sent on stdin, so a file that is not saved, or
  not on disk, is checked as the editor shows it; its imports and `agentica.toml` resolve from its folder) and
  publishes its first diagnostic, or an empty list. `textDocument/didClose` clears it.
- An error in an imported file, or in the `agentica.toml` that `agentica check` finds above the file, is shown at the
  start of the opened file, with the imported file and position in the message and in `relatedInformation`, whose
  location points into that file (the start of the file for an error at a key of `agentica.toml`).
- Saving a file checks again the other open files whose current diagnostic points into it, so fixing an imported file
  clears the error shown on the files that import it.
- Positions are UTF-16 by default, or code points when the client offers `utf-32`.

## Limitations

- Only `.agc` files are checked. Only the text of the file itself comes from the buffer: an imported file is read from
  disk, so an unsaved change in it is not seen by the files that import it.
- Each check runs in its own task with a 10 s deadline, so a slow check never delays the next message. At most 4
  checks run at once (the cap counts check tasks, and a cancelled checker process may still be ending for a
  moment); the other files wait in order. A newer `didOpen`, `didChange`, `didSave` or `didClose` of the
  same file cancels its older check, whose result is never published, so quick changes publish only the diagnostics
  of the last text. A check requested by `didChange` waits 200 ms for the next change before it starts (a newer change
  replaces its text and restarts the wait); `didOpen`, `didSave` and the re-check of the files that import a saved file
  start at once.
- A check that fails (timeout, the checker cannot run, no diagnostic from a failing check) publishes nothing and
  logs a warning (see Logging), so the editor keeps the diagnostics it already shows. A crash of a check task is
  logged as an error and also leaves the previous diagnostics.
- An error in an imported file is published on the file that was opened, never on the imported file itself. Saving a
  file checks again only the open files whose current diagnostic points into it. A file that imports it and showed no
  error is not checked again until it is saved or reopened, and neither is a file whose first check is still running
  when the save comes.
- A diagnostic in a library module or package file (not an absolute path) has the prefix in its message but no related
  location.

## Usage

It needs `agentica` (0.6.0 or later) on `PATH`, and `--allow-run` to start it:

```sh
agentica --allow-run src/main.agc [--stdio] [--agentica PATH] [--log-level LEVEL] [--client-log-level LEVEL] \
  [--log-format text|json] [--log-file PATH]
```

`--agentica PATH` names the binary that checks the files (default: `agentica` from `PATH`). `--stdio` is accepted
for clients that pass it; stdio is the only transport. The logging options are described below.

## Editors

`bin/agc-lsp` starts the server from wherever the script lives (a symlink to it works too) and passes its arguments on.
It runs the `agentica` on `PATH`, or the binary named by the `AGENTICA` environment variable. To have `agc-lsp` on
`PATH`:

```sh
ln -s "$PWD/bin/agc-lsp" ~/.local/bin/agc-lsp
```

- Neovim 0.11+: [editors/nvim/agentica.lua](editors/nvim/agentica.lua) (a note for 0.10 is in the file).
- VS Code: [editors/vscode](editors/vscode), a minimal extension to install from a `.vsix` (see its README).

Syntax highlighting is not part of this repository; it will come from
[agentica-lang/agc-tmlanguage](https://github.com/agentica-lang/agc-tmlanguage).

## Logging

The server logs through `std/logger` to three destinations, each with its own level (`debug`, `info`, `warning` or
`error`). Nothing below the level of a destination reaches it.

| Destination | Default level | Set with |
| --- | --- | --- |
| stderr (what editors show in their LSP log) | `warning` | `--log-level`, `logLevel` |
| the editor, as `window/logMessage` notifications | `error` | `--client-log-level`, `clientLogLevel` |
| a file of JSON lines, one event per line | the level of stderr | `--log-file PATH`, with `--log-level`, `logLevel` |

- `--log-level LEVEL` sets the level of stderr and of the log file; the file has no level of its own.
- `--client-log-level LEVEL` sets the level of the log messages sent to the editor. The types are 1 (error),
  2 (warning), 3 (info) and 4 (log, for debug). The handler starts after the `initialize` request has been answered,
  so the editor gets nothing before the answer.
- `--log-format text|json` sets the format of stderr: `TIME LEVEL message key=value ...` (the default) or one JSON
  object per line. The log file is always JSON lines, appended to if it exists. A file that cannot be written is warned
  about and not used.
- The editor can set the two levels in the `initializationOptions` of `initialize`, for example
  `{"logLevel": "debug", "clientLogLevel": "info"}`. An option on the command line wins over the same setting from the
  editor.
- An invalid option (an unknown level or format, an option without a value, an unknown argument) is warned about and
  ignored, as if it was not given. A level the editor sets in `initializationOptions` then applies, or else the
  default. A level from the editor that is not valid is also warned about and ignored.

What is logged:

- `debug`: each message received and sent (the method and the id, never document text), and the start and the end of
  each check with its URI, generation and duration in milliseconds.
- `info`: the start (with the `agentica` binary used), the initialization (with the position encoding) and the
  shutdown.
- `warning`: a check that failed (timeout, the checker cannot run, status 1 without a diagnostic), a URI that is not
  a local file, an ignored argument or a setting that is not valid.
- `error`: a crashed check task or input reader, and a message without a `Content-Length` header, which ends the
  session.

stdout carries only the protocol: the log messages for the editor are written by the main task of the server, like
the diagnostics.

## Development

```sh
make test   # agentica check, then the BDD specs in specs/ (agentica test)
```

## License

Licensed under the [Apache License 2.0](LICENSE).
