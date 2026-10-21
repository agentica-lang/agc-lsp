## Reads the places that agentica prints and converts them to positions and ranges of the client.

import Fields from "fields"
import {UTF16, utf16_width} from "columns"

READ_TIMEOUT_MS = 10_000

## Holds a line and a column, both counted from 1 in code points; 0 means unknown.
export struct Place
  ## Is the line, counted from 1.
  line: Int
  ## Is the column, counted from 1 in code points.
  column: Int
end

## Holds the part of a file from one place up to another, the end excluded.
export struct Span
  ## Is the file as agentica names it.
  file: String
  ## Is the first place.
  start: Place
  ## Is the place after the last one.
  stop: Place
end

## Returns the start or the end of the range of a diagnostic or a span.
export def place(found: Json, edge: String) -> Place
  at = Fields.value(Fields.value(found, "range"), edge)
  return Place(line: Fields.number(at, "line", 0), column: Fields.number(at, "column", 0))
end

## Returns the span of a JSON object with a file and a range.
export def span(found: Json) -> Span
  return Span(file: Fields.text(found, "file"), start: place(found, "start"), stop: place(found, "end"))
end

## Returns the LSP range from a start to a stop in the lines of a file.
export def range(lines: List[String], start: Place, stop: Place, encoding: String) -> Json
  return JSON.object({"start": position(start, lines, encoding), "end": position(stop, lines, encoding)})
end

## Returns the LSP position of a place in the lines of a file.
export def position(at: Place, lines: List[String], encoding: String) -> Json
  line = not_negative(at.line - 1)
  character = not_negative(at.column - 1)
  if encoding == UTF16 and line < lines.size
    character = utf16_width(lines[line], character)
  end
  return JSON.object({"line": JSON.from(line), "character": JSON.from(character)})
end

## Returns the LSP position of the start of a file.
export def origin() -> Json
  return JSON.object({"line": JSON.from(0), "character": JSON.from(0)})
end

## Returns the lines of a file on disk, or a single empty line when it cannot be read.
export def source_lines(path: String) -> List[String]
  return File.read_text(path, READ_TIMEOUT_MS).unwrap_or("").split("\n")
end

def not_negative(n: Int) -> Int
  if n < 0
    return 0
  end
  return n
end
