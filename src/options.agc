## Parses the command-line options of the server and holds their defaults.

export DEFAULT_AGENTICA = "agentica"
export DEFAULT_LEVEL = "warning"
export DEFAULT_CLIENT_LEVEL = "error"
export DEFAULT_FORMAT = "text"
LEVELS = Set.new(["debug", "info", "warning", "error"])
FORMATS = Set.new(["text", "json"])
VALUE_OPTIONS = Set.new(["--agentica", "--log-level", "--client-log-level", "--log-format", "--log-file"])

## Holds the options given on the command line, with the problems found while reading them.
export struct Options
  ## Is the executable that runs the checks.
  agentica: String
  ## Is the log level of stderr and the log file, or empty for the default.
  level: String
  ## Is the log level of the editor, or empty for the default.
  client_level: String
  ## Is the format of the stderr lines, or empty for the default.
  format: String
  ## Is the path of the log file, or empty for none.
  file: String
  ## Lists what was wrong with the arguments.
  problems: List[String]
end

## Returns the options of the arguments, with a problem for each argument that is ignored or rejected.
export def parse(args: List[String]) -> Options
  options = Options(agentica: DEFAULT_AGENTICA, level: "", client_level: "", format: "", file: "", problems: [])
  index = 0
  while index < args.size
    word = args[index]
    if takes_value?(word) and index + 1 < args.size
      options = set(options, word, args[index + 1])
      index += 2
    elsif takes_value?(word)
      options = options.with(problems: options.problems.push("the option #{word} needs a value"))
      index += 1
    elsif word != "--stdio"
      options = options.with(problems: options.problems.push("ignoring the argument #{word}"))
      index += 1
    else
      index += 1
    end
  end
  return options
end

## Returns true when the name is a log level.
export def level?(name: String) -> Bool
  return LEVELS.include?(name)
end

def takes_value?(word: String) -> Bool
  return VALUE_OPTIONS.include?(word)
end

def set(options: Options, word: String, value: String) -> Options
  case word
    "--agentica" -> return options.with(agentica: value)
    "--log-file" -> return options.with(file: value)
    "--log-level" ->
      if level?(value)
        return options.with(level: value)
      end
      return rejected(options, "log level", word, value)
    "--client-log-level" ->
      if level?(value)
        return options.with(client_level: value)
      end
      return rejected(options, "log level", word, value)
    _ ->
      if FORMATS.include?(value)
        return options.with(format: value)
      end
      return rejected(options, "log format", word, value)
  end
end

def rejected(options: Options, what: String, word: String, value: String) -> Options
  problem = "unknown #{what} #{value} for #{word}; keeping the default"
  return options.with(problems: options.problems.push(problem))
end
