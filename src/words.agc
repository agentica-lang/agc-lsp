export struct Word
  text: String
  start: Int
  stop: Int
end

export def at(chars: List[String], index: Int) -> Result[Word]
  if index < 0 or index >= chars.size
    return error("no character at #{index}")
  end
  point = index
  if suffix?(chars[point]) and point > 0 and word_char?(chars[point - 1])
    point -= 1
  end
  if !word_char?(chars[point])
    return error("not a word")
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

export def word_start(chars: List[String], index: Int) -> Int
  start = index
  while start > 0 and word_char?(chars[start - 1])
    start -= 1
  end
  return start
end

export def dotted?(chars: List[String], start: Int) -> Bool
  return start > 0 and chars[start - 1] == "."
end

export def receiver(chars: List[String], start: Int) -> Result[Word]
  if !dotted?(chars, start)
    return error("no dot before the word")
  end
  stop = start - 1
  first = word_start(chars, stop)
  if first == stop
    return error("no word before the dot")
  end
  return ok(Word(text: chars.take(stop).drop(first).join(""), start: first, stop: stop))
end

export def member(chars: List[String], stop: Int) -> Result[Word]
  if stop >= chars.size or chars[stop] != "."
    return error("no dot after the word")
  end
  return at(chars, stop + 1)
end

export def called?(chars: List[String], stop: Int) -> Bool
  return stop < chars.size and chars[stop] == "("
end

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
  return (code >= 48 and code <= 57) or (code >= 65 and code <= 90) or (code >= 97 and code <= 122) or code == 95
end

def suffix?(char: String) -> Bool
  return char == "?" or char == "!"
end

def inequality?(chars: List[String], index: Int) -> Bool
  return chars[index] == "!" and index + 1 < chars.size and chars[index + 1] == "="
end
