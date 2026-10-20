# agc-lsp

A Language Server Protocol (LSP) server for [Agentica](https://github.com/sonic182/agentica), a language for AI agents,
written in Agentica.

> **Status:** early stage. Diagnostics of the file on disk only.

## What it does

- Speaks JSON-RPC over stdio with `Content-Length` framing: `initialize`, `shutdown`, `exit`.
- On `textDocument/didOpen` and `textDocument/didSave` it runs `agentica --json check` on the file on disk and
  publishes its first diagnostic, or an empty list. `textDocument/didClose` clears it. Unsaved changes are not
  checked yet, so the server asks for no `didChange` notifications.
- An error in an imported file is shown at the start of the opened file, with the imported file and position in the
  message.
- Positions are UTF-16 by default, or code points when the client offers `utf-32`.

## Limitations

- Only `.agc` files are checked, and only as they are on disk.
- Each check runs in its own task with a 10 s deadline, so a slow check never delays the next message. A newer
  `didOpen`, `didSave` or `didClose` of the same file cancels its older check, whose result is never published.
- An error in an imported file is published on the file that was opened. Saving the imported file does not refresh
  it: save or reopen the file that imports it.

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
