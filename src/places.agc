## Converts the places that std/analysis answers to positions and ranges of the client, and finds the lines they
## are counted in.

import {UTF16, utf16_width} from "columns"
import Analysis from "std/analysis"
import Uri from "uri"

READ_TIMEOUT_MS = 10_000

## Returns the LSP range of a region in the lines of a file.
export def range(lines: List[String], region: Analysis.Region, encoding: String) -> Json
  return JSON.object({
    "start": position(region.start, lines, encoding),
    "end": position(region.stop, lines, encoding),
  })
end

## Returns the LSP position of the start of a file.
export def origin() -> Json
  return JSON.object({"line": JSON.from(0), "character": JSON.from(0)})
end

## Returns the lines of a file as the editor shows them when it is open, else as they are on disk, or a single empty
## line when it cannot be read.
export def lines_of(documents: Map[String, String], path: String) -> List[String]
  return text_of(documents, path).split("\n")
end

## Returns true when the file is open in the editor or can be read from disk.
export def known?(documents: Map[String, String], path: String) -> Bool
  return held(documents, path).ok? or File.stat(path, READ_TIMEOUT_MS).ok?
end

def position(at: Analysis.Position, lines: List[String], encoding: String) -> Json
  line = not_negative(at.line - 1)
  character = not_negative(at.column - 1)
  if encoding == UTF16 and line < lines.size
    character = utf16_width(lines[line], character)
  end

  return JSON.object({"line": JSON.from(line), "character": JSON.from(character)})
end

def text_of(documents: Map[String, String], path: String) -> String
  case held(documents, path)
    ok(text) -> return text
    error(_) -> return File.read_text(path, READ_TIMEOUT_MS).unwrap_or("")
  end
end

def held(documents: Map[String, String], path: String) -> Result[String]
  case documents.get(path)
    some(text) -> return ok(text)
    none -> return same_file(documents, path)
  end
end

def same_file(documents: Map[String, String], path: String) -> Result[String]
  for open in documents.keys
    if Uri.same_path?(open, path)
      return documents.get(open).to_result("not open: #{path}")
    end
  end

  return error("not open: #{path}")
end

def not_negative(n: Int) -> Int
  if n < 0
    return 0
  end

  return n
end
