## Runs `agentica --json check` on the text of a buffer and maps its diagnostic to LSP.

import Fields from "fields"
import Places from "places"
import Proc from "proc"
import Logger from "std/logger"
import Uri from "uri"

CHECK_TIMEOUT_MS = 10_000
SEVERITY_ERROR = 1
RELATED_MESSAGE = "the error is here"
NO_MAIN_MESSAGE = "a program must declare exactly one main"
STUB_MAIN = "\n\ndef main() -> Void\nend\n"

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
  return Fields.text(location, "uri")
end

def failed(message: String) -> Result[List[Json]]
  Logger.warning(message)
  return error(message)
end

def without_main?(found: Json, path: String) -> Bool
  message = Fields.text(found, "message")
  if Fields.text(found, "code") != "CHECK-MAIN" or !message.starts_with?(NO_MAIN_MESSAGE)
    return false
  end
  return Uri.same_path?(Fields.text(found, "file"), path)
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
  if !Uri.same_path?(Fields.text(found, "file"), path)
    return false
  end
  return Places.place(found, "start").line > source.split("\n").size
end

def run(agentica: String, path: String, text: String, deadline: Int) -> Result[String]
  output = try Proc.run(agentica, ["--json", "check", "--stdin", path], text, deadline)
  case output.status
    0 ->
      if output.unsent != ""
        return error(output.unsent)
      end
      return ok("")
    1 ->
      problem = last_line(output.stderr)
      if problem == "" and output.unsent != ""
        return error(output.unsent)
      elsif problem == ""
        return error("agentica exited with status 1 and no diagnostic")
      end
      return ok(problem)
    _ -> return error("agentica exited with status #{output.status}: #{output.stderr.strip}")
  end
end

def last_line(text: String) -> String
  lines = text.strip.split("\n")
  return lines[lines.size - 1].strip
end

def diagnostic(found: Json, path: String, source: String, encoding: String) -> Json
  file = Fields.text(found, "file")
  message = Fields.text(found, "message")
  help = Fields.text(found, "help")
  if help != ""
    message = "#{message}\nhelp: #{help}"
  end
  start = Places.place(found, "start")
  stop = Places.place(found, "end")
  key_path = Fields.text(found, "key_path")
  fields: Map[String, Json] = {
    "severity": JSON.from(SEVERITY_ERROR),
    "code": JSON.from(Fields.text(found, "code")),
    "source": JSON.from("agentica"),
  }
  if Uri.same_path?(file, path)
    fields = fields.put("range", Places.range(source.split("\n"), start, stop, encoding))
  else
    message = "#{where(file, key_path, start)}: #{message}"
    fields = fields.put("range", JSON.object({"start": Places.origin(), "end": Places.origin()}))
    if file.starts_with?("/")
      fields = fields.put("relatedInformation", JSON.array([related(found, encoding)]))
    end
  end
  return JSON.object(fields.put("message", JSON.from(message)))
end

def related(found: Json, encoding: String) -> Json
  file = Fields.text(found, "file")
  key_path = Fields.text(found, "key_path")
  start = Places.place(found, "start")
  stop = Places.place(found, "end")
  range = JSON.object({"start": Places.origin(), "end": Places.origin()})
  if key_path == "" and start.line > 0
    range = Places.range(Places.source_lines(file), start, stop, encoding)
  end
  location = JSON.object({"uri": JSON.from(Uri.of_path(file)), "range": range})
  return JSON.object({"location": location, "message": JSON.from(RELATED_MESSAGE)})
end

def where(file: String, key_path: String, start: Places.Place) -> String
  if key_path != ""
    return "#{file} (#{key_path})"
  elsif start.line == 0
    return file
  end
  return "#{file}:#{start.line}:#{start.column}"
end
