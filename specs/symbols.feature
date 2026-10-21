Feature: Document symbols
  The outline of a file lists what it declares, from the text of the buffer:
  fields under their struct and variants under their enum.

  Scenario: the declarations of a file are listed with their kinds and names
    Given the language server has started
    When the editor opens "app.agc" with:
      """
      LIMIT = 3

      ## A point.
      struct Point
        ## The x.
        x: Int
        y: Int
      end

      enum Shape
        Dot
        Circle(Int)
      end

      type Names = List[String]

      def double(n: Int) -> Int
        return n * 2
      end

      def main() -> Void
        puts(double(LIMIT))
      end

      """
    And the editor asks for the symbols of "app.agc"
    Then the symbols of "app.agc" are:
      | symbol       | kind          | at         |
      | LIMIT        | Constant      | 1:1-1:6    |
      | Point        | Struct        | 4:8-4:13   |
      | Point.x      | Field         | 6:3-6:4    |
      | Point.y      | Field         | 7:3-7:4    |
      | Shape        | Enum          | 10:6-10:11 |
      | Shape.Dot    | EnumMember    | 11:3-11:6  |
      | Shape.Circle | EnumMember    | 12:3-12:9  |
      | Names        | TypeParameter | 15:6-15:11 |
      | double       | Function      | 17:5-17:11 |
      | main         | Function      | 21:5-21:9  |

  Scenario: a file that does not check still lists its symbols and one that does not parse lists none
    Given the language server has started
    When the editor opens "typed.agc" with:
      """
      def double(n: Int) -> Int
        return n * "2"
      end

      def main() -> Void
        puts(double(1))
      end

      """
    And the editor opens "broken.agc" with:
      """
      def double(n: Int -> Int
        return n * 2
      end

      """
    And the editor asks for the symbols of "typed.agc"
    And the editor asks for the symbols of "broken.agc"
    And the editor asks for the symbols of "ghost.agc"
    Then the symbols of "typed.agc" are:
      | symbol | kind     | at       |
      | double | Function | 1:5-1:11 |
      | main   | Function | 5:5-5:9  |
    And there are no symbols for "broken.agc"
    And there are no symbols for "ghost.agc"

  Scenario: a kind of declaration that the server does not know is listed as a variable
    Given the language server has started with the arguments "--agentica specs/fixtures/futuristic-agentica"
    When the editor opens "app.agc" with:
      """
      macro shout
      end

      """
    And the editor asks for the symbols of "app.agc"
    Then the symbols of "app.agc" are:
      | symbol | kind     | at       |
      | shout  | Variable | 1:7-1:12 |

  Scenario Outline: the range of a symbol counts in the encoding the editor asked for
    Given the language server has started with the position encodings "<offered>"
    When the editor opens "app.agc" with:
      """
      GREETING = "😀"
      """
    And the editor asks for the symbols of "app.agc"
    Then the symbol "GREETING" of "app.agc" covers <covers>

    Examples:
      | offered        | covers   |
      | utf-16         | 1:1-1:16 |
      | utf-16, utf-32 | 1:1-1:15 |
