## Answers prepareRename and rename requests with the declaration and the uses that `agentica refs` finds, and refuses
## a rename that could leave a use behind.

import Imports from "imports"
import Lookup from "lookup"
import Places from "places"
import Analysis from "std/analysis"
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

## Returns the range and the name that the editor shows before it asks for the new name, or null when the cursor is on
## no place of the name, or an error that says why the name cannot be renamed.
def prepare(request: Request) -> Result[JSON.Value]
  found = try Lookup.uses(request.lookup)
  case found
    some(uses) -> return prepare_from(request, uses)
    none -> return ok(JSON.null())
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

IMPORTED_KINDS = Set.new(["function", "struct", "enum", "alias", "constant"])

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

def prepare_from(request: Request, uses: Analysis.Refs) -> Result[JSON.Value]
  plan = try planned_from(request, uses)
  case named_at(request, plan.places)
    some(place) ->
      lines = Places.lines_of(request.lookup.documents, request.lookup.path)
      range = Places.range(lines, place.range, request.lookup.cursor.encoding)
      return ok(JSON.object({"range": range, "placeholder": JSON.from(plan.definition.name)}))
    none -> return ok(JSON.null())
  end
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
  aliased = aliased_in(request, definition, places)
  if aliased != ""
    return error("#{definition.name} is imported with `as` in #{aliased}: rename it there by hand")
  end

  other = elsewhere(request, definition, places)
  if other != ""
    return error("#{definition.name} is also written in #{other}, which agentica does not read with this file")
  end

  return ok(Plan(definition: definition, places: places))
end

# A public name may be used by a file that imports its module, and agentica reads only the file and what it imports.
# So the rename is refused when another file of the workspace holds the name as a word.
def elsewhere(request: Request, definition: Analysis.Symbol, places: List[Place]) -> String
  if !public?(request, definition)
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

def public?(request: Request, definition: Analysis.Symbol) -> Bool
  if definition.kind == "parameter"
    return exported_function?(request, definition)
  end

  return !LOCAL_KINDS.include?(definition.kind) and definition.exported
end

# A parameter of a public function is named by the arguments of its calls in other files. One of a lambda is not.
def exported_function?(request: Request, definition: Analysis.Symbol) -> Bool
  path = Uri.resolve(request.lookup.folder, definition.module)
  case Analysis.outline(request.lookup.session, path)
    ok(outlined) ->
      case owner_exported(outlined.items, definition)
        some(exported) -> return exported
        none -> return false
      end

    error(_) -> return true
  end
end

def owner_exported(items: List[Analysis.Item], definition: Analysis.Symbol) -> Optional[Bool]
  line = definition.name_range.start.line
  for item in items
    if item.kind == "module"
      inner = owner_exported(item.items, definition)
      if inner.some?
        return inner
      end
    elsif item.kind == "function" and declares?(item, definition.name, line)
      return some(item.exported)
    end
  end

  return none
end

def declares?(item: Analysis.Item, name: String, line: Int) -> Bool
  first = item.name_range.start.line
  return line >= first and line <= first + item.parameters.size and item.parameters.any? do |one| one.name == name end
end

def aliased_in(request: Request, definition: Analysis.Symbol, places: List[Place]) -> String
  if !IMPORTED_KINDS.include?(definition.kind) or !definition.exported
    return ""
  end

  for path in plan_files(request, places)
    for entry in import_entries(request, path, definition)
      if entry.local != entry.name
        return path
      end
    end
  end

  return ""
end

def plan_files(request: Request, places: List[Place]) -> List[String]
  paths: List[String] = []
  for place in places
    path = Uri.resolve(request.lookup.folder, place.file)
    if !paths.include?(path)
      paths = paths.push(path)
    end
  end

  return paths
end

def import_entries(request: Request, path: String, definition: Analysis.Symbol) -> List[Analysis.ImportName]
  module = Uri.resolve(request.lookup.folder, definition.module)
  return Imports.entries(request.lookup.session, path, module, definition.name)
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
  for path in plan_files(request, plan.places)
    if !Places.known?(lookup.documents, path)
      return error("cannot read #{path}")
    end

    lines = Places.lines_of(lookup.documents, path)
    found: List[JSON.Value] = []
    for place in plan.places
      if Uri.same_path?(Uri.resolve(lookup.folder, place.file), path)
        found = found.push(edit_of(Places.range(lines, place.range, lookup.cursor.encoding), name))
      end
    end

    for entry in import_entries(request, path, plan.definition)
      if !declared?(plan.places, request, path, entry)
        found = found.push(edit_of(Places.range(lines, entry.range, lookup.cursor.encoding), name))
      end
    end

    changes = changes.put(uri_of(request, path), found)
  end

  grouped: Map[String, JSON.Value] = {}
  for uri in changes.keys
    grouped = grouped.put(uri, JSON.array(changes.get(uri).unwrap_or([])))
  end

  return ok(JSON.object({"changes": JSON.object(grouped)}))
end

def edit_of(range: JSON.Value, name: String) -> JSON.Value
  return JSON.object({"range": range, "newText": JSON.from(name)})
end

# A site that agentica reports as a use is renamed already.
def declared?(places: List[Place], request: Request, path: String, entry: Analysis.ImportName) -> Bool
  for place in places
    same = Uri.same_path?(Uri.resolve(request.lookup.folder, place.file), path)
    start = entry.range.start
    if same and place.range.start.line == start.line and place.range.start.column == start.column
      return true
    end
  end

  return false
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
