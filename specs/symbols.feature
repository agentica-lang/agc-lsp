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

  Scenario: one-line defs, a guard and the declarations below private are listed, the private fields are not
    Given the language server has started
    When the editor opens "app.agc" with:
      """
      LIMIT = 3

      struct Conn
        id: Int

        private

        socket: Int
      end

      def double(x: Int) -> Int = x * 2

      def triple(x: Int) -> Int = x * 3

      def clamp(x: Int) -> Int
        return LIMIT if x > LIMIT
        return x
      end

      private

      SECRET = 1

      def hidden() -> Int = SECRET

      """
    And the editor asks for the symbols of "app.agc"
    Then the symbols of "app.agc" are:
      | symbol  | kind     | at         |
      | LIMIT   | Constant | 1:1-1:6    |
      | Conn    | Struct   | 3:8-3:12   |
      | Conn.id | Field    | 4:3-4:5    |
      | double  | Function | 11:5-11:11 |
      | triple  | Function | 13:5-13:11 |
      | clamp   | Function | 15:5-15:10 |
      | SECRET  | Constant | 22:1-22:7  |
      | hidden  | Function | 24:5-24:11 |

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
