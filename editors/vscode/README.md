# Agentica for VS Code

Shows the diagnostics of the [agc-lsp](https://github.com/agentica-lang/agc-lsp) language server on `.agc` files.
Syntax highlighting is not part of this extension; it will come from
[agentica-lang/agc-tmlanguage](https://github.com/agentica-lang/agc-tmlanguage).

## Install locally

1. Put `agc-lsp` on your `PATH` (see the Editors section of the main README), with `agentica` 0.8.1 or later. On
   Windows, put the `bin` folder of the repository on `PATH`: the extension starts the command through `cmd.exe`, so
   `agc-lsp` finds `agc-lsp.bat`.
2. From this folder:

   ```sh
   npm install
   npx @vscode/vsce package
   code --install-extension agentica-lsp-0.1.0.vsix
   ```

   `vsce package` copies the repository `LICENSE` into this folder first (git ignores the copy), so it needs no
   prompt.

   Or use "Extensions: Install from VSIX..." in VS Code.

## Settings

- `agentica.server.path` (default `agc-lsp`): the command that starts the server, for example the full path of
  `bin/agc-lsp` (`bin\agc-lsp.bat` on Windows, where the extension runs the command through `cmd.exe`; a path with
  spaces is quoted for you).
- `agentica.server.logLevel` (default `warning`): level of the server log in the Agentica output channel.
- `agentica.server.clientLogLevel` (default `error`): level of the log messages the server sends to the editor.

Changing a setting restarts the server.
