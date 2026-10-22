## Finds the workspace folder that the editor opened and answers workspace symbol requests with the declarations of a
## name in the files below it.

import Fields from "fields"
import Places from "places"
import Refusals from "refusals"
import Analysis from "std/analysis"
import Logger from "std/logger"
import Symbols from "symbols"
import Uri from "uri"

NO_FILES = "no .agc file"
BUILTIN_KIND = "builtin"

## Holds what a workspace symbol request needs: the session, the folder, the name and the position encoding.
export struct Request
  ## Is the session with the text of every open document at the time of the request.
  session: Analysis.Session
  ## Maps the path of each open document to its text.
  documents: Map[String, String]
  ## Is the absolute path of the workspace folder.
  root: String
  ## Is the working folder, from which std/analysis writes the names of files below it.
  folder: String
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
      ok(path) -> return Uri.trimmed(path)
      error(_) -> next
    end
  end
  path = Fields.text(params, "rootPath")
  if path.starts_with?("/")
    return Uri.trimmed(path)
  end
  return ""
end

## Returns the declarations of the name in the files of the workspace and in the open documents, as symbol
## information; the list is empty when there are none.
export def answer(request: Request) -> Result[Json]
  found = try declarations_of(request)
  symbols: List[Json] = []
  for match in found
    path = Uri.resolve(request.folder, match.module)
    if Places.known?(request.documents, path)
      symbols = symbols.push(symbol(request, match, path))
    else
      Logger.debug("the search dropped a match in a file that cannot be read: #{path}")
    end
  end
  return ok(JSON.array(symbols))
end

def declarations_of(request: Request) -> Result[List[Analysis.Symbol]]
  none: List[Analysis.Symbol] = []
  case Analysis.symbol(request.session, request.name, [request.root])
    ok(searched) ->
      for skipped in searched.skipped
        Logger.debug("the search skipped a file", {"file": skipped.file, "code": skipped.diagnostic.code})
      end
      return ok(searched.matches.filter do |match| match.kind != BUILTIN_KIND end)
    error(message) if Refusals.in_search?(message) -> return ok(none)
    error(message) if without_files?(message) ->
      Logger.debug("the search found no agentica file in #{request.root}")
      return ok(none)
    error(message) -> return error(message)
  end
end

def without_files?(message: String) -> Bool
  case Analysis.diagnostic(message)
    ok(found) -> return found.message.contains?(NO_FILES)
    error(_) -> return false
  end
end

def symbol(request: Request, match: Analysis.Symbol, path: String) -> Json
  lines = Places.lines_of(request.documents, path)
  range = Places.range(lines, match.name_range, request.encoding)
  fields: Map[String, Json] = {
    "name": JSON.from(match.name),
    "kind": JSON.from(Symbols.kind_of(match.kind)),
    "location": JSON.object({"uri": JSON.from(Uri.of_path(path)), "range": range}),
  }
  if match.owner != ""
    fields = fields.put("containerName", JSON.from(match.owner))
  end
  return JSON.object(fields)
end
