const assert = require("node:assert/strict");
const fs = require("node:fs/promises");
const { execFileSync } = require("node:child_process");
const os = require("node:os");
const path = require("node:path");
const { downloadAndUnzipVSCode } = require("@vscode/test-electron");

async function smoke(vsix, agentica) {
  const temp = await fs.mkdtemp(path.join(os.tmpdir(), "agc vscode "));
  try {
    const workspace = path.join(temp, "workspace");
    const profile = path.join(temp, "profile");
    const extensions = path.join(temp, "extensions");
    const cache = path.join(temp, "server cache");
    const fixture = path.join(temp, "test");
    const result = path.join(temp, "result");
    const executable = path.join(temp, path.basename(agentica));
    await fs.copyFile(agentica, executable);
    await fs.mkdir(workspace);
    await fs.mkdir(path.join(profile, "User"), { recursive: true });
    await fs.mkdir(fixture);
    await fs.writeFile(path.join(workspace, "sample.agc"), 'def broken() -> Int\n  return "wrong"\nend\n');
    await fs.writeFile(path.join(profile, "User", "settings.json"), JSON.stringify({
      "agentica.server.agenticaPath": executable,
      "extensions.autoUpdate": false,
    }));
    await fs.writeFile(path.join(fixture, "package.json"), JSON.stringify({
      name: "agc-lsp-vsix-test",
      publisher: "local",
      version: "0.0.1",
      engines: { vscode: "*" },
    }));
    const tests = path.join(fixture, "diagnostics.js");
    await fs.copyFile(path.join(__dirname, "diagnostics.js"), tests);

    const code = process.env.VSCODE_EXECUTABLE || await downloadAndUnzipVSCode("1.105.1");
    const resources = process.platform === "darwin" ? "../Resources" : "resources";
    const cli = path.resolve(path.dirname(code), resources, "app", "out", "cli.js");
    const profileArgs = ["--user-data-dir", profile, "--extensions-dir", extensions];
    execFileSync(code, [cli, ...profileArgs, "--install-extension", vsix], {
      env: { ...process.env, ELECTRON_RUN_AS_NODE: "1" },
      stdio: "inherit",
      timeout: 120_000,
    });
    const launch = () => {
      const linuxArgs = process.platform === "linux" ? ["--no-sandbox"] : [];
      execFileSync(code, [
        workspace, ...profileArgs, `--extensionDevelopmentPath=${fixture}`, `--extensionTestsPath=${tests}`,
        "--disable-workspace-trust", "--skip-welcome", "--skip-release-notes", "--disable-updates", ...linuxArgs,
      ], {
        env: { ...process.env, AGC_LSP_CACHE: cache, AGC_LSP_TEST_RESULT: result },
        stdio: "inherit",
        timeout: 150_000,
      });
    };
    launch();
    console.log(await fs.readFile(result, "utf8"));
    const programs = (await fs.readdir(cache)).filter((file) => file.endsWith(".agcb"));
    assert.equal(programs.length, 1);
    const program = path.join(cache, programs[0]);
    const { mtimeMs } = await fs.stat(program);

    await fs.unlink(result);
    launch();
    console.log(await fs.readFile(result, "utf8"));
    assert.equal((await fs.stat(program)).mtimeMs, mtimeMs, "The second launch reused the compiled program");
  } finally {
    await fs.rm(temp, { recursive: true, force: true, maxRetries: 5 });
  }
}

const [vsix, agentica] = process.argv.slice(2);
assert.ok(vsix && agentica, "Usage: node test/vsix.js <vsix> <agentica executable>");
smoke(path.resolve(vsix), path.resolve(agentica)).catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
