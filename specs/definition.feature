Feature: Go to definition
  The editor jumps from a name to the place where it is declared. The text of
  the buffer is what counts, so a function that was just typed is found before
  the file is saved. Locals and builtins are not declared in any file.

  Scenario: a function of the same file is found in the buffer
    Given the language server has started
    When the editor opens "app.agc" with:
      """
      def double(n: Int) -> Int
        return n * 2
      end

      def main() -> Void
        puts(double(21))
      end

      """
    And the editor asks for the definition in "app.agc" at 6:9
    Then the definition at 6:9 is in "app.agc" at 1:5-1:11

  Scenario: a function of an imported module is found at its name
    Given the language server has started
    And the file "lib.agc" contains:
      """
      ## Returns a greeting.
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
    And the editor asks for the definition in "app.agc" at 4:12
    Then the definition at 4:12 is in "lib.agc" at 2:12-2:17

  Scenario: a module in another folder is found through its path
    Given the language server has started
    And the file "shared/names.agc" contains:
      """
      export def shout(name: String) -> String
        return name.upcase
      end

      """
    When the editor opens "app.agc" with:
      """
      import {shout} from "shared/names"

      def main() -> Void
        puts(shout("ana"))
      end

      """
    And the editor asks for the definition in "app.agc" at 4:8
    Then the definition at 4:8 is in "shared/names.agc" at 1:12-1:17

  Scenario: a function of a std module has no definition
    Given the language server has started
    When the editor opens "app.agc" with:
      """
      import Queue from "std/queue"

      def main() -> Void
        queue = Queue.new()
        puts(Queue.size(queue))
      end

      """
    And the editor asks for the definition in "app.agc" at 4:18
    Then there is no definition at 4:18

  Scenario: a folder of the project named std is found like any other
    Given the language server has started
    And the file "std/names.agc" contains:
      """
      export def shout(name: String) -> String
        return name.upcase
      end

      """
    When the editor opens "app.agc" with:
      """
      import {shout} from "./std/names"

      def main() -> Void
        puts(shout("ana"))
      end

      """
    And the editor asks for the definition in "app.agc" at 4:8
    Then the definition at 4:8 is in "std/names.agc" at 1:12-1:17

  Scenario: a local, a builtin and a comment have no definition
    Given the language server has started
    When the editor opens "app.agc" with:
      """
      def main() -> Void
        text = "a,b"
        # text
        parts = text.split(",")
        puts(parts)
      end

      """
    And the editor asks for the definition in "app.agc" at 4:11
    And the editor asks for the definition in "app.agc" at 4:16
    And the editor asks for the definition in "app.agc" at 5:4
    And the editor asks for the definition in "app.agc" at 3:6
    And the editor asks for the definition in "ghost.agc" at 1:1
    Then there is no definition at 4:11
    And there is no definition at 4:16
    And there is no definition at 5:4
    And there is no definition at 3:6
    And there is no definition at 1:1

  Scenario: the location of a name of the same file keeps the URI of the document
    Given the language server has started
    And the file "app.agc" contains:
      """
      def double(n: Int) -> Int
        return n * 2
      end

      def main() -> Void
        puts(double(21))
      end

      """
    When the editor opens "app.agc" through a localhost URI
    And the editor asks for the definition in "app.agc" through a localhost URI at 6:9
    Then the definition at 6:9 is in "app.agc" through a localhost URI at 1:5-1:11

  Scenario: a file that does not check has no definition
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
    And the editor asks for the definition in "app.agc" at 6:9
    Then there is no definition at 6:9

  Scenario Outline: the position of the editor and the location count in the encoding it asked for
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
    And the editor asks for the definition in "app.agc" at <asked>
    Then the definition at <asked> is in "app.agc" at 1:5-1:11

    Examples:
      | offered        | asked |
      | utf-16         | 6:17  |
      | utf-16, utf-32 | 6:16  |

  Scenario: an agentica that cannot run leaves the definition empty and warns
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
    And the editor asks for the definition in "app.agc" at 6:9
    Then there is no definition at 6:9
    And the server warns "cannot answer the request for the definition"
