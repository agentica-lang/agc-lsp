Feature: Find references
  The editor lists where a name is used: in the file, in the files it imports and in the files they use. The text of
  the buffer counts for the file itself; the other files are read from disk. The declaration is part of the list
  unless the editor leaves it out.

  Scenario: the uses of a function are listed with its declaration
    Given the language server has started
    When the editor opens "app.agc" with:
      """
      def double(n: Int) -> Int
        return n * 2
      end

      def main() -> Void
        puts(double(21))
        puts(double(double(2)))
      end

      """
    And the editor asks for the references in "app.agc" at 6:9
    Then the references at 6:9 are:
      | file    | at        |
      | app.agc | 1:5-1:11  |
      | app.agc | 6:8-6:14  |
      | app.agc | 7:8-7:14  |
      | app.agc | 7:15-7:21 |

  Scenario: the editor can leave the declaration out
    Given the language server has started
    When the editor opens "app.agc" with:
      """
      def double(n: Int) -> Int
        return n * 2
      end

      def main() -> Void
        puts(double(21))
        puts(double(double(2)))
      end

      """
    And the editor asks for the references in "app.agc" at 6:9 without the declaration
    Then the references at 6:9 are:
      | file    | at        |
      | app.agc | 6:8-6:14  |
      | app.agc | 7:8-7:14  |
      | app.agc | 7:15-7:21 |

  Scenario: the declaration and the uses in an imported module are listed
    Given the language server has started
    And the file "lib.agc" contains:
      """
      export def greet(name: String) -> String
        return "hello #{name}"
      end

      export def twice(name: String) -> String
        return greet(greet(name))
      end

      """
    When the editor opens "app.agc" with:
      """
      import Lib from "lib"

      def main() -> Void
        puts(Lib.greet("Ana"))
      end

      """
    And the editor asks for the references in "app.agc" at 4:12
    Then the references at 4:12 are:
      | file    | at        |
      | lib.agc | 1:12-1:17 |
      | lib.agc | 6:10-6:15 |
      | lib.agc | 6:16-6:21 |
      | app.agc | 4:12-4:17 |

  Scenario: a local is listed with its uses in the buffer
    Given the language server has started
    When the editor opens "app.agc" with:
      """
      def main() -> Void
        count = 21
        puts(count)
        puts(count + 1)
      end

      """
    And the editor asks for the references in "app.agc" at 3:8
    Then the references at 3:8 are:
      | file    | at       |
      | app.agc | 2:3-2:8  |
      | app.agc | 3:8-3:13 |
      | app.agc | 4:8-4:13 |

  Scenario: a function with an error does not stop the references in the others
    Given the language server has started
    When the editor opens "app.agc" with:
      """
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
    And the editor asks for the references in "app.agc" at 10:9
    Then the references at 10:9 are:
      | file    | at         |
      | app.agc | 1:5-1:11   |
      | app.agc | 10:8-10:14 |

  Scenario: a keyword, a comment, a blank and a document that is not open need no query
    Given the language server has started with the arguments "--agentica specs/fixtures/broken-agentica"
    And the file "app.agc" contains:
      """
      def main() -> Void
        # puts("hi")
        puts("hi")
      end

      """
    When the editor opens "app.agc" without waiting
    And the editor asks for the references in "app.agc" at 1:2
    And the editor asks for the references in "app.agc" at 4:2
    And the editor asks for the references in "app.agc" at 2:6
    And the editor asks for the references in "ghost.agc" at 1:1
    Then there are no references at 1:2
    And there are no references at 4:2
    And there are no references at 2:6
    And there are no references at 1:1
    And the server never logs "cannot answer the request"

  Scenario: a name that agentica finds no expression at has no references and no warning
    Given the language server has started
    When the editor opens "app.agc" with:
      """
      def double(n: Int) -> Int
        return n * 2
      end

      """
    And the editor asks for the references in "app.agc" at 1:15
    Then there are no references at 1:15
    And the server never logs "cannot answer the request"

  Scenario: an agentica that cannot run leaves the references empty and warns
    Given the language server has started with the arguments "--agentica specs/fixtures/broken-agentica"
    And the file "app.agc" contains:
      """
      def double(n: Int) -> Int
        return n * 2
      end

      def main() -> Void
        puts(double(21))
      end

      """
    When the editor opens "app.agc" without waiting
    And the editor asks for the references in "app.agc" at 6:9
    Then there are no references at 6:9
    And the server warns "cannot answer the request for the references"

  Scenario Outline: the position of the editor and the locations count in the encoding it asked for
    Given the language server has started with the position encodings "<offered>"
    When the editor opens "app.agc" with:
      """
      def double(n: Int) -> Int
        return n * 2
      end

      def main() -> Void
        puts("😀" + double(21).to_s)
      end

      """
    And the editor asks for the references in "app.agc" at <asked>
    Then the references at <asked> are:
      | file    | at       |
      | app.agc | 1:5-1:11 |
      | app.agc | <use>    |

    Examples:
      | offered        | asked | use       |
      | utf-16         | 6:17  | 6:15-6:21 |
      | utf-16, utf-32 | 6:16  | 6:14-6:20 |
