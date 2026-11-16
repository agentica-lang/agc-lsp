## Finds the places where an import list `import {a, b as c} from "module"` names a declaration, which `agentica refs`
## does not report.

import Words from "words"

## Holds a name in an import list: its line, its character index, and whether its entry has an `as`.
struct Site
  ## Is the zero-based line.
  line: Int
  ## Is the character index of the name in the line.
  character: Int
  ## Is true when the entry renames the name with `as`, or the name is the one that `as` gives.
  aliased: Bool
end

## Returns the sites of the name in the import lists of the lines that import from the module, a name without folder
## or extension such as `lib`.
def sites(lines: List[String], name: String, module: String) -> List[Site]
  found: List[Site] = []
  index = 0
  while index < lines.size
    if lines[index].start_with?("import {")
      stop = list_end(lines, index)
      if from_module(lines[stop]) == module
        found = found.concat(listed(lines, index, stop, name))
      end

      index = stop
    end

    index += 1
  end

  return found
end

private

def list_end(lines: List[String], start: Int) -> Int
  stop = start
  while stop < lines.size - 1 and !lines[stop].include?("}")
    stop += 1
  end

  return stop
end

def from_module(line: String) -> String
  parts = line.split("from \"")
  if parts.size < 2
    return ""
  end

  quoted = parts[parts.size - 1].split("\"")[0]
  segments = quoted.split("/")
  return segments[segments.size - 1]
end

def listed(lines: List[String], start: Int, stop: Int, name: String) -> List[Site]
  found: List[Site] = []
  for line in start...(stop + 1)
    text = lines[line]
    from = 0
    if line == start
      from = text.index_of("{").unwrap_or(-1) + 1
    end

    to = text.length
    if line == stop
      to = text.index_of("}").unwrap_or(text.length)
    end

    for character in Words.occurrences(text, name)
      if character >= from and character < to
        found = found.push(Site(line: line, character: character, aliased: aliased?(text, character, name, from, to)))
      end
    end
  end

  return found
end

def aliased?(text: String, character: Int, name: String, from: Int, to: Int) -> Bool
  before = text.slice(from, character - from).split(",")
  after = text.slice(character + name.length, to - character - name.length).split(",")
  entry = "#{last_of(before)}#{name}#{first_of(after)}"
  return entry.include?(" as ")
end

def last_of(parts: List[String]) -> String
  if parts.size == 0
    return ""
  end

  return parts[parts.size - 1]
end

def first_of(parts: List[String]) -> String
  if parts.size == 0
    return ""
  end

  return parts[0]
end
