# agc-lsp

A Language Server Protocol (LSP) server for [Agentica](https://github.com/sonic182/agentica), a language for AI agents,
written in Agentica.

> **Status:** early stage. Diagnostics of the file on disk only.

## What it does

- Speaks JSON-RPC over stdio with `Content-Length` framing: `initialize`, `shutdown`, `exit`.
- On `textDocument/didOpen` and `textDocument/didSave` it runs `agentica --json check` on the file on disk and
  publishes its first diagnostic, or an empty list. `textDocument/didClose` clears it. Unsaved changes are not
  checked yet.
- Positions are UTF-16 by default, or code points when the client offers `utf-32`.

## Usage

It needs `agentica` (0.5.0 or later) on `PATH`, and `--allow-run` to start it:

```sh
agentica --allow-run src/main.agc [--agentica PATH]
```

`--agentica PATH` names the binary that checks the files (default: `agentica` from `PATH`).

## Development

```sh
make test   # agentica check, then the BDD specs in specs/ (agentica test)
```

## License

Licensed under the [Apache License 2.0](LICENSE).
