import Server from "server"

DEFAULT_AGENTICA = "agentica"

def main() -> Void
  System.exit(Server.serve(Server.start(agentica(System.args()))))
end

def agentica(args: List[String]) -> String
  if args.size == 2 and args[0] == "--agentica"
    return args[1]
  end
  return DEFAULT_AGENTICA
end
