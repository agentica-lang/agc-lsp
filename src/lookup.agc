## Answers definition and references requests, and hover requests that need the compiler, with the questions that
## std/analysis answers.

import Catalog from "catalog"
import Cursor from "cursor"
import Hover from "hover"
import Places from "places"
import Refusals from "refusals"
import Analysis from "std/analysis"
import Uri from "uri"
import Words from "words"

SHORT_TEXT_CHARS = 60
MIN_FENCE = 3
SECTION_BREAK = "\n\n---\n\n"
LOCAL_KINDS = Set.new(["local", "parameter", "loop", "pattern"])
TYPE_KIND = "type"
BUILTIN_KIND = "builtin"

## Holds what a definition, references or hover request needs: the session, the document and the cursor.
export struct Request
  ## Is the session with the text of every open document at the time of the request.
  session: Analysis.Session
  ## Is the URI of the document, as the editor wrote it.
  uri: String
  ## Is the path of the document.
  path: String
  ## Maps the path of each open document to its text.
  documents: Map[String, String]
  ## Is the working folder, from which std/analysis writes the names of files below it.
  folder: String
  ## Is the position of the request in that document.
  cursor: Cursor.Cursor
  ## Is the catalog of builtins, which answers a hover when the program gives no type.
  book: Catalog.Book
end

struct Use
  file: String
  range: Analysis.Region
end

enum Typed
  Refused
  Found(Analysis.TypeAt)
end

enum Referenced
  Refused
  Found(Analysis.Refs)
end

enum Origin
  Unknown
  Declared(Analysis.Definition)
  Builtin(Catalog.Entry)
end

## Returns the location of the declaration of the name under the cursor, or null when there is none.
export def definition(request: Request) -> Result[Json]
  typed = try subject_at(request)
  case typed
    Typed.Refused -> return ok(JSON.null())
    Typed.Found(found) ->
      case origin_of(found)
        Origin.Declared(declared) -> return ok(location(request, declared.file, declared.name_range))
        Origin.Builtin(_) -> return ok(JSON.null())
        Origin.Unknown -> return ok(JSON.null())
      end
  end
end

## Returns the locations of the uses of the name under the cursor, with its declaration when asked, or null when
## agentica finds no name there. A file that is not open and not on disk has no locations.
export def references(request: Request, with_declaration: Bool) -> Result[Json]
  found = try references_at(request)
  case found
    Referenced.Refused -> return ok(JSON.null())
    Referenced.Found(uses) -> return ok(locations(request, places_of(uses, with_declaration)))
  end
end

## Returns the hover of the name under the cursor: the builtin it is, or its declaration and the type of the
## expression. A function with an error has no type, so the catalog answers, or else the result is null.
export def hover(request: Request) -> Result[Json]
  typed = try subject_at(request)
  case typed
    Typed.Refused -> return ok(Hover.answer(request.book, request.cursor))
    Typed.Found(found) -> return ok(answer(request, found))
  end
end

def subject_at(request: Request) -> Result[Typed]
  asked = Analysis.type_at_partial(request.session, request.path, request.cursor.line + 1, request.cursor.index + 1)
  case asked
    ok(found) -> return ok(Typed.Found(found))
    error(message) if Refusals.at_position?(message) -> return ok(Typed.Refused)
    error(message) -> return error(message)
  end
end

def references_at(request: Request) -> Result[Referenced]
  asked = Analysis.refs_partial(request.session, request.path, request.cursor.line + 1, request.cursor.index + 1)
  case asked
    ok(found) -> return ok(Referenced.Found(found))
    error(message) if Refusals.at_position?(message) -> return ok(Referenced.Refused)
    error(message) -> return error(message)
  end
end

def origin_of(found: Analysis.TypeAt) -> Origin
  if found.definition.size > 0
    return Origin.Declared(found.definition[0])
  end

  if found.kind == BUILTIN_KIND and JSON.kind(found.help) == "object"
    return Origin.Builtin(Catalog.from_help(found.help))
  end

  return Origin.Unknown
