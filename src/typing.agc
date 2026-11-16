## Reads the brackets that are open at a position of a line, and repairs a buffer that the editor left in the middle of
## typing so that std/analysis can read it.

## Holds a bracket that is open at the position: its character and index, the commas after it and the index after the
## last of them.
struct Frame
  ## Is the opening character: (, [ or {.
  bracket: String
  ## Is the index of the bracket in the line.
  open: Int
  ## Counts the commas of the bracket that are before the position.
  commas: Int
  ## Is the index where the argument at the position starts.
  segment: Int
end

## Returns the brackets that are open at the index of the line, from the outermost to the innermost. A string and a
## comment hide their brackets.
def frames(chars: List[String], upto: Int) -> List[Frame]
  open: List[Frame] = []
  in_string = false
  index = 0
  while index < upto and index < chars.size
    char = chars[index]
    if in_string and char == "\\"
      index += 1
    elsif in_string
      in_string = char != "\""
    elsif char == "\""
      in_string = true
    elsif char == "#"
      return open
    elsif OPENERS.include?(char)
      open = open.push(Frame(bracket: char, open: index, commas: 0, segment: index + 1))
    elsif CLOSERS.include?(char) and open.size > 0
      open = open.take(open.size - 1)
    elsif char == "," and open.size > 0
      last = open.size - 1
      open = open.take(last).push(open[last].with(commas: open[last].commas + 1, segment: index + 1))
    end

    index += 1
  end

  return open
end

## Returns the text of the document in which the line is cut after the first `keep` characters and the brackets that
## the cut leaves open are closed.
def repaired(text: String, line: Int, chars: List[String], keep: Int) -> String
  lines = text.split("\n")
  lines = lines.take(line).push("#{chars.take(keep).join("")}#{closers(chars, keep)}").concat(lines.drop(line + 1))
  return lines.join("\n")
end

## Returns the characters that close the brackets open at the index of the line.
def closers(chars: List[String], upto: Int) -> String
  shut = frames(chars, upto).reverse.map do |frame| MATCHING.get(frame.bracket).unwrap_or("") end
  return shut.join("")
end

private

OPENERS = Set.new(["(", "[", "{"])

CLOSERS = Set.new([")", "]", "}"])

MATCHING = {"(": ")", "[": "]", "{": "}"}
