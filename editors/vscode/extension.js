const vscode = require("vscode");
const { LanguageClient, TransportKind } = require("vscode-languageclient/node");

let client;

function start() {
  const settings = vscode.workspace.getConfiguration("agentica.server");
  const command = settings.get("path", "agc-lsp");
  const server = { command, args: ["--stdio"], transport: TransportKind.stdio };

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

async function restart() {
  if (client) {
    await client.stop();
  }
  await start();
}

async function activate(context) {
  context.subscriptions.push(
    vscode.workspace.onDidChangeConfiguration((event) => {
      if (event.affectsConfiguration("agentica.server")) {
        restart();
      }
    })
  );
  await start();
}

async function deactivate() {
  if (client) {
    await client.stop();
  }
}

module.exports = { activate, deactivate };
