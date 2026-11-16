## Finds the names that an import list `import {a, b as c} from "module"` takes from a file, which `agentica refs` does
## not report, from the outline of the file that imports.

import Uri from "uri"
import Analysis from "std/analysis"

## Returns the entries of the import lists of the file that take the name from the module file. An entry whose local
## name differs renames it with `as`.
def entries(session: Analysis.Session, path: String, module: String, name: String) -> List[Analysis.ImportName]
  found: List[Analysis.ImportName] = []
  case Analysis.outline(session, path)
    ok(outlined) ->
      for imported in outlined.imports
        if imported.alias == "" and imports_from?(path, imported, module)
          found = found.concat(imported.names.filter do |entry| entry.name == name end)
        end
      end

    error(_) -> return found
  end

  return found
end

private

def imports_from?(path: String, imported: Analysis.Import, module: String) -> Bool
  parts = path.split("/")
  folder = parts.take(parts.size - 1).join("/")
  return Uri.same_path?(Uri.resolve(folder, "#{imported.path}.agc"), module)
end
