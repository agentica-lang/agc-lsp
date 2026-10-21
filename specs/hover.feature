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

  Scenario: a method call shows every builtin with that name
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
    And the hover at 4:15 shows these builtins:
      | builtin    |
      | List.size  |
      | Map.size   |
      | Set.size   |
      | Range.size |
    And the hover at 4:15 covers 4:14-4:18

  Scenario: a call on a module or a type shows nothing even when a builtin has that name
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
        puts(Parts.split("a,b"))
      end

      """
    And the editor hovers over "app.agc" at 4:16
    Then there is no hover at 4:16

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
    And the editor hovers over "app.agc" at 2:10
    Then "app.agc" gets these diagnostics:
      | at        | severity | code               |
      | 2:22-2:26 | error    | CHECK-UNKNOWN-NAME |
    And there is no hover at 2:10
    And the server warns "cannot load the builtin catalog"
