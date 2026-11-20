# Agentica LSP for VS Code

Agentica LSP provides diagnostics, completion, hover, go to definition, references, formatting, and rename for
`.agc` files. It includes the language server and installs
[Agentica Language](https://marketplace.visualstudio.com/items?itemName=agentica-lang.agentica-language) for syntax highlighting.

## Installation

1. Install [Agentica](https://github.com/agentica-lang/agentica/releases) 0.33.0 or later.
2. Install **Agentica LSP** (`agentica-lang.agentica-lsp`) from the VS Code Extensions view.
3. Open an `.agc` file. The extension compiles the bundled server on first use and reuses the compiled program on
   subsequent starts.

The extension looks for Agentica on `PATH`. On macOS it also checks `~/.local/bin/agentica`, including when VS Code
starts from the Dock. If Agentica is installed elsewhere, set `agentica.server.agenticaPath` to its absolute path.

## Settings

- `agentica.server.path` starts a custom language server command. Leave empty to use the bundled launcher.
- `agentica.server.agenticaPath` sets the absolute path of the Agentica executable used by the launcher and language server.
- `agentica.server.logLevel` controls the server's stderr log in the Agentica output channel. Defaults to `warning`.
- `agentica.server.clientLogLevel` controls the log messages the server sends to VS Code. Defaults to `error`.

Changing a setting restarts the server.

## Build a VSIX

With Node.js 22 or later, run these commands from `editors/vscode`:

```sh
npm ci
npx vsce package --out agentica-lsp.vsix
code --install-extension agentica-lsp.vsix
```

You can also use **Extensions: Install from VSIX…** in VS Code.
