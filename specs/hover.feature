Feature: Hover on builtins
  Hovering over a builtin of Agentica shows its signature and what it does. The
  catalog comes from `agentica --json help`, so the editor needs nothing else.

  Scenario: a qualified builtin shows its signature on either part of the name
    Given the language server has loaded the builtin catalog
    When the editor opens "app.agc" with:
      """
      def main() -> Void
        words = String.split("a,b", ",")
        puts(words)
      end

      """
    And the editor hovers over "app.agc" at 2:13
    And the editor hovers over "app.agc" at 2:20
    Then the hover at 2:13 shows "String.split"
    And the hover at 2:13 covers 2:11-2:23
    And the hover at 2:20 shows "String.split"
    And the hover at 2:20 covers 2:11-2:23

  Scenario: a bare builtin call shows its signature
    Given the language server has loaded the builtin catalog
    When the editor opens "app.agc" with:
      """
      def main() -> Void
        words = String.split("a,b", ",")
        puts(words)
      end

      """
    And the editor hovers over "app.agc" at 3:4
    Then the hover at 3:4 shows "puts"
    And the hover at 3:4 covers 3:3-3:7

  Scenario: a method call shows the builtin of the type of its receiver
    Given the language server has loaded the builtin catalog
    When the editor opens "app.agc" with:
      """
      def main() -> Void
        text = "a,b"
        parts = text.split(",")
        puts(parts.size)
      end

      """
    And the editor hovers over "app.agc" at 3:18
    And the editor hovers over "app.agc" at 4:15
    Then the hover at 3:18 shows "String.split"
    And the hover at 3:18 covers 3:16-3:21
    And the hover at 4:15 shows "List.size"
    And the hover at 4:15 does not show "Map.size"
    And the hover at 4:15 covers 4:14-4:18

  Scenario: a method call in a function with an error shows every builtin with that name
    Given the language server has loaded the builtin catalog
    When the editor opens "app.agc" with:
      """
      def main() -> Void
        parts = ["a", "b"]
        puts(parts.size + oops)
      end

      """
    And the editor hovers over "app.agc" at 3:15
    Then the hover at 3:15 shows these builtins:
      | builtin    |
      | List.size  |
      | Map.size   |
      | Set.size   |
      | Range.size |
    And the hover at 3:15 covers 3:14-3:18

  Scenario: a builtin is shown from the program when the catalog cannot be loaded
    Given the editor asks for the client log level "warning"
    And the language server has started with the arguments "--agentica specs/fixtures/nohelp-agentica"
    And the editor waits for a log message containing "cannot load the builtin catalog"
    When the editor opens "app.agc" with:
      """
      def main() -> Void
        puts(String.upcase("x"))
      end

      """
    And the editor hovers over "app.agc" at 2:16
    Then the hover at 2:16 shows the declaration "String.upcase(s: String) -> String"
    And the hover at 2:16 covers 2:8-2:21

  Scenario: a call of a function of the code shows the type of the expression
    Given the language server has started
    And the file "lib.agc" contains:
      """
      export def greet(name: String) -> String
        return "hello #{name}"
      end

      """
    When the editor opens "app.agc" with:
      """
      import Lib from "lib"

      def double(n: Int) -> Int
        return n * 2
      end

      def main() -> Void
        puts(double(21))
        puts(Lib.greet("Ana"))
      end

      """
    And the editor hovers over "app.agc" at 8:9
    And the editor hovers over "app.agc" at 9:12
    Then the hover at 8:9 shows the type "Int"
    And the hover at 8:9 covers 8:8-8:18
    And the hover at 9:12 shows the type "String"

  Scenario: a function of the code shows its signature and its doc before the type of the call
    Given the language server has started
    And the file "lib.agc" contains:
      """
      ## Returns a greeting for a name.
      ##
      ## The name is used as given.
      export def greet(name: String) -> String
        return "hello #{name}"
      end

      """
    When the editor opens "app.agc" with:
      """
      import Lib from "lib"

      def main() -> Void
        puts(Lib.greet("Ana"))
      end

      """
    And the editor hovers over "app.agc" at 4:12
    Then the hover at 4:12 reads:
      """
      ```agc
      greet(name: String) -> String
      ```

      Returns a greeting for a name.

      The name is used as given.

      ---

      ```agc
      Lib.greet("Ana"): String
      ```
      """
    And the hover at 4:12 covers 4:8-4:24

  Scenario: a field, a struct and a variant show their declaration and their doc
    Given the language server has started
    When the editor opens "app.agc" with:
      """
      ## Holds a point of the plane.
      struct Point
        ## Is the distance to the left edge.
        x: Int
        y: Int
      end

      ## Is the way a shape is drawn.
      enum Pen
        ## Draws a line of a width.
        Line(Int)
        Dot
      end

      def main() -> Void
        point = Point(x: 1, y: 2)
        pen = Pen.Line(3)
        puts(point.x)
      end

      """
    And the editor hovers over "app.agc" at 18:14
    And the editor hovers over "app.agc" at 16:12
    And the editor hovers over "app.agc" at 17:14
    Then the hover at 18:14 shows the declaration "x: Int"
    And the hover at 18:14 shows the documentation "Is the distance to the left edge."
    And the hover at 18:14 shows the type "Int"
    And the hover at 16:12 shows the declaration "struct Point"
    And the hover at 16:12 shows the documentation "Holds a point of the plane."
    And the hover at 17:14 shows the declaration "Line(Int)"
    And the hover at 17:14 shows the documentation "Draws a line of a width."

  Scenario: a local, a parameter and a loop name show their type only
    Given the language server has started
    When the editor opens "app.agc" with:
      """
      def total(limit: Int) -> Int
        sum = 0
        for step in [1, 2, 3]
          sum += step
        end
        return sum + limit
      end

      def main() -> Void
        puts(total(5))
      end

      """
    And the editor hovers over "app.agc" at 6:17
    Then the hover at 6:17 reads:
      """
      ```agc
      limit: Int
      ```
      """

  Scenario: a field with the name of a builtin method shows the field and not the builtin
    Given the language server has loaded the builtin catalog
    When the editor opens "app.agc" with:
      """
      struct Crowd
        ## Is the number of people.
        size: Int
      end

      def main() -> Void
        crowd = Crowd(size: 3)
        puts(crowd.size)
      end

      """
    And the editor hovers over "app.agc" at 8:15
    Then the hover at 8:15 shows the declaration "size: Int"
    And the hover at 8:15 shows the type "Int"
    And the hover at 8:15 does not show "List.size"

  Scenario: a function with an error does not stop the hover in the others
    Given the language server has started
    When the editor opens "app.agc" with:
      """
      ## Returns the double of a number.
      def double(n: Int) -> Int
        return n * 2
      end

      def broken() -> Int
        return "x"
      end

      def main() -> Void
        puts(double(21))
      end

      """
    And the editor hovers over "app.agc" at 11:9
    And the editor hovers over "app.agc" at 7:10
    Then the hover at 11:9 shows the declaration "double(n: Int) -> Int"
    And the hover at 11:9 shows the documentation "Returns the double of a number."
    And there is no hover at 7:10

  Scenario: a name that resolves in a function with an error shows its declaration without a type
    Given the language server has started
    When the editor opens "app.agc" with:
      """
      def double(n: Int) -> Int
        return n * 2
      end

      def main() -> Void
        puts(double(oops))
      end

      """
    And the editor hovers over "app.agc" at 6:9
    And the editor hovers over "app.agc" at 6:16
    Then the hover at 6:9 reads:
      """
      ```agc
      double(n: Int) -> Int
      ```
      """
    And there is no hover at 6:16

  Scenario: a name that is not a builtin shows its type and not the builtin of the same name
    Given the language server has loaded the builtin catalog
    And the file "parts.agc" contains:
      """
      export def split(text: String) -> List[String]
        return text.split(",")
      end

      """
    When the editor opens "app.agc" with:
      """
      import Parts from "parts"

      def main() -> Void
        text = "a,b"
        puts(Parts.split(text))
      end

      """
    And the editor hovers over "app.agc" at 5:16
    And the editor hovers over "app.agc" at 5:21
    Then the hover at 5:16 shows the type "List[String]"
    And the hover at 5:16 does not show "String.split"
    And the hover at 5:21 shows the type "String"

  Scenario: names that are not builtins, comments and strings show nothing
    Given the language server has loaded the builtin catalog
    When the editor opens "app.agc" with:
      """
      def main() -> Void
        # String.split("a", ",")
        text = "puts(String.split)"
        names = greet(text)
        puts(names)
      end

      """
    And the editor hovers over "app.agc" at 2:6
    And the editor hovers over "app.agc" at 3:12
    And the editor hovers over "app.agc" at 3:4
    And the editor hovers over "app.agc" at 4:12
    Then there is no hover at 2:6
    And there is no hover at 3:12
    And there is no hover at 3:4
    And there is no hover at 4:12

  Scenario: positions in UTF-16 find the word after an emoji
    Given the language server has loaded the builtin catalog
    When the editor opens "app.agc" with:
      """
      def main() -> Void
        names = ["😀", String.upcase("x")]
        puts(names)
      end

      """
    And the editor hovers over "app.agc" at 2:30
    Then the hover at 2:30 shows "String.upcase"
    And the hover at 2:30 covers 2:18-2:31

  Scenario: positions in code points find the word after an emoji
    Given the language server has loaded the builtin catalog with the position encodings "utf-16, utf-32"
    When the editor opens "app.agc" with:
      """
      def main() -> Void
        names = ["😀", String.upcase("x")]
        puts(names)
      end

      """
    And the editor hovers over "app.agc" at 2:29
    Then the hover at 2:29 shows "String.upcase"
    And the hover at 2:29 covers 2:17-2:30

  Scenario Outline: the range of a hover on a name counts in the encoding the editor asked for
    Given the language server has started with the position encodings "<offered>"
    When the editor opens "app.agc" with:
      """
      def main() -> Void
        text = "a,b"
        puts("😀" + text)
      end

      """
    And the editor hovers over "app.agc" at <asked>
    Then the hover at <asked> shows the type "String"
    And the hover at <asked> covers <covers>

    Examples:
      | offered        | asked | covers    |
      | utf-16         | 3:16  | 3:15-3:19 |
      | utf-16, utf-32 | 3:15  | 3:14-3:18 |

  Scenario: a document that was closed or never opened shows nothing
    Given the language server has loaded the builtin catalog
    And the file "app.agc" contains:
      """
      def main() -> Void
        puts("hi")
      end

      """
    When the editor opens "app.agc"
    And the editor closes "app.agc"
    And the editor hovers over "app.agc" at 2:4
    And the editor hovers over "ghost.agc" at 1:1
    Then there is no hover at 2:4
    And there is no hover at 1:1

  Scenario: a catalog that cannot be loaded leaves the hover empty and the checks working
    Given the editor asks for the client log level "warning"
    And the language server has started with the arguments "--agentica specs/fixtures/nohelp-agentica"
    And the editor waits for a log message containing "cannot load the builtin catalog"
    When the editor opens "app.agc" with:
      """
      def main() -> Void
        puts(String.upcase(oops))
      end

      """
    And the editor hovers over "app.agc" at 2:23
    Then "app.agc" gets these diagnostics:
      | at        | severity | code               |
      | 2:22-2:26 | error    | CHECK-UNKNOWN-NAME |
    And there is no hover at 2:23
    And the server warns "cannot load the builtin catalog"

  Scenario: a newer hover on a document supersedes the older ones, which are answered with null
    Given the language server has started with the arguments "--agentica specs/fixtures/lagging-agentica"
    When the editor opens "app.agc" with:
      """
      def main() -> Void
        count = 21
        puts(count)
      end

      """
    And the editor hovers over "app.agc" at 3:8 three times in a row
    Then the earlier hovers in a row are answered with null
    And the hover at 3:8 shows the type "Int"

  Scenario: at most four queries run at a time and the others wait their turn
    Given the language server has started with the arguments "--agentica specs/fixtures/lagging-agentica"
    And the files "a.agc, b.agc, c.agc, d.agc, e.agc, f.agc" contain:
      """
      def main() -> Void
        count = 21
        puts(count)
      end

      """
    When the editor opens the files "a.agc, b.agc, c.agc, d.agc, e.agc, f.agc" without waiting
    And the editor waits for the diagnostics of 6 files
    And the editor hovers over each of "a.agc, b.agc, c.agc, d.agc, e.agc, f.agc" at 3:8
    Then the hovers of "a.agc, b.agc, c.agc, d.agc, e.agc, f.agc" at 3:8 show the type "Int"

  Scenario: a hover that the editor cancels is answered as cancelled
    Given the language server has started with the arguments "--agentica specs/fixtures/lagging-agentica"
    When the editor opens "app.agc" with:
      """
      def main() -> Void
        count = 21
        puts(count)
      end

      """
    And the editor hovers over "app.agc" at 3:8 and cancels the request
    Then the hover at 3:8 is answered as cancelled

  Scenario: a hover still running at shutdown is answered with null before the shutdown
    Given the language server has started with the arguments "--agentica specs/fixtures/lagging-agentica"
    When the editor opens "app.agc" with:
      """
      def main() -> Void
        count = 21
        puts(count)
      end

      """
    And the editor hovers over "app.agc" at 3:8 without waiting
    Then there is no hover at 3:8
    And the hover at 3:8 is answered before the shutdown

  Scenario: the code of a hover is fenced with more backticks than its text has
    Given the language server has started
    When the editor opens "app.agc" with:
      """
      def shout(text: String) -> String
        return text.upcase
      end

      def main() -> Void
        puts(shout("```"))
      end

      """
    And the editor hovers over "app.agc" at 6:9
    Then the hover at 6:9 shows the type "String"
    And the hover at 6:9 is fenced with 4 backticks

  Scenario: a keyword, a comment and a blank need no query
    Given the language server has started with the arguments "--agentica specs/fixtures/broken-agentica"
    And the file "app.agc" contains:
      """
      def main() -> Void
        # puts("hi")
        puts("hi")
      end

      """
    When the editor opens "app.agc" without waiting
    And the editor hovers over "app.agc" at 1:2
    And the editor hovers over "app.agc" at 4:2
    And the editor hovers over "app.agc" at 2:1
    And the editor asks for the definition in "app.agc" at 2:6
    And the editor asks for the definition in "app.agc" at 4:2
    Then there is no hover at 1:2
    And there is no hover at 4:2
    And there is no hover at 2:1
    And there is no definition at 2:6
    And there is no definition at 4:2
    And the server never logs "cannot answer the request"
