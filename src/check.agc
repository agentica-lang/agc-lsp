CHECK_TIMEOUT_MS = 60000
READ_TIMEOUT_MS = 10000
SEVERITY_ERROR = 1
SURROGATE_START = 65536

struct Place
  line: Int
  column: Int
end

export def diagnostics(agentica: String, path: String, encoding: String) -> List[Json]
  case run(agentica, path)
    ok(problem) ->
      if problem == ""
        return []
      end
      case JSON.parse(problem)
        ok(found) -> return [diagnostic(found, path, encoding)]
        error(message) ->
          IO.warn("agc-lsp: the diagnostic of #{path} is not JSON: #{message}")
          return []
      end
    error(message) ->
      IO.warn("agc-lsp: cannot check #{path}: #{message}")
      return []
  end
end

def run(agentica: String, path: String) -> Result[String]
  checker = try Process.spawn_captured(agentica, ["--json", "check", path], ".", CHECK_TIMEOUT_MS)
  output = try Process.output(checker, CHECK_TIMEOUT_MS)
  status = try Process.wait(checker, CHECK_TIMEOUT_MS)
  case status
    0 -> return ok("")
    1 -> return ok(output.stderr.strip)
    _ -> return error("agentica exited with status #{status}: #{output.stderr.strip}")
  end
end

def diagnostic(found: Json, path: String, encoding: String) -> Json
  file = text(found, "file")
  message = text(found, "message")
  help = text(found, "help")
  if help != ""
    message = "#{message}\nhelp: #{help}"
  end
  start = place(found, "start")
  stop = place(found, "end")
  range = JSON.object({"start": origin(), "end": origin()})
  if file == path
    lines = source_lines(path)
    range = JSON.object({"start": position(start, lines, encoding), "end": position(stop, lines, encoding)})
  else
    message = "#{file}:#{start.line}:#{start.column}: #{message}"
  end
  return JSON.object({
    "range": range,
    "severity": JSON.from(SEVERITY_ERROR),
    "code": JSON.from(text(found, "code")),
    "source": JSON.from("agentica"),
    "message": JSON.from(message),
  })
end

def position(at: Place, lines: List[String], encoding: String) -> Json
  line = not_negative(at.line - 1)
  character = not_negative(at.column - 1)
  if encoding == "utf-16" and line < lines.size
    character = utf16_width(lines[line], character)
  end
  return JSON.object({"line": JSON.from(line), "character": JSON.from(character)})
end

def origin() -> Json
  return JSON.object({"line": JSON.from(0), "character": JSON.from(0)})
end

def utf16_width(line: String, characters: Int) -> Int
  width = 0
  for char in line.slice(0, smaller(characters, line.length)).split("")
    if String.code(char) >= SURROGATE_START
      width += 2
    else
      width += 1
    end
  end
  return width + not_negative(characters - line.length)
end

def smaller(a: Int, b: Int) -> Int
  if a < b
    return a
  end
  return b
end

def not_negative(n: Int) -> Int
  if n < 0
    return 0
  end
  return n
end

def source_lines(path: String) -> List[String]
  return File.read_text(path, READ_TIMEOUT_MS).unwrap_or("").split("\n")
end

def place(found: Json, edge: String) -> Place
  range = JSON.get(found, "range").unwrap_or(JSON.null())
  at = JSON.get(range, edge).unwrap_or(JSON.null())
  line = JSON.get(at, "line").unwrap_or(JSON.from(0))
  column = JSON.get(at, "column").unwrap_or(JSON.from(0))
  return Place(line: JSON.int(line).unwrap_or(0), column: JSON.int(column).unwrap_or(0))
end

def text(found: Json, key: String) -> String
  value = JSON.get(found, key).unwrap_or(JSON.from(""))
  return JSON.string(value).unwrap_or("")
end
