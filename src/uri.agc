## Converts between file URIs and paths.

FILE_SCHEME = "file://"
LOCALHOST = "localhost"
HEX_DIGITS = "0123456789abcdef"
HEX_UPPER = "0123456789ABCDEF"
ASCII_LIMIT = 128

## Returns the path of a local file URI, or an error for another URI.
export def path_of(uri: String) -> Result[String]
  if !uri.starts_with?(FILE_SCHEME)
    return error("not a file URI: #{uri}")
  end
  rest = before(before(uri.slice(FILE_SCHEME.length, uri.length - FILE_SCHEME.length), "#"), "?")
  slash = rest.index_of("/").unwrap_or(rest.length)
  authority = rest.slice(0, slash)
  if authority != "" and authority.downcase != LOCALHOST
    return error("not a local file URI: #{uri}")
  end
  return decode(rest.slice(slash, rest.length - slash))
end

## Returns the file URI of a path, with percent escapes for spaces, marks and non-ASCII characters.
export def of_path(path: String) -> String
  parts: List[String] = []
  for char in path.split("")
    if char == " " or char == "%" or char == "#" or char == "?" or String.code(char) >= ASCII_LIMIT
      for byte in char.to_bytes
        parts = parts.push("%#{HEX_UPPER.at(byte / 16)}#{HEX_UPPER.at(byte % 16)}")
      end
    else
      parts = parts.push(char)
    end
  end
  return "#{FILE_SCHEME}#{parts.join("")}"
end

## Returns true when both paths are the same file, resolving links when both exist.
export def same_path?(a: String, b: String) -> Bool
  if a == b
    return true
  end
  case Path.real(a)
    ok(first) ->
      case Path.real(b)
        ok(second) -> return first == second
        error(_) -> return false
      end
    error(_) -> return false
  end
end

## Returns the absolute path of a file that agentica names relative to a folder (without a leading ./), or as it is.
export def resolve(folder: String, file: String) -> String
  if file.starts_with?("/")
    return file
  end
  relative = file
  while relative.starts_with?("./")
    relative = relative.slice(2, relative.length - 2)
  end
  if folder == "/"
    return "/#{relative}"
  end
  return "#{folder}/#{relative}"
end

## Returns the path without the slashes at its end, except the root.
export def trimmed(path: String) -> String
  shorter = path
  while shorter.length > 1 and shorter.ends_with?("/")
    shorter = shorter.slice(0, shorter.length - 1)
  end
  return shorter
end

def before(text: String, mark: String) -> String
  case text.index_of(mark)
    ok(at) -> return text.slice(0, at)
    error(_) -> return text
  end
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
