const { copyFileSync, mkdirSync, readdirSync, rmSync } = require("node:fs");
const path = require("node:path");

const root = path.resolve(__dirname, "../..");
const server = path.join(__dirname, "server");
rmSync(server, { recursive: true, force: true });
mkdirSync(path.join(server, "bin"), { recursive: true });
mkdirSync(path.join(server, "src"));

const sources = readdirSync(path.join(root, "src")).filter((file) => file.endsWith(".agc"));
const files = ["agentica.toml", "bin/agc-lsp", "bin/agc-lsp.bat", "bin/prepare.agc",
  ...sources.map((file) => path.join("src", file))];
for (const file of files) {
  copyFileSync(path.join(root, file), path.join(server, file));
}
copyFileSync(path.join(root, "LICENSE"), path.join(__dirname, "LICENSE"));
