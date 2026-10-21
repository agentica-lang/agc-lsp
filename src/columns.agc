SURROGATE_START = 65536

export def utf16_width(line: String, characters: Int) -> Int
  chars = line.split("")
  width = 0
  for char in chars.take(smaller(characters, chars.size))
    width += units_of(char)
  end
  if characters > chars.size
    width += characters - chars.size
  end
  return width
end

export def characters_in(line: String, units: Int) -> Int
  chars = line.split("")
  used = 0
  index = 0
  for char in chars
    if used >= units
      break
    end
    used += units_of(char)
    index += 1
  end
  return index
end

def units_of(char: String) -> Int
  if String.code(char) >= SURROGATE_START
    return 2
  end
  return 1
end

def smaller(a: Int, b: Int) -> Int
  if a < b
    return a
  end
  return b
end
