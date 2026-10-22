const vscode = require("vscode");
const { LanguageClient, TransportKind } = require("vscode-languageclient/node");

let client;
let pending = Promise.resolve();

function launcher(command, args) {
  if (process.platform !== "win32") {
    return { command, args };
  }
  const quoted = /\s/.test(command) && !command.startsWith('"') ? `"${command}"` : command;
  return { command: [quoted, ...args].join(" "), args: [], options: { shell: true } };
}

function start() {
  const settings = vscode.workspace.getConfiguration("agentica.server");
  const command = settings.get("path", "agc-lsp");
  const server = { ...launcher(command, ["--stdio"]), transport: TransportKind.stdio };

  client = new LanguageClient(
    "agentica",
    "Agentica",
    { run: server, debug: server },
    {
      documentSelector: [{ scheme: "file", language: "agentica" }],
      initializationOptions: {
        logLevel: settings.get("logLevel", "warning"),
        clientLogLevel: settings.get("clientLogLevel", "error"),
      },
    }
  );
  return client.start();
}

async function stop() {
  const old = client;
  client = undefined;
  if (old) {
    try {
      await old.stop();
    } catch {}
  }
}

function enqueue(action) {
  pending = pending
    .then(action)
    .catch((err) =>
      vscode.window.showErrorMessage(`Agentica language server: ${err.message ?? err}`)
    );
  return pending;
}

function activate(context) {
  context.subscriptions.push(
    vscode.workspace.onDidChangeConfiguration((event) => {
      if (event.affectsConfiguration("agentica.server")) {
        enqueue(async () => {
          await stop();
          await start();
        });
      }
    })
  );
  return enqueue(start);
}

function deactivate() {
  return enqueue(stop);
}

module.exports = { activate, deactivate };
