## Maps the first problem that std/analysis finds in a file to an LSP diagnostic, with relatedInformation for a problem
## in another file.

import Fields from "fields"
import Places from "places"
import Analysis from "std/analysis"
import Uri from "uri"

SEVERITY_ERROR = 1
RELATED_MESSAGE = "the error is here"

## Holds what the diagnostic of a check needs to be placed: the file, the open documents, the working folder and the
## position encoding.
export struct Placing
  ## Is the path of the checked file.
  path: String
  ## Maps the path of each open document to its text.
  documents: Map[String, String]
  ## Is the working folder, from which std/analysis writes the names of files below it.
  folder: String
  ## Is the position encoding of the session.
  encoding: String
end

## Returns the first problem of the check as LSP diagnostics, or an empty list when the check passes.
export def diagnostics(checked: Analysis.Checked, placing: Placing) -> List[Json]
  if checked.diagnostics.size == 0
    return []
  end
  return [diagnostic(checked.diagnostics[0], placing)]
end

## Returns the URI that the related location of the first diagnostic points into, or an empty text.
export def points_into(found: List[Json]) -> String
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

def diagnostic(found: Analysis.Diagnostic, placing: Placing) -> Json
  message = found.message
  if found.help != ""
    message = "#{message}\nhelp: #{found.help}"
  end
  fields: Map[String, Json] = {
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
    if file.starts_with?("/") and Places.known?(placing.documents, file)
      fields = fields.put("relatedInformation", JSON.array([related(found, file, placing)]))
    end
  end
  return JSON.object(fields.put("message", JSON.from(message)))
end

def related(found: Analysis.Diagnostic, file: String, placing: Placing) -> Json
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
