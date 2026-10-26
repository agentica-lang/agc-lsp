## Converts between code point counts and UTF-16 code unit counts of a line.

export UTF16 = "utf-16"
export UTF32 = "utf-32"
SURROGATE_START = 65_536

## Returns the UTF-16 width of the first characters of a line.
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

## Returns how many characters of a line fit in the UTF-16 units.
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
