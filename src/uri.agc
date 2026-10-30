## Converts between file URIs and paths.
##
## A path that starts with a letter and a colon, followed by a slash, a backslash or nothing, is a drive path on every
## system: its letter is lower case and its `\` are `/`. On Unix a relative path such as `a:/b` is therefore read as
## the drive `a:`. That is accepted so that one code path serves all systems and the Unix scenarios can exercise it.
## Only the letter is folded when paths are compared, so the rest of a path of an unsaved file must match in case.

FILE_SCHEME = "file://"
LOCALHOST = "localhost"
HEX_DIGITS = "0123456789abcdef"
HEX_UPPER = "0123456789ABCDEF"
ASCII_LIMIT = 128
LOWER_A = 97
LOWER_Z = 122

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

  path = try decode(rest.slice(slash, rest.length - slash))
  if path.starts_with?("/") and drive?(path.slice(1, path.length - 1))
    return ok(normal(path.slice(1, path.length - 1)))
  end

  return ok(path)
end

## Returns the file URI of a path, with percent escapes for spaces, marks and non-ASCII characters.
export def of_path(path: String) -> String
  parts: List[String] = []
  if drive?(path)
    parts = parts.push("/")
  end

  for char in normal(path).split("")
    if char == " " or char == "%" or char == "#" or char == "?" or String.code(char) >= ASCII_LIMIT
      for byte in char.bytes
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
  if normal(a) == normal(b)
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

## Returns true when the path starts at the root of a drive or of the file system.
export def absolute?(path: String) -> Bool
  return path.starts_with?("/") or drive?(path)
end

## Returns the absolute path of a file that agentica names relative to a folder (without a leading ./), or as it is.
export def resolve(folder: String, file: String) -> String
  if absolute?(file)
    return normal(file)
  end

  relative = file
  if drive?(folder)
    relative = file.replace("\\", "/")
  end

  while relative.starts_with?("./")
    relative = relative.slice(2, relative.length - 2)
  end

  if folder.ends_with?("/")
    return "#{folder}#{relative}"
  end

  return "#{folder}/#{relative}"
end

## Returns the path without the slashes at its end, except the root.
export def trimmed(path: String) -> String
  shorter = normal(path)
  while shorter.length > 1 and shorter.ends_with?("/") and !drive_root?(shorter)
    shorter = shorter.slice(0, shorter.length - 1)
  end

  return shorter
end

def normal(path: String) -> String
  if !drive?(path)
    return path
  end

  return "#{path.slice(0, 1).downcase}#{path.slice(1, path.length - 1).replace("\\", "/")}"
end

def drive_root?(path: String) -> Bool
  return path.length == 3 and drive?(path) and path.ends_with?("/")
end

def drive?(text: String) -> Bool
  if text.length < 2 or text.at(1) != ":"
    return false
  end

  if text.length > 2 and text.at(2) != "/" and text.at(2) != "\\"
    return false
  end

  code = String.code(text.at(0).downcase)
  return code >= LOWER_A and code <= LOWER_Z
end

def before(text: String, mark: String) -> String
  case text.index_of(mark)
    some(at) -> return text.slice(0, at)
    none -> return text
  end
end

def decode(text: String) -> Result[String]
  chars = text.split("")
  parts: List[Bytes] = []
  index = 0
  while index < chars.size
    char = chars[index]
    if char == "%" and index + 2 < chars.size
      high = try digit(chars[index + 1])
      low = try digit(chars[index + 2])
      parts = parts.push(try Bytes.from_list([high * 16 + low]))
      index += 3
    else
      parts = parts.push(char.bytes)
      index += 1
    end
  end

  return String.from_bytes(Bytes.concat(parts))
end

def digit(char: String) -> Result[Int]
  return HEX_DIGITS.index_of(char.downcase).to_result("not a hex digit: #{char}")
end
