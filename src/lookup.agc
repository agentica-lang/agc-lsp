## Answers definition and references requests, and hover requests that need the compiler, with the queries of
## agentica.

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

## Returns the locations of the uses of the name under the cursor, with its declaration when asked, or null when
## agentica finds no name there. A file that is not on disk has no locations.
export def references(request: Request, with_declaration: Bool) -> Result[Json]
  found = try Query.references_at(request.agentica, request.buffer, request.cursor.line + 1, request.cursor.index + 1)
  case found
    Query.Referenced.Refused(_) -> return ok(JSON.null())
    Query.Referenced.Found(uses) -> return ok(locations(request, places_of(uses, with_declaration)))
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

def places_of(uses: Query.Uses, with_declaration: Bool) -> List[Places.Span]
  if !with_declaration
    return uses.places
  end
  case uses.origin
    Query.Origin.Declared(declaration) -> return [declaration.name_span].concat(uses.places)
    Query.Origin.Builtin(_) -> return uses.places
    Query.Origin.Unknown -> return uses.places
  end
end

def locations(request: Request, places: List[Places.Span]) -> Json
  lines = lines_by_file(request, places)
  found: List[Json] = []
  for place in places
    case lines.get(place.file)
      ok(file_lines) ->
        found = found.push(JSON.object({
          "uri": JSON.from(location_uri(request, place.file)),
          "range": Places.range(file_lines, place.start, place.stop, request.cursor.encoding),
        }))
      error(_) -> next
    end
  end
  return JSON.array(found)
end

def lines_by_file(request: Request, places: List[Places.Span]) -> Map[String, List[String]]
  loaded: Map[String, List[String]] = {}
  seen: Set[String] = Set.new([])
  for place in places
    if !seen.include?(place.file)
      seen = seen.add(place.file)
      if known?(request, place.file)
        loaded = loaded.put(place.file, lines_of(request, place.file))
      end
    end
  end
  return loaded
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
    Query.Origin.Builtin(entry) ->
      case Words.at(request.cursor.chars, request.cursor.index)
        ok(word) ->
          name = qualified(request.cursor.chars, entry, word)
          return Cursor.range(request.cursor, name.start, name.stop)
        error(_) -> return span_range(request, subject)
      end
    Query.Origin.Declared(_) -> return span_range(request, subject)
    Query.Origin.Unknown -> return span_range(request, subject)
  end
end

def qualified(chars: List[String], entry: Catalog.Entry, word: Words.Word) -> Words.Word
  if entry.namespace == ""
    return word
  end
  if word.text == entry.namespace
    case Words.member(chars, word.stop)
      ok(member) -> return word.with(stop: member.stop)
      error(_) -> return word
    end
  end
  case Words.receiver(chars, word.start)
    ok(receiver) if receiver.text == entry.namespace -> return word.with(start: receiver.start)
    ok(_) -> return word
    error(_) -> return word
  end
end

def span_range(request: Request, subject: Query.Subject) -> Json
  lines = request.buffer.text.split("\n")
  return Places.range(lines, subject.span.start, subject.span.stop, request.cursor.encoding)
end

def answer(request: Request, subject: Query.Subject) -> Json
  found = sections(subject)
  if found.size == 0
    return Hover.answer(request.book, request.cursor)
  end
  value = JSON.object({"kind": JSON.from("markdown"), "value": JSON.from(found.join(SECTION_BREAK))})
  return JSON.object({"contents": value, "range": covered(request, subject)})
end
