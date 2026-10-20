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
  logs a warning on stderr, so the editor keeps the diagnostics it already shows. A crash of a check task is only
  logged on stderr and also leaves the previous diagnostics.
- An error in an imported file is published on the file that was opened, never on the imported file itself. Saving a
  file checks again only the open files whose current diagnostic points into it. A file that imports it and showed no
  error is not checked again until it is saved or reopened, and neither is a file whose first check is still running
  when the save comes.
- A diagnostic in a library module or package file (not an absolute path) has the prefix in its message but no related
  location.

## Usage

It needs `agentica` (0.5.0 or later) on `PATH`, and `--allow-run` to start it:

```sh
agentica --allow-run src/main.agc [--stdio] [--agentica PATH]
```

`--agentica PATH` names the binary that checks the files (default: `agentica` from `PATH`). `--stdio` is accepted
for clients that pass it; stdio is the only transport.

## Development

```sh
make test   # agentica check, then the BDD specs in specs/ (agentica test)
```

## License

Licensed under the [Apache License 2.0](LICENSE).
