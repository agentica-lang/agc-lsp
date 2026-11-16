## Answers codeAction requests with the quick fixes of the suggestions that `agentica lint` makes for the buffer.

import {UTF16, characters_in, utf16_width} from "columns"
import Fields from "fields"
import Options from "options"
import Logger from "std/logger"

## Holds what a codeAction request needs.
struct Request
  ## Is the executable that lints.
  agentica: String
  ## Is the URI of the document, as the editor wrote it.
  uri: String
  ## Is the file name of the document.
  name: String
  ## Is the text of the buffer.
  text: String
  ## Is the position encoding of the session.
  encoding: String
  ## Is the range that the editor asks about.
  range: JSON.Value
  ## Lists the kinds of actions that the editor wants, empty for all.
  only: List[String]
end

## Returns the actions that fix a suggestion in the range: each one replaces the text of the suggestion.
def answer(request: Request) -> Result[JSON.Value]
  shown: List[JSON.Value] = []
  if !wanted?(request.only)
    return ok(JSON.array(shown))
  end

  found = try suggestions(request)
  lines = request.text.split("\n")
  asked = span_of(request.range, lines, request.encoding)
  for suggestion in found
    if touches?(suggestion, asked)
      case fix_of(suggestion, lines)
        some(fix) -> shown = shown.push(action(request, fix, lines))
        none -> next
      end
    end
  end

  return ok(JSON.array(shown))
end

private

QUICK_FIX = "quickfix"

TEMP_FOLDER = "agc-lsp-lint"

LINT_TIMEOUT_MS = 30_000

FILE_TIMEOUT_MS = 10_000

## A place of the text: a line from 1 and a column from 1, counted in characters.
struct Spot
  line: Int
  column: Int
end

struct Span
  start: Spot
  stop: Spot
end

struct Suggestion
  code: String
  span: Span
end

## Is a replacement of the text of a span.
struct Fix
  title: String
  span: Span
  text: String
end

def wanted?(only: List[String]) -> Bool
  if only.size == 0
    return true
  end

  return only.any? do |kind| kind == QUICK_FIX or QUICK_FIX.start_with?("#{kind}.") end
end

def span_of(range: JSON.Value, lines: List[String], encoding: String) -> Span
  return Span(
    start: spot_of(Fields.value(range, "start"), lines, encoding),
    stop: spot_of(Fields.value(range, "end"), lines, encoding),
  )
end

def spot_of(at: JSON.Value, lines: List[String], encoding: String) -> Spot
  line = JSON.int(Fields.value(at, "line")).unwrap_or(0)
  character = JSON.int(Fields.value(at, "character")).unwrap_or(0)
  column = character
  if encoding == UTF16 and line >= 0 and line < lines.size
    column = characters_in(lines[line], character)
  end

  return Spot(line: line + 1, column: column + 1)
end

def before?(a: Spot, b: Spot) -> Bool
  return a.line < b.line or (a.line == b.line and a.column <= b.column)
end

def touches?(suggestion: Suggestion, asked: Span) -> Bool
  return before?(suggestion.span.start, asked.stop) and before?(asked.start, suggestion.span.stop)
end

def suggestions(request: Request) -> Result[List[Suggestion]]
  folder = "#{temporary()}/#{TEMP_FOLDER}-#{System.pid()}-#{Time.now_ms()}"
  try Dir.mkdir_private(folder, FILE_TIMEOUT_MS)
  outcome = linted(request, folder)
  _ = Path.remove(folder, FILE_TIMEOUT_MS)
  case outcome
    ok(found) -> return ok(found)
    error(failure) ->
      Logger.info("cannot lint #{request.name}: #{failure.message}")
      return ok([])
  end
end

def temporary() -> String
  for name in ["TMPDIR", "TEMP", "TMP"]
    case System.env(name)
      ok(folder) if folder != "" -> return folder.replace("\\", "/")
      ok(_) -> next
      error(_) -> next
    end
  end

  return "/tmp"
end

def linted(request: Request, folder: String) -> Result[List[Suggestion]]
  file = "#{folder}/#{request.name}"
  try File.write_text(file, request.text, FILE_TIMEOUT_MS)
  options = Process.Options(timeout_ms: LINT_TIMEOUT_MS, chdir: folder)
  helper = try Process.spawn_captured(Options.executable(request.agentica), ["--json", "lint", file], options)
  outcome = read(helper)
  Process.close(helper)
  return outcome
end

def read(helper: Process) -> Result[List[Suggestion]]
  try Process.close_stdin(helper, LINT_TIMEOUT_MS)
  output = try Process.output(helper, LINT_TIMEOUT_MS)
  status = try Process.wait(helper, LINT_TIMEOUT_MS)
  if status != 0
    return error("agentica exited with status #{status}: #{output.stderr.strip}")
  end

  document = try JSON.parse(output.stdout)
  found: List[Suggestion] = []
  for entry in Fields.items(document, "files")
    for item in Fields.items(entry, "suggestions")
      range = Fields.value(item, "range")
      span = Span(start: json_spot(Fields.value(range, "start")), stop: json_spot(Fields.value(range, "end")))
      found = found.push(Suggestion(code: Fields.text(item, "code"), span: span))
    end
  end

  return ok(found)
