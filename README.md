# agc-lsp

A Language Server Protocol (LSP) server for [Agentica](https://github.com/sonic182/agentica), a language for AI agents,
written in Agentica.

> **Status:** early stage. Diagnostics of the file on disk only.

## What it does

- Speaks JSON-RPC over stdio with `Content-Length` framing: `initialize`, `shutdown`, `exit`.
- On `textDocument/didOpen` and `textDocument/didSave` it runs `agentica --json check` on the file on disk and
  publishes its first diagnostic, or an empty list. `textDocument/didClose` clears it. Unsaved changes are not
  checked yet, so the server asks for no `didChange` notifications.
- An error in an imported file, or in the `agentica.toml` that `agentica check` finds above the file, is shown at the
  start of the opened file, with the imported file and position in the message and in `relatedInformation`, whose
  location points into that file (the start of the file for an error at a key of `agentica.toml`).
- Saving a file checks again the other open files whose current diagnostic points into it, so fixing an imported file
  clears the error shown on the files that import it.
- Positions are UTF-16 by default, or code points when the client offers `utf-32`.

## Limitations

- Only `.agc` files are checked, and only as they are on disk.
- Each check runs in its own task with a 10 s deadline, so a slow check never delays the next message. At most 4
  checks run at once (the cap counts check tasks, and a cancelled checker process may still be ending for a
  moment); the other files wait in order. A newer `didOpen`, `didSave` or `didClose` of the same file
  cancels its older check, whose result is never published.
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

It needs `agentica` (0.5.0 or later) on `PATH`, and `--allow-run` to start it:

```sh
agentica --allow-run src/main.agc [--stdio] [--agentica PATH] [--log-level LEVEL] [--client-log-level LEVEL] \
  [--log-format text|json] [--log-file PATH]
```

`--agentica PATH` names the binary that checks the files (default: `agentica` from `PATH`). `--stdio` is accepted
for clients that pass it; stdio is the only transport. The logging options are described below.

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
  2 (warning), 3 (info) and 4 (log, for debug). Nothing is sent before the `initialize` request has been answered.
- `--log-format text|json` sets the format of stderr: `TIME LEVEL message key=value ...` (the default) or one JSON
  object per line. The log file is always JSON lines, appended to if it exists. A file that cannot be written is warned
  about and not used.
- The editor can set the two levels in the `initializationOptions` of `initialize`, for example
  `{"logLevel": "debug", "clientLogLevel": "info"}`. An option on the command line wins over the same setting from the
  editor.
- An unknown level or format, an option without a value and an unknown argument are warned about and ignored; the
  default stays.

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
