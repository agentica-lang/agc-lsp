import Server from "server"

DEFAULT_AGENTICA = "agentica"

def main() -> Void
  System.exit(Server.serve(Server.start(agentica(System.args()))))
end

def agentica(args: List[String]) -> String
  chosen = DEFAULT_AGENTICA
  index = 0
  while index < args.size
    word = args[index]
    if word == "--agentica" and index + 1 < args.size
      chosen = args[index + 1]
      index += 2
    else
      if word != "--stdio"
        IO.warn("agc-lsp: ignoring the argument #{word}")
      end
      index += 1
    end
  end
  return chosen
end
