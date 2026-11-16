## Answers prepareRename and rename requests with the declaration and the uses that `agentica refs` finds, and refuses
## a rename that could leave a use behind.

import Lookup from "lookup"
import Places from "places"
import Analysis from "std/analysis"
import Logger from "std/logger"
import Uri from "uri"
import Words from "words"

## Holds what a rename request needs.
struct Request
  ## Is the question at the position of the name.
  lookup: Lookup.Request
  ## Is the absolute path of the workspace folder, empty when the editor gave none.
  root: String
  ## Is the new name, empty for prepareRename.
  name: String
end

## Returns the range and the name that the editor shows before it asks for the new name, or null when the name under
## the cursor cannot be renamed.
def prepare(request: Request) -> Result[JSON.Value]
  case planned(request)
    ok(plan) ->
      case named_at(request, plan.places)
        some(place) ->
          lines = Places.lines_of(request.lookup.documents, request.lookup.path)
          range = Places.range(lines, place.range, request.lookup.cursor.encoding)
          return ok(JSON.object({"range": range, "placeholder": JSON.from(plan.definition.name)}))
        none -> return ok(JSON.null())
      end

    error(failure) ->
      Logger.debug("the name cannot be renamed: #{failure.message}")
      return ok(JSON.null())
  end
end

## Returns the workspace edit that renames the declaration under the cursor and its uses, or an error that says why
## it cannot be done.
def rename(request: Request) -> Result[JSON.Value]
  plan = try planned(request)
  name = try checked_name(plan.definition, request.name)
  return edits(request, plan, name)
end

private

LOCAL_KINDS = Set.new(["local", "parameter", "loop", "pattern"])

TYPE_KINDS = Set.new(["struct", "enum", "alias", "variant"])

READ_TIMEOUT_MS = 10_000

MAX_ENTRIES = 20_000

SKIPPED_FOLDERS = Set.new(["_build", "node_modules"])

AGENTICA_EXTENSION = ".agc"

UPPER_FIRST = 65

UPPER_LAST = 90

LOWER_FIRST = 97

LOWER_LAST = 122

DIGIT_FIRST = 48

DIGIT_LAST = 57

struct Place
  file: String
  range: Analysis.Region
end

struct Plan
  definition: Analysis.Symbol
  places: List[Place]
end

def planned(request: Request) -> Result[Plan]
  found = try Lookup.uses(request.lookup)
  case found
    some(uses) -> return planned_from(request, uses)
    none -> return error("there is no name to rename here")
  end
end

def planned_from(request: Request, uses: Analysis.Refs) -> Result[Plan]
  if uses.builtin != ""
    return error("#{uses.builtin} is a builtin and cannot be renamed")
  elsif uses.definition.size == 0
    return error("the name has no declaration")
  elsif uses.partial
    return error("some functions have errors: fix them first, so that every use of the name is found")
  end

  definition = uses.definition[0]
  declared = [Place(file: definition.module, range: definition.name_range)]
  places = declared.concat(uses.references.map do |use| Place(file: use.file, range: use.range) end)
  other = elsewhere(request, definition, places)
  if other != ""
    return error("#{definition.name} is also written in #{other}, which agentica does not read with this file")
  end

  return ok(Plan(definition: definition, places: places))
end

# A public name may be used by a file that imports its module, and agentica reads only the file and what it imports.
# So the rename is refused when another file of the workspace holds the name as a word.
def elsewhere(request: Request, definition: Analysis.Symbol, places: List[Place]) -> String
  if LOCAL_KINDS.include?(definition.kind) or !definition.exported
    return ""
  end

  known = places.map do |place| Uri.trimmed(Uri.resolve(request.lookup.folder, place.file)) end
  for path in workspace_files(request)
    if !known.include?(path) and mentions?(request, path, definition.name)
      return path
    end
  end

  return ""
end

def mentions?(request: Request, path: String, name: String) -> Bool
  return Words.mentions?(Places.lines_of(request.lookup.documents, path).join("\n"), name)
end

