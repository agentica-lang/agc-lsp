## Maps the problems that std/analysis finds in a file to LSP diagnostics, with relatedInformation for a problem in
## another file.

import Fields from "fields"
import Places from "places"
import Analysis from "std/analysis"
import Uri from "uri"

## Holds what the diagnostic of a check needs to be placed: the file, the open documents, the working folder and the
## position encoding.
struct Placing
  ## Is the path of the checked file.
  path: String
  ## Maps the path of each open document to its text.
  documents: Map[String, String]
  ## Is the working folder, from which std/analysis writes the names of files below it.
  folder: String
  ## Is the position encoding of the session.
  encoding: String
end

## Returns the problems as LSP diagnostics.
def diagnostics(problems: List[Analysis.Diagnostic], placing: Placing) -> List[JSON.Value]
  return problems.map do |found| diagnostic(found, placing) end
end

## Returns the problems of the file: the first one of the check and the ones of the other functions that do not check.
## A check stops at the first problem; a partial question names those of every function that fails.
def problems(session: Analysis.Session, path: String, checked: Analysis.Checked) -> List[Analysis.Diagnostic]
  if checked.diagnostics.size == 0
    return []
  end

  case Analysis.outline(session, path)
    ok(outlined) ->
      for item in outlined.items
        if ANCHOR_KINDS.include?(item.kind)
          start = item.name_range.start
          return merged(checked.diagnostics[0], Analysis.refs_partial(session, path, start.line, start.column))
        end
      end

      return [checked.diagnostics[0]]
    error(_) -> return [checked.diagnostics[0]]
  end
end

## Returns the URI that the related location of the first diagnostic points into, or an empty text.
def points_into(found: List[JSON.Value]) -> String
  if found.size == 0
    return ""
  end

  entries = Fields.items(found[0], "relatedInformation")
  if entries.size == 0
    return ""
  end

  location = Fields.value(entries[0], "location")
  return Fields.text(location, "uri")
end

private

SEVERITY_ERROR = 1

ANCHOR_KINDS = Set.new(["function", "constant", "struct"])

RELATED_MESSAGE = "the error is here"

def merged(first: Analysis.Diagnostic, asked: Result[Analysis.Refs]) -> List[Analysis.Diagnostic]
  case asked
    ok(refs) -> return [first].concat(refs.diagnostics.filter do |found| !same_problem?(found, first) end)
    error(_) -> return [first]
  end
end

def same_problem?(a: Analysis.Diagnostic, b: Analysis.Diagnostic) -> Bool
  return (
    a.code == b.code and
    a.file == b.file and
    a.range.start.line == b.range.start.line and
    a.range.start.column == b.range.start.column
  )
end

def diagnostic(found: Analysis.Diagnostic, placing: Placing) -> JSON.Value
  message = found.message
  if found.help != ""
    message = "#{message}\nhelp: #{found.help}"
  end

  fields: Map[String, JSON.Value] = {
    "severity": JSON.from(SEVERITY_ERROR),
    "code": JSON.from(found.code),
    "source": JSON.from("agentica"),
  }
  if Uri.same_path?(found.file, placing.path)
    lines = Places.lines_of(placing.documents, placing.path)
    fields = fields.put("range", Places.range(lines, found.range, placing.encoding))
  else
    message = "#{where(found)}: #{message}"
    fields = fields.put("range", JSON.object({"start": Places.origin(), "end": Places.origin()}))
    file = Uri.resolve(placing.folder, found.file)
    if Uri.absolute?(file) and Places.known?(placing.documents, file)
      fields = fields.put("relatedInformation", JSON.array([related(found, file, placing)]))
    end
  end

  return JSON.object(fields.put("message", JSON.from(message)))
end

def related(found: Analysis.Diagnostic, file: String, placing: Placing) -> JSON.Value
  range = JSON.object({"start": Places.origin(), "end": Places.origin()})
  if found.key_path == "" and found.range.start.line > 0
    range = Places.range(Places.lines_of(placing.documents, file), found.range, placing.encoding)
  end

  location = JSON.object({"uri": JSON.from(Uri.of_path(file)), "range": range})
  return JSON.object({"location": location, "message": JSON.from(RELATED_MESSAGE)})
end

def where(found: Analysis.Diagnostic) -> String
  if found.key_path != ""
    return "#{found.file} (#{found.key_path})"
  elsif found.range.start.line == 0
    return found.file
  end

  return "#{found.file}:#{found.range.start.line}:#{found.range.start.column}"
end
