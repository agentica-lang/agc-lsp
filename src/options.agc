export DEFAULT_AGENTICA = "agentica"
export DEFAULT_LEVEL = "warning"
export DEFAULT_CLIENT_LEVEL = "error"
export DEFAULT_FORMAT = "text"
LEVELS = Set.new(["debug", "info", "warning", "error"])
FORMATS = Set.new(["text", "json"])
VALUE_OPTIONS = Set.new(["--agentica", "--log-level", "--client-log-level", "--log-format", "--log-file"])

export struct Options
  agentica: String
  level: String
  client_level: String
  format: String
  file: String
  problems: List[String]
end

export def parse(args: List[String]) -> Options
  options = Options(agentica: DEFAULT_AGENTICA, level: "", client_level: "", format: "", file: "", problems: [])
  index = 0
  while index < args.size
    word = args[index]
    if !takes_value?(word)
      if word != "--stdio"
        options = options.with(problems: options.problems.push("ignoring the argument #{word}"))
      end
      index += 1
    elsif index + 1 >= args.size
      options = options.with(problems: options.problems.push("the option #{word} needs a value"))
      index += 1
    else
      options = set(options, word, args[index + 1])
      index += 2
    end
  end
  return options
end

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
