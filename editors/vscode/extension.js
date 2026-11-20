const { execFile } = require("node:child_process");
const { constants } = require("node:fs");
const { access, stat } = require("node:fs/promises");
const { homedir } = require("node:os");
const path = require("node:path");
const { promisify } = require("node:util");
const vscode = require("vscode");
const { LanguageClient } = require("vscode-languageclient/node");

const run = promisify(execFile);
const windows = process.platform === "win32";
let client;
let pending = Promise.resolve();

async function findAgentica(configuredPath) {
  if (configuredPath && !path.isAbsolute(configuredPath)) {
    throw new Error("Set agentica.server.agenticaPath to the absolute path of the Agentica executable.");
  }
  const requested = configuredPath || process.env.AGENTICA || "agentica";
  const executable = windows && !configuredPath && !path.extname(requested) ? `${requested}.exe` : requested;
  const pathValue = Object.entries(process.env).find(([key]) => key.toUpperCase() === "PATH")?.[1];
  const directories = (pathValue ?? "").split(path.delimiter).filter(path.isAbsolute);
  if (process.platform === "darwin") {
    directories.push(path.join(homedir(), ".local", "bin"));
  }
  const candidates = path.basename(executable) === executable
    ? directories.map((dir) => path.join(dir, executable))
    : [path.resolve(executable)];
  for (const candidate of candidates) {
    try {
      if ((await stat(candidate)).isFile()) {
        await access(candidate, constants.X_OK);
        return candidate;
      }
    } catch {}
  }
  throw new Error("Agentica executable not found. Install Agentica 0.33.0 or later, or set agentica.server.agenticaPath.");
}

async function checkVersion(executable) {
  let version;
  try {
    const { stdout } = await run(executable, ["--version"], { timeout: 5000, windowsHide: true });
    version = stdout.trim();
  } catch (error) {
    throw new Error(`Could not run Agentica at ${executable}: ${error.message}`);
  }
  const match = /^(\d+)\.(\d+)\.(\d+)(-[\w.-]+)?(?:\+[\w.-]+)?$/.exec(version);
  if (!match || (Number(match[1]) === 0 &&
      (Number(match[2]) < 33 || (Number(match[2]) === 33 && Number(match[3]) === 0 && match[4])))) {
    throw new Error(`Agentica 0.33.0 or later is required. Found ${version || "an unknown version"} at ${executable}.`);
  }
}

function launcher(command, executable) {
  const args = executable ? ["--stdio", "--agentica", executable] : ["--stdio"];
  const env = { ...process.env };
  if (executable) {
    env.AGENTICA = executable;
  }
  if (!windows) {
    return { command, args, options: { env } };
  }
  const argumentsText = executable ? '--stdio --agentica "%AGENTICA%"' : "--stdio";
  return {
    command: process.env.ComSpec || "cmd.exe",
    args: ["/d", "/s", "/v:off", "/c", `""%AGC_LSP_COMMAND%" ${argumentsText}"`],
    options: { env: { ...env, AGC_LSP_COMMAND: command.replace(/^"(.*)"$/, "$1") }, windowsVerbatimArguments: true },
  };
}

async function start(context) {
  const settings = vscode.workspace.getConfiguration("agentica.server");
  const custom = settings.get("path", "");
  const configuredAgentica = settings.get("agenticaPath", "");
  let executable;
  if (!custom || configuredAgentica) {
    executable = await findAgentica(configuredAgentica);
    await checkVersion(executable);
  }
  const command = custom || context.asAbsolutePath(path.join("server", "bin", windows ? "agc-lsp.bat" : "agc-lsp"));
  const server = launcher(command, executable);

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
    .catch((err) => {
      void vscode.window.showErrorMessage(`Agentica language server: ${err.message ?? err}`);
    });
  return pending;
}

function activate(context) {
  context.subscriptions.push(
    vscode.workspace.onDidChangeConfiguration((event) => {
      if (event.affectsConfiguration("agentica.server")) {
        enqueue(async () => {
          await stop();
          await start(context);
        });
      }
    })
  );
  return enqueue(() => start(context));
}

function deactivate() {
  return enqueue(stop);
}

module.exports = { activate, deactivate };