end

def location(request: Request, file: String, name_range: Analysis.Region) -> Json
  path = Uri.resolve(request.folder, file)
  if !Places.known?(request.documents, path)
    return JSON.null()
  end

  return JSON.object({
    "uri": JSON.from(location_uri(request, path)),
    "range": Places.range(Places.lines_of(request.documents, path), name_range, request.cursor.encoding),
  })
end

def places_of(uses: Analysis.Refs, with_declaration: Bool) -> List[Use]
  found = uses.references.map do |use| Use(file: use.file, range: use.range) end
  if !with_declaration
    return found
  end

  declared = uses.definition.map do |symbol| Use(file: symbol.module, range: symbol.name_range) end
  return declared.concat(found)
end

def locations(request: Request, places: List[Use]) -> Json
  lines = lines_by_file(request, places)
  found: List[Json] = []
  for place in places
    path = Uri.resolve(request.folder, place.file)
    case lines.get(path)
      ok(file_lines) ->
        found = found.push(JSON.object({
          "uri": JSON.from(location_uri(request, path)),
          "range": Places.range(file_lines, place.range, request.cursor.encoding),
        }))
      error(_) -> next
    end
  end

  return JSON.array(found)
end

def lines_by_file(request: Request, places: List[Use]) -> Map[String, List[String]]
  loaded: Map[String, List[String]] = {}
  for place in places
    path = Uri.resolve(request.folder, place.file)
    if !loaded.get(path).ok? and Places.known?(request.documents, path)
      loaded = loaded.put(path, Places.lines_of(request.documents, path))
    end
  end

  return loaded
end

def location_uri(request: Request, path: String) -> String
  if Uri.same_path?(path, request.path)
    return request.uri
  end

  return Uri.of_path(path)
end

def typed(found: Analysis.TypeAt) -> String
  if found.text.contains?("\n") or found.text.length > SHORT_TEXT_CHARS
    return fenced(found.type)
  end

  return fenced("#{found.text}: #{found.type}")
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

def declaration_text(declared: Analysis.Definition) -> String
  if declared.doc == ""
    return fenced(declared.signature)
  end

  return "#{fenced(declared.signature)}\n\n#{declared.doc}"
end

def sections(found: Analysis.TypeAt) -> List[String]
  case origin_of(found)
    Origin.Builtin(entry) -> return [Hover.describe(entry)]
    Origin.Declared(declared) if found.kind == TYPE_KIND -> return [declaration_text(declared)]
    Origin.Declared(declared) if !LOCAL_KINDS.include?(declared.kind) ->
      return [declaration_text(declared)].concat(typed_sections(found))
    Origin.Declared(_) -> return typed_sections(found)
    Origin.Unknown -> return typed_sections(found)
  end
end

def typed_sections(found: Analysis.TypeAt) -> List[String]
  if found.type == "" or found.kind == TYPE_KIND
    return []
  end

  return [typed(found)]
end

def covered(request: Request, found: Analysis.TypeAt) -> Json
  case origin_of(found)
    Origin.Builtin(entry) ->
      case Words.at(request.cursor.chars, request.cursor.index)
        ok(word) ->
          name = qualified(request.cursor.chars, entry, word)
          return Cursor.range(request.cursor, name.start, name.stop)
        error(_) -> return span_range(request, found)
      end

    Origin.Declared(_) -> return span_range(request, found)
    Origin.Unknown -> return span_range(request, found)
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

def span_range(request: Request, found: Analysis.TypeAt) -> Json
  lines = Places.lines_of(request.documents, request.path)
  return Places.range(lines, found.range, request.cursor.encoding)
end

def answer(request: Request, found: Analysis.TypeAt) -> Json
  shown = sections(found)
  if shown.size == 0
    return Hover.answer(request.book, request.cursor)
  end

  value = JSON.object({"kind": JSON.from("markdown"), "value": JSON.from(shown.join(SECTION_BREAK))})
  return JSON.object({"contents": value, "range": covered(request, found)})
end
