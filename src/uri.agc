FILE_SCHEME = "file://"
HEX_DIGITS = "0123456789abcdef"

export def path_of(uri: String) -> Result[String]
  if !uri.starts_with?(FILE_SCHEME)
    return error("not a file URI: #{uri}")
  end
  return decode(uri.slice(FILE_SCHEME.length, uri.length - FILE_SCHEME.length))
end

def decode(text: String) -> Result[String]
  chars = text.split("")
  data: List[Int] = []
  index = 0
  while index < chars.size
    char = chars[index]
    if char == "%" and index + 2 < chars.size
      high = try digit(chars[index + 1])
      low = try digit(chars[index + 2])
      data = data.push(high * 16 + low)
      index += 3
    else
      data = data.concat(char.to_bytes)
      index += 1
    end
  end
  return String.from_bytes(data)
end

def digit(char: String) -> Result[Int]
  return HEX_DIGITS.index_of(char.downcase)
end
