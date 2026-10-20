FILE_SCHEME = "file://"
LOCALHOST = "localhost"
HEX_DIGITS = "0123456789abcdef"

export def path_of(uri: String) -> Result[String]
  if !uri.starts_with?(FILE_SCHEME)
    return error("not a file URI: #{uri}")
  end
  rest = uri.slice(FILE_SCHEME.length, uri.length - FILE_SCHEME.length)
  slash = rest.index_of("/").unwrap_or(rest.length)
  authority = rest.slice(0, slash)
  if authority != "" and authority.downcase != LOCALHOST
    return error("not a local file URI: #{uri}")
  end
  return decode(rest.slice(slash, rest.length - slash))
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
