const assert = require("node:assert/strict");
const { writeFile } = require("node:fs/promises");
const { setTimeout: delay } = require("node:timers/promises");
const vscode = require("vscode");

exports.run = async () => {
  const uri = vscode.Uri.joinPath(vscode.workspace.workspaceFolders[0].uri, "sample.agc");
  const document = await vscode.workspace.openTextDocument(uri);
  await vscode.window.showTextDocument(document);
  assert.equal(document.languageId, "agentica");
  const extension = vscode.extensions.getExtension("agentica-lang.agentica-lsp");
  assert.ok(extension, "The VSIX extension is installed");

  for (let attempt = 0; attempt < 360; attempt++) {
    const diagnostic = vscode.languages.getDiagnostics(uri).find(
      (item) => item.source === "agentica" && item.severity === vscode.DiagnosticSeverity.Error && /Int/.test(item.message)
    );
    if (extension.isActive && diagnostic) {
      await writeFile(process.env.AGC_LSP_TEST_RESULT, diagnostic.message);
      return;
    }
    await delay(250);
  }
  assert.fail("No Agentica type error arrived for sample.agc");
};