end

def json_spot(at: JSON.Value) -> Spot
  return Spot(
    line: JSON.int(Fields.value(at, "line")).unwrap_or(1),
    column: JSON.int(Fields.value(at, "column")).unwrap_or(1),
  )
end

def fix_of(suggestion: Suggestion, lines: List[String]) -> Optional[Fix]
  span = suggestion.span
  if span.start.line != span.stop.line or span.start.line > lines.size
    return none
  end

  chars = lines[span.start.line - 1].split("")
  written = chars.take(span.stop.column - 1).drop(span.start.column - 1).join("")
  case suggestion.code
    "LINT-BOOL-COMPARE" -> return replaced("Use the Bool as it is", span, bool_compare(written))
    "LINT-TO-S-CONCAT" -> return replaced("Use interpolation", span, interpolation(written))
    _ -> return none
  end
end

def replaced(title: String, span: Span, text: Optional[String]) -> Optional[Fix]
  case text
    some(found) -> return some(Fix(title: title, span: span, text: found))
    none -> return none
  end
end

## Returns `x` for `x == true`, `not x` for `x == false`, and the same for `!=` with the Bool swapped; or none when the
## comparison is not one of a plain name or call.
def bool_compare(written: String) -> Optional[String]
  for operator in [" == ", " != "]
    if written.include?(operator)
      parts = written.split(operator)
      if parts.size == 2
        return compared(parts[0].strip, parts[1].strip, operator == " == ")
      end
    end
  end

  return none
end

def compared(left: String, right: String, equal: Bool) -> Optional[String]
  literal = right
  subject = left
  if (left == "true" or left == "false") and right != "true" and right != "false"
    literal = left
    subject = right
  end

  if (literal != "true" and literal != "false") or subject == "" or subject.include?(" ") or subject.include?("\"")
    return none
  end

  if equal == (literal == "true")
    return some(subject)
  end

  return some("not #{subject}")
end

## Returns the string with interpolation for `"n=" + n.to_s`, or none when a piece is neither a string nor a plain name
## or call.
def interpolation(written: String) -> Optional[String]
  pieces = top_level_pieces(written)
  if pieces.size < 2
    return none
  end

  inside: List[String] = []
  for piece in pieces
    if piece.start_with?("\"") and piece.end_with?("\"") and piece.length >= 2
      inside = inside.push(piece.slice(1, piece.length - 2))
    elsif piece == "" or piece.include?(" ") or piece.include?("\"")
      return none
    else
      inside = inside.push("\#{#{without_to_s(piece)}}")
    end
  end

  return some("\"#{inside.join("")}\"")
end

def without_to_s(piece: String) -> String
  for suffix in [".to_s()", ".to_s"]
    if piece.end_with?(suffix)
      return piece.slice(0, piece.length - suffix.length)
    end
  end

  return piece
end

## Returns the pieces of the text that are joined with a + outside a string and a bracket.
def top_level_pieces(written: String) -> List[String]
  chars = written.split("")
  pieces: List[String] = []
  depth = 0
  in_string = false
  start = 0
  index = 0
  while index < chars.size
    char = chars[index]
    if in_string and char == "\\"
      index += 1
    elsif in_string
      in_string = char != "\""
    elsif char == "\""
      in_string = true
    elsif char == "(" or char == "[" or char == "{"
      depth += 1
    elsif char == ")" or char == "]" or char == "}"
      depth -= 1
    elsif char == "+" and depth == 0
      pieces = pieces.push(chars.take(index).drop(start).join("").strip)
      start = index + 1
    end

    index += 1
  end

  return pieces.push(chars.drop(start).join("").strip)
end

def action(request: Request, fix: Fix, lines: List[String]) -> JSON.Value
  edit = JSON.object({
    "range": JSON.object({
      "start": position(fix.span.start, lines, request.encoding),
      "end": position(fix.span.stop, lines, request.encoding),
    }),
    "newText": JSON.from(fix.text),
  })
  return JSON.object({
    "title": JSON.from(fix.title),
    "kind": JSON.from(QUICK_FIX),
    "isPreferred": JSON.from(true),
    "edit": JSON.object({"changes": JSON.object({request.uri: JSON.array([edit])})}),
  })
end

def position(at: Spot, lines: List[String], encoding: String) -> JSON.Value
  character = at.column - 1
  if encoding == UTF16
    character = utf16_width(lines[at.line - 1], character)
  end

  return JSON.object({"line": JSON.from(at.line - 1), "character": JSON.from(character)})
end
