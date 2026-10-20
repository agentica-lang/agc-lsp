# agc-lsp

An LSP server for Agentica, written in Agentica. Plan: sonic182/agentica#346.

## Map

```text
src/main.agc      entry point: options, then the server loop
src/server.agc    lifecycle and dispatch of requests and notifications
src/rpc.agc       Content-Length framing and JSON-RPC envelopes on stdio
src/check.agc     runs `agentica --json check` and maps its diagnostic to LSP
src/uri.agc       file:// URIs to paths
specs/            BDD features and their step program (steps.agc)
```

## Commands

- `make test`: `agentica check` of the sources and the step program, then `agentica test specs --steps specs/steps.agc`.
- CI (`.github/workflows/ci.yml`) runs `make test` on the release binary named by `AGENTICA_VERSION`.

## Rules

- Behavior changes start with a failing scenario in `specs/`.
- Before writing `.agc` or `.feature` files, load the `agentica-programming` skill (`.agents/skills/`).