def workspace_files(request: Request) -> List[String]
  files = request.lookup.documents.keys.map do |path| Uri.trimmed(path) end
  if request.root == ""
    return files
  end

  pending = [request.root]
  budget = MAX_ENTRIES
  while pending.size > 0 and budget > 0
    folder = pending[0]
    pending = pending.drop(1)
    case Dir.list(folder, READ_TIMEOUT_MS)
      ok(names) ->
        for name in names
          budget -= 1
          path = "#{folder}/#{name}"
          if name.start_with?(".") or SKIPPED_FOLDERS.include?(name)
            next
          elsif name.end_with?(AGENTICA_EXTENSION)
            if !files.include?(path)
              files = files.push(path)
            end
          elsif directory?(path)
            pending = pending.push(path)
          end
        end

      error(_) -> next
    end
  end

  return files
end

def directory?(path: String) -> Bool
  case File.stat(path, READ_TIMEOUT_MS)
    ok(info) -> return info.kind == "directory"
    error(_) -> return false
  end
end

def named_at(request: Request, places: List[Place]) -> Optional[Place]
  line = request.lookup.cursor.line + 1
  column = request.lookup.cursor.index + 1
  for place in places
    here = Uri.same_path?(Uri.resolve(request.lookup.folder, place.file), request.lookup.path)
    start = place.range.start
    if here and start.line == line and start.column <= column and column <= place.range.stop.column
      return some(place)
    end
  end

  return none
end

def checked_name(definition: Analysis.Symbol, name: String) -> Result[String]
  body = name
  if definition.kind == "function" and (name.end_with?("?") or name.end_with?("!"))
    body = name.slice(0, name.length - 1)
  end

  chars = body.split("")
  spelled = chars.size > 0 and body != "_" and chars.all? do |char| word?(char) end and !digit?(chars[0])
  if !spelled or Words.keyword?(name)
    return error("#{name.inspect} is not a name that agentica accepts")
  end

  if definition.kind == "constant" and !chars.all? do |char| !lower?(char) end
    return error("the name of a constant is written in capitals: #{name.inspect}")
  elsif (definition.kind == "constant" or TYPE_KINDS.include?(definition.kind)) and !upper?(chars[0])
    return error("a #{definition.kind} is named with a capital letter: #{name.inspect}")
  elsif definition.kind != "constant" and !TYPE_KINDS.include?(definition.kind) and upper?(chars[0])
    return error("a #{definition.kind} is named with a lower case letter: #{name.inspect}")
  end

  return ok(name)
end

def edits(request: Request, plan: Plan, name: String) -> Result[JSON.Value]
  lookup = request.lookup
  changes: Map[String, List[JSON.Value]] = {}
  lines_of: Map[String, List[String]] = {}
  for place in plan.places
    path = Uri.resolve(lookup.folder, place.file)
    if !Places.known?(lookup.documents, path)
      return error("cannot read #{place.file}")
    end

    if lines_of.get(path).none?
      lines_of = lines_of.put(path, Places.lines_of(lookup.documents, path))
    end

    uri = uri_of(request, path)
    range = Places.range(lines_of.get(path).unwrap_or([]), place.range, lookup.cursor.encoding)
    edit = JSON.object({"range": range, "newText": JSON.from(name)})
    changes = changes.put(uri, changes.get(uri).unwrap_or([]).push(edit))
  end

  grouped: Map[String, JSON.Value] = {}
  for uri in changes.keys
    grouped = grouped.put(uri, JSON.array(changes.get(uri).unwrap_or([])))
  end

  return ok(JSON.object({"changes": JSON.object(grouped)}))
end

def uri_of(request: Request, path: String) -> String
  if Uri.same_path?(path, request.lookup.path)
    return request.lookup.uri
  end

  return Uri.of_path(path)
end

def word?(char: String) -> Bool
  return upper?(char) or lower?(char) or digit?(char) or char == "_"
end

def upper?(char: String) -> Bool
  return String.code(char) >= UPPER_FIRST and String.code(char) <= UPPER_LAST
end

def lower?(char: String) -> Bool
  return String.code(char) >= LOWER_FIRST and String.code(char) <= LOWER_LAST
end

def digit?(char: String) -> Bool
  return String.code(char) >= DIGIT_FIRST and String.code(char) <= DIGIT_LAST
end
