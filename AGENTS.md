# agc-lsp

An LSP server for Agentica, written in Agentica. Plan: sonic182/agentica#346.

## Map

```text
src/main.agc      entry point: options, then the server loop
src/server.agc    lifecycle and dispatch of requests and notifications; which open files point into which file
src/events.agc    the reader and check tasks, and the events they send to the server loop
src/schedule.agc  which checks run (at most 4), wait or are stale, per file
src/rpc.agc       Content-Length framing and JSON-RPC envelopes on stdio
src/check.agc     runs `agentica --json check` and maps its diagnostic to LSP (with relatedInformation)
src/uri.agc       file:// URIs to paths and back
specs/            BDD features and their step program (steps.agc)
```

## Commands

- `make test`: `agentica check` of the sources and the step program, then `agentica test specs --steps specs/steps.agc`.
- CI (`.github/workflows/ci.yml`) runs `make test` on the release binary named by `AGENTICA_VERSION`.

## Rules

- Behavior changes start with a failing scenario in `specs/`.
- Before writing `.agc` or `.feature` files, load the `agentica-programming` skill (`.agents/skills/`).
- This repo has no `agentica.toml` on purpose: `agentica check` reads the first one it finds in the folders above a
  file, so a manifest here would reach the scenarios. Scenario folders live outside the repo (under `TMPDIR` or
  `/tmp`), and `with_folder` in `specs/steps.agc` fails if an `agentica.toml` exists in any folder above them.
