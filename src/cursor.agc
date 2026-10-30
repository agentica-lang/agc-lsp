## Locates a position of the client in an open document.

import {UTF16, characters_in, utf16_width} from "columns"
import Uri from "uri"

## Holds the line of a position, its characters and the character index the position falls on.
export struct Cursor
  ## Is the zero-based line of the position.
  line: Int
  ## Is the text of the line without its line ending.
  text: String
  ## Lists the characters of the line.
  chars: List[String]
  ## Is the index of the character the position falls on.
  index: Int
  ## Is the position encoding of the session.
  encoding: String
end

## Returns the cursor of the position in the params, or an error when the document or the position is unknown. The
## documents map the path of each open document to its text.
export def locate(documents: Map[String, String], params: Json, encoding: String) -> Result[Cursor]
  document = JSON.get(params, "textDocument").unwrap_or(JSON.null())
  path = try Uri.path_of(try JSON.string(try JSON.get(document, "uri")))
  at = JSON.get(params, "position").unwrap_or(JSON.null())
  line = try JSON.int(try JSON.get(at, "line"))
  character = try JSON.int(try JSON.get(at, "character"))
  lines = (try documents.get(path).to_result("not open: #{path}")).split("\n")
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
    index = characters_in(text, character)
  end

  if index > chars.size
    index = chars.size
  end

  return ok(Cursor(line: line, text: text, chars: chars, index: index, encoding: encoding))
end

## Returns a cursor at the start of the first line, for requests about a whole document.
export def start(encoding: String) -> Cursor
  return Cursor(line: 0, text: "", chars: [], index: 0, encoding: encoding)
end

## Returns the LSP range between two character indexes of the cursor line.
export def range(cursor: Cursor, start: Int, stop: Int) -> Json
  return JSON.object({"start": position(cursor, start), "end": position(cursor, stop)})
end

def position(cursor: Cursor, index: Int) -> Json
  character = index
  if cursor.encoding == UTF16
    character = utf16_width(cursor.text, index)
  end

  return JSON.object({"line": JSON.from(cursor.line), "character": JSON.from(character)})
end
