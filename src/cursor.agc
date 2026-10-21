## Locates a position of the client in an open document.

import Columns from "columns"

UTF16 = "utf-16"

## Holds the line of a position, its characters and the character index the position falls on.
export struct Cursor
  line: Int
  text: String
  chars: List[String]
  index: Int
  encoding: String
end

## Returns the cursor of the position in the params, or an error when the document or the position is unknown.
export def locate(documents: Map[String, String], params: Json, encoding: String) -> Result[Cursor]
  document = JSON.get(params, "textDocument").unwrap_or(JSON.null())
  uri = try JSON.string(try JSON.get(document, "uri"))
  at = JSON.get(params, "position").unwrap_or(JSON.null())
  line = try JSON.int(try JSON.get(at, "line"))
  character = try JSON.int(try JSON.get(at, "character"))
  lines = (try documents.get(uri)).split("\n")
  if line < 0 or line >= lines.size or character < 0
    return error("no such position #{line}:#{character}")
  end
  text = lines[line]
  if text.ends_with?("\r")
    text = text.slice(0, text.length - 1)
  end
  chars = text.split("")
  index = character
  if encoding == UTF16
    index = Columns.characters_in(text, character)
  end
  if index > chars.size
    index = chars.size
  end
  return ok(Cursor(line: line, text: text, chars: chars, index: index, encoding: encoding))
end

## Returns the LSP range between two character indexes of the cursor line.
export def range(cursor: Cursor, start: Int, stop: Int) -> Json
  return JSON.object({"start": position(cursor, start), "end": position(cursor, stop)})
end

def position(cursor: Cursor, index: Int) -> Json
  character = index
  if cursor.encoding == UTF16
    character = Columns.utf16_width(cursor.text, index)
  end
  return JSON.object({"line": JSON.from(cursor.line), "character": JSON.from(character)})
end
