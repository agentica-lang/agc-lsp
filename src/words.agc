## Scans the words of a line given as a list of characters.

DIGIT_FIRST = 48
DIGIT_LAST = 57
UPPER_FIRST = 65
UPPER_LAST = 90
LOWER_FIRST = 97
LOWER_LAST = 122
UNDERSCORE = 95
KEYWORDS = Set.new([
  "def", "end", "if", "elsif", "else", "case", "for", "while", "return", "struct", "enum", "import", "export",
  "from", "type", "do", "in", "next", "break", "try", "and", "or", "not",
])

## Holds a word, the characters from start up to stop.
export struct Word
  ## Is the text of the word.
  text: String
  ## Is the index of its first character.
  start: Int
  ## Is the index after its last character.
  stop: Int
end

## Returns the word that covers the index, with a trailing ? or !, or an error when there is none.
export def at(chars: List[String], index: Int) -> Result[Word]
  if index < 0 or index >= chars.size
    return error("no character at #{index}")
  end

  point = index
  if suffix?(chars[point]) and point > 0 and word_char?(chars[point - 1])
    point -= 1
  end

  if !word_char?(chars[point])
    return error("not a word at #{point}")
  end

  start = word_start(chars, point)
  stop = point + 1
  while stop < chars.size and word_char?(chars[stop])
    stop += 1
  end

  if stop < chars.size and suffix?(chars[stop]) and !inequality?(chars, stop)
    stop += 1
  end

  return ok(Word(text: chars.take(stop).drop(start).join(""), start: start, stop: stop))
end

## Returns the index where the word that ends at the index starts.
export def word_start(chars: List[String], index: Int) -> Int
  start = index
  while start > 0 and word_char?(chars[start - 1])
    start -= 1
  end

  return start
end

## Returns true when a dot comes right before the index.
export def dotted?(chars: List[String], start: Int) -> Bool
  return start > 0 and chars[start - 1] == "."
end

## Returns the word before the dot that precedes the index, or an error when there is none.
export def receiver(chars: List[String], start: Int) -> Result[Word]
  if !dotted?(chars, start)
    return error("no dot before the word at #{start}")
  end

  stop = start - 1
  first = word_start(chars, stop)
  if first == stop
    return error("no word before the dot at #{stop}")
  end

  return ok(Word(text: chars.take(stop).drop(first).join(""), start: first, stop: stop))
end

## Returns the word after the dot at the index, or an error when there is none.
export def member(chars: List[String], stop: Int) -> Result[Word]
  if stop >= chars.size or chars[stop] != "."
    return error("no dot after the word at #{stop}")
  end

  return at(chars, stop + 1)
end

## Returns true when an opening parenthesis comes at the index.
export def called?(chars: List[String], stop: Int) -> Bool
  return stop < chars.size and chars[stop] == "("
end

## Returns true when the text is a keyword of the language, which names no expression.
export def keyword?(text: String) -> Bool
  return KEYWORDS.include?(text)
end

## Returns true when the text starts with a capital letter.
export def type_name?(text: String) -> Bool
  return text.length > 0 and String.code(text.at(0)) >= UPPER_FIRST and String.code(text.at(0)) <= UPPER_LAST
end

## Returns true when the index is right after the ? or ! that ends a name.
export def after_suffix?(chars: List[String], index: Int) -> Bool
  return index > 1 and index <= chars.size and suffix?(chars[index - 1]) and word_char?(chars[index - 2])
end

## Returns true when a word that is not a keyword is at the index, in code and not in a string or a comment.
export def name_at?(chars: List[String], index: Int) -> Bool
  if !code?(chars, index + 1)
    return false
  end

  case at(chars, index)
    ok(word) -> return !keyword?(word.text)
    error(_) -> return false
  end
end

## Returns true when the index of the line is neither in a string nor in a comment.
export def code?(chars: List[String], upto: Int) -> Bool
  in_string = false
  index = 0
  while index < upto and index < chars.size
    char = chars[index]
    if in_string and char == "\\"
      index += 1
    elsif in_string and char == "\""
      in_string = false
    elsif !in_string and char == "\""
      in_string = true
    elsif !in_string and char == "#"
      return false
    end

    index += 1
  end

  return !in_string
end

def word_char?(char: String) -> Bool
  code = String.code(char)
  return (
    (code >= DIGIT_FIRST and code <= DIGIT_LAST) or
    (code >= UPPER_FIRST and code <= UPPER_LAST) or
    (code >= LOWER_FIRST and code <= LOWER_LAST) or
    code == UNDERSCORE
  )
end

def suffix?(char: String) -> Bool
  return char == "?" or char == "!"
end

def inequality?(chars: List[String], index: Int) -> Bool
  return chars[index] == "!" and index + 1 < chars.size and chars[index + 1] == "="
end
