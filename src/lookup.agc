## Answers definition requests, and hover requests that need the compiler, with the queries of agentica.

import Catalog from "catalog"
import Cursor from "cursor"
import Hover from "hover"
import Places from "places"
import Query from "query"
import Uri from "uri"
import Words from "words"

STAT_TIMEOUT_MS = 10_000
SHORT_TEXT_CHARS = 60
MIN_FENCE = 3
SECTION_BREAK = "\n\n---\n\n"
LOCAL_KINDS = Set.new(["local", "parameter", "loop", "pattern"])

## Holds what a definition or hover request needs: the compiler, the buffer and the cursor.
export struct Request
  ## Is the executable that answers the queries.
  agentica: String
  ## Is the URI of the document, as the editor wrote it.
  uri: String
  ## Is the document the request is about, as the editor shows it.
  buffer: Query.Buffer
  ## Is the position of the request in that document.
  cursor: Cursor.Cursor
  ## Is the catalog of builtins, which answers a hover when the program gives no type.
  book: Catalog.Book
end

## Returns the location of the declaration of the name under the cursor, or null when there is none.
export def definition(request: Request) -> Result[Json]
  typed = try subject_at(request)
  case typed
    Query.Typed.Refused(_) -> return ok(JSON.null())
    Query.Typed.Found(subject) ->
      case subject.origin
        Query.Origin.Declared(declaration) -> return ok(location(request, declaration.name_span))
        Query.Origin.Builtin(_) -> return ok(JSON.null())
        Query.Origin.Unknown -> return ok(JSON.null())
      end
  end
end

## Returns the hover of the name under the cursor: the builtin it is, or its declaration and the type of the
## expression. A function with an error has no type, so the catalog answers, or else the result is null.
export def hover(request: Request) -> Result[Json]
  typed = try subject_at(request)
  case typed
    Query.Typed.Refused(_) -> return ok(Hover.answer(request.book, request.cursor))
    Query.Typed.Found(subject) -> return ok(answer(request, subject))
  end
end

def subject_at(request: Request) -> Result[Query.Typed]
  return Query.type_at(request.agentica, request.buffer, request.cursor.line + 1, request.cursor.index + 1)
end

def location(request: Request, name_span: Places.Span) -> Json
  if !known?(request, name_span.file)
    return JSON.null()
  end
  lines = lines_of(request, name_span.file)
  return JSON.object({
    "uri": JSON.from(location_uri(request, name_span.file)),
    "range": Places.range(lines, name_span.start, name_span.stop, request.cursor.encoding),
  })
end

def location_uri(request: Request, path: String) -> String
  if Uri.same_path?(path, request.buffer.path)
    return request.uri
  end
  return Uri.of_path(path)
end

def known?(request: Request, path: String) -> Bool
  return Uri.same_path?(path, request.buffer.path) or File.stat(path, STAT_TIMEOUT_MS).ok?
end

def lines_of(request: Request, path: String) -> List[String]
  if Uri.same_path?(path, request.buffer.path)
    return request.buffer.text.split("\n")
  end
  return Places.source_lines(path)
end

def typed(subject: Query.Subject) -> String
  if subject.text.contains?("\n") or subject.text.length > SHORT_TEXT_CHARS
    return fenced(subject.type)
  end
  return fenced("#{subject.text}: #{subject.type}")
end

def fenced(code: String) -> String
  fence = fence_for(code)
  return "#{fence}agc\n#{code}\n#{fence}"
end

def fence_for(text: String) -> String
  longest = 0
  run = 0
  for char in text.split("")
    if char == "`"
      run += 1
      if run > longest
        longest = run
      end
    else
      run = 0
    end
  end
  if longest < MIN_FENCE
    longest = MIN_FENCE - 1
  end
  return List.repeat("`", longest + 1).join("")
end

def declaration_text(declaration: Query.Declaration) -> String
  if declaration.doc == ""
    return fenced(declaration.signature)
  end
  return "#{fenced(declaration.signature)}\n\n#{declaration.doc}"
end

def sections(subject: Query.Subject) -> List[String]
  case subject.origin
    Query.Origin.Builtin(entry) -> return [Hover.describe(entry)]
    Query.Origin.Declared(declaration) if !LOCAL_KINDS.include?(declaration.kind) ->
      return [declaration_text(declaration)].concat(typed_sections(subject))
    Query.Origin.Declared(_) -> return typed_sections(subject)
    Query.Origin.Unknown -> return typed_sections(subject)
  end
end

def typed_sections(subject: Query.Subject) -> List[String]
  if subject.type == ""
    return []
  end
  return [typed(subject)]
end

def covered(request: Request, subject: Query.Subject) -> Json
  case subject.origin
    Query.Origin.Builtin(_) ->
      case Words.at(request.cursor.chars, request.cursor.index)
        ok(word) -> return Cursor.range(request.cursor, word.start, word.stop)
        error(_) -> return span_range(request, subject)
      end
    Query.Origin.Declared(_) -> return span_range(request, subject)
    Query.Origin.Unknown -> return span_range(request, subject)
  end
end

def span_range(request: Request, subject: Query.Subject) -> Json
  lines = request.buffer.text.split("\n")
  return Places.range(lines, subject.span.start, subject.span.stop, request.cursor.encoding)
end

def answer(request: Request, subject: Query.Subject) -> Json
  found = sections(subject)
  if found.size == 0
    return JSON.null()
  end
  value = JSON.object({"kind": JSON.from("markdown"), "value": JSON.from(found.join(SECTION_BREAK))})
  return JSON.object({"contents": value, "range": covered(request, subject)})
end
