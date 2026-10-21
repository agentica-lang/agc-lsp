## Finds the workspace folder that the editor opened and answers workspace symbol requests with the declarations of a
## name in the files below it.

import Fields from "fields"
import Places from "places"
import Query from "query"
import Symbols from "symbols"
import Logger from "std/logger"
import Uri from "uri"

READ_TIMEOUT_MS = 10_000

## Holds what a workspace symbol request needs: the compiler, the folder, the name and the position encoding.
export struct Request
  ## Is the executable that answers the query.
  agentica: String
  ## Is the absolute path of the workspace folder.
  root: String
  ## Is the name to find, written as the code declares it.
  name: String
  ## Is the position encoding of the session.
  encoding: String
end

## Returns the absolute path of the first workspace folder of initialize, else its root URI or root path, or an empty
## text when the editor gave none that is a local folder.
export def root_of(params: Json) -> String
  none: List[Json] = []
  folders = JSON.list(Fields.value(params, "workspaceFolders")).unwrap_or(none)
  uris = folders.map do |folder| Fields.text(folder, "uri") end.push(Fields.text(params, "rootUri"))
  for uri in uris
    case Uri.path_of(uri)
      ok(path) -> return trimmed(path)
      error(_) -> next
    end
  end
  path = Fields.text(params, "rootPath")
  if path.starts_with?("/")
    return trimmed(path)
  end
  return ""
end

## Returns the declarations of the name in the files of the workspace, as read from disk, as symbol information; the
## list is empty when there are none.
export def answer(request: Request) -> Result[Json]
  found = try Query.declarations_of(request.agentica, request.root, request.name)
  lines = lines_by_file(found)
  symbols: List[Json] = []
  for match in found
    case lines.get(match.name_span.file)
      ok(file_lines) -> symbols = symbols.push(symbol(request, match, file_lines))
      error(_) -> Logger.debug("the search dropped a match in a file that cannot be read: #{match.name_span.file}")
    end
  end
  return ok(JSON.array(symbols))
end

def lines_by_file(found: List[Query.Match]) -> Map[String, List[String]]
  loaded: Map[String, List[String]] = {}
  seen: Set[String] = Set.new([])
  for match in found
    file = match.name_span.file
    if !seen.include?(file)
      seen = seen.add(file)
      case File.read_text(file, READ_TIMEOUT_MS)
        ok(text) -> loaded = loaded.put(file, text.split("\n"))
        error(_) -> next
      end
    end
  end
  return loaded
end

def symbol(request: Request, match: Query.Match, lines: List[String]) -> Json
  range = Places.range(lines, match.name_span.start, match.name_span.stop, request.encoding)
  fields: Map[String, Json] = {
    "name": JSON.from(match.name),
    "kind": JSON.from(Symbols.kind_of(match.kind)),
    "location": JSON.object({"uri": JSON.from(Uri.of_path(match.name_span.file)), "range": range}),
  }
  if match.container != ""
    fields = fields.put("containerName", JSON.from(match.container))
  end
  return JSON.object(fields)
end

def trimmed(path: String) -> String
  root = path
  while root.length > 1 and root.ends_with?("/")
    root = root.slice(0, root.length - 1)
  end
  return root
end
