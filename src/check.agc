## Runs `agentica --json check` on the text of a buffer and maps its diagnostic to LSP.

import Columns from "columns"
import Logger from "std/logger"
import Uri from "uri"

CHECK_TIMEOUT_MS = 10_000
SHORTEST_WAIT_MS = 1
READ_TIMEOUT_MS = 10_000
SEVERITY_ERROR = 1
CHUNK_BYTES = 1_048_576
SINGLE_SEND_CHARS = 262_144
UTF16 = "utf-16"
RELATED_MESSAGE = "the error is here"
NO_MAIN_MESSAGE = "a program must declare exactly one main"
STUB_MAIN = "\n\ndef main() -> Void\nend\n"

struct Place
  line: Int
  column: Int
end

## Returns the first diagnostic of the text as LSP diagnostics, or an empty list when the check passes.
export def diagnostics(agentica: String, path: String, text: String, encoding: String) -> Result[List[Json]]
  deadline = Time.now_ms() + CHECK_TIMEOUT_MS
  first = try problems(agentica, path, text, deadline)
  if first.size == 0
    return ok([])
  end
  if !without_main?(first[0], path)
    return ok([diagnostic(first[0], path, text, encoding)])
  end
  second = try problems(agentica, path, "#{text}#{STUB_MAIN}", deadline)
  if second.size == 0
    return ok([])
  end
  if in_stub?(second[0], path, text)
    return ok([diagnostic(first[0], path, text, encoding)])
  end
  return ok([diagnostic(second[0], path, text, encoding)])
end

## Returns the URI that the related location of the first diagnostic points into, or an empty text.
export def points_into(found: List[Json]) -> String
  if found.size == 0
    return ""
  end
  none: List[Json] = []
  entries = JSON.list(JSON.get(found[0], "relatedInformation").unwrap_or(JSON.null())).unwrap_or(none)
  if entries.size == 0
    return ""
  end
  location = JSON.get(entries[0], "location").unwrap_or(JSON.null())
  return text(location, "uri")
end

def failed(message: String) -> Result[List[Json]]
  Logger.warning(message)
  return error(message)
end

def without_main?(found: Json, path: String) -> Bool
  if text(found, "code") != "CHECK-MAIN" or !text(found, "message").starts_with?(NO_MAIN_MESSAGE)
    return false
  end
  return Uri.same_path?(text(found, "file"), path)
end

def problems(agentica: String, path: String, source: String, deadline: Int) -> Result[List[Json]]
  case run(agentica, path, source, deadline)
    ok(problem) ->
      if problem == ""
        return ok([])
      end
      case JSON.parse(problem)
        ok(found) -> return ok([found])
        error(message) -> return failed("the diagnostic of #{path} is not JSON: #{message}")
      end
    error(message) -> return failed("cannot check #{path}: #{message}")
  end
end

def in_stub?(found: Json, path: String, source: String) -> Bool
  if !Uri.same_path?(text(found, "file"), path)
    return false
  end
  return place(found, "start").line > source.split("\n").size
end

def run(agentica: String, path: String, text: String, deadline: Int) -> Result[String]
  checker = try Process.spawn_captured(agentica, ["--json", "check", "--stdin", path], ".", remaining(deadline))
  result = collect(checker, text, deadline)
  Process.close(checker)
  return result
end

def collect(checker: Process, text: String, deadline: Int) -> Result[String]
  sent = feed(checker, text, deadline)
  captured = Process.output(checker, remaining(deadline))
  if !captured.ok? and !sent.ok?
    return error(unsent(sent))
  end
  output = try captured
  status = try Process.wait(checker, remaining(deadline))
  case status
    0 ->
      if !sent.ok?
        return error(unsent(sent))
      end
      return ok("")
    1 ->
      problem = last_line(output.stderr)
      if problem == "" and !sent.ok?
        return error(unsent(sent))
      elsif problem == ""
        return error("agentica exited with status 1 and no diagnostic")
      end
      return ok(problem)
    _ -> return error("agentica exited with status #{status}: #{output.stderr.strip}")
  end
end

def unsent(sent: Result[Void]) -> String
  return "cannot send the buffer: #{sent.message}"
end

def feed(checker: Process, text: String, deadline: Int) -> Result[Void]
  if text.length <= SINGLE_SEND_CHARS
    try Process.send(checker, text, remaining(deadline))
    return Process.close_stdin(checker, remaining(deadline))
  end
  rest = text.to_bytes
  while rest.size > 0
    try Process.send_bytes(checker, rest.take(CHUNK_BYTES), remaining(deadline))
    rest = rest.drop(CHUNK_BYTES)
  end
  return Process.close_stdin(checker, remaining(deadline))
end

def remaining(deadline: Int) -> Int
  left = deadline - Time.now_ms()
  if left < SHORTEST_WAIT_MS
    return SHORTEST_WAIT_MS
  end
  return left
end

def last_line(text: String) -> String
  lines = text.strip.split("\n")
  return lines[lines.size - 1].strip
end

def diagnostic(found: Json, path: String, source: String, encoding: String) -> Json
  file = text(found, "file")
  message = text(found, "message")
  help = text(found, "help")
  if help != ""
    message = "#{message}\nhelp: #{help}"
  end
  start = place(found, "start")
  stop = place(found, "end")
  key_path = text(found, "key_path")
  fields: Map[String, Json] = {
    "severity": JSON.from(SEVERITY_ERROR),
    "code": JSON.from(text(found, "code")),
    "source": JSON.from("agentica"),
  }
  if Uri.same_path?(file, path)
    fields = fields.put("range", span(source.split("\n"), start, stop, encoding))
  else
    message = "#{where(file, key_path, start)}: #{message}"
    fields = fields.put("range", JSON.object({"start": origin(), "end": origin()}))
    if file.starts_with?("/")
      fields = fields.put("relatedInformation", JSON.array([related(found, encoding)]))
    end
  end
  return JSON.object(fields.put("message", JSON.from(message)))
end

def related(found: Json, encoding: String) -> Json
  file = text(found, "file")
  key_path = text(found, "key_path")
  start = place(found, "start")
  stop = place(found, "end")
  range = JSON.object({"start": origin(), "end": origin()})
  if key_path == "" and start.line > 0
    range = span(source_lines(file), start, stop, encoding)
  end
  location = JSON.object({"uri": JSON.from(Uri.of_path(file)), "range": range})
  return JSON.object({"location": location, "message": JSON.from(RELATED_MESSAGE)})
end

def span(lines: List[String], start: Place, stop: Place, encoding: String) -> Json
  return JSON.object({"start": position(start, lines, encoding), "end": position(stop, lines, encoding)})
end

def where(file: String, key_path: String, start: Place) -> String
  if key_path != ""
    return "#{file} (#{key_path})"
  elsif start.line == 0
    return file
  end
  return "#{file}:#{start.line}:#{start.column}"
end

def position(at: Place, lines: List[String], encoding: String) -> Json
  line = not_negative(at.line - 1)
  character = not_negative(at.column - 1)
  if encoding == UTF16 and line < lines.size
    character = Columns.utf16_width(lines[line], character)
  end
  return JSON.object({"line": JSON.from(line), "character": JSON.from(character)})
end

def origin() -> Json
  return JSON.object({"line": JSON.from(0), "character": JSON.from(0)})
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
