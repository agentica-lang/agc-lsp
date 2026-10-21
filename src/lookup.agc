## Answers definition requests, and hover requests on what is not a builtin, with the queries of agentica.

import Cursor from "cursor"
import Places from "places"
import Query from "query"
import Uri from "uri"

STAT_TIMEOUT_MS = 10_000
SHORT_TEXT_CHARS = 60
MIN_FENCE = 3

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
end

## Returns the location of the declaration of the name under the cursor, or null when there is none.
export def definition(request: Request) -> Result[Json]
  typed = try subject_at(request)
  case typed
    Query.Typed.Refused(_) -> return ok(JSON.null())
    Query.Typed.Found(subject) ->
      case subject.origin
        Query.Origin.Declared(name_span) -> return ok(location(request, name_span))
        Query.Origin.Unknown -> return ok(JSON.null())
      end
  end
end

## Returns the hover with the type of the expression under the cursor, or null when the program has an error.
export def hover(request: Request) -> Result[Json]
  typed = try subject_at(request)
  case typed
    Query.Typed.Refused(_) -> return ok(JSON.null())
    Query.Typed.Found(subject) -> return ok(markdown(request, subject))
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
    return "```agc\n#{subject.type}\n```"
  end
  fence = fence_for(subject.text)
  return "#{fence}agc\n#{subject.text}: #{subject.type}\n#{fence}"
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

def markdown(request: Request, subject: Query.Subject) -> Json
  contents = JSON.object({"kind": JSON.from("markdown"), "value": JSON.from(typed(subject))})
  lines = request.buffer.text.split("\n")
  range = Places.range(lines, subject.span.start, subject.span.stop, request.cursor.encoding)
  return JSON.object({"contents": contents, "range": range})
end
