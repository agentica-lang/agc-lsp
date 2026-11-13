## Starts the language server on stdio.

import Logs from "logs"
import Options from "options"
import Server from "server"

private

def main() -> Void
  options = Logs.start(Options.parse(System.args()))
  System.exit(Server.serve(Server.start(options)))
end
