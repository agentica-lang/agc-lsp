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

  Scenario: the files below the folder where the server started are found at their place
    Given the language server has started in the folder of the project
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

  Scenario: a type name in a signature is found where the type is declared
    Given the language server has started
    And the file "models.agc" contains:
      """
      export struct User
        name: String
      end

      """
    When the editor opens "app.agc" with:
      """
      import Models from "models"

      struct Cell
        value: Int
      end

      def make(cell: Cell, user: Models.User) -> Cell
        return cell
      end

      def main() -> Void
        puts(make(Cell(value: 1), Models.User(name: "Ana")).value)
      end

      """
    And the editor asks for the definition in "app.agc" at 7:17
    And the editor asks for the definition in "app.agc" at 7:36
    And the editor asks for the definition in "app.agc" at 7:45
    Then the definition at 7:17 is in "app.agc" at 3:8-3:12
    And the definition at 7:36 is in "models.agc" at 1:15-1:19
    And the definition at 7:45 is in "app.agc" at 3:8-3:12

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

  Scenario: a local, a parameter, a loop name and a pattern name are found where they are declared
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

      def pick(answer: Result[Int]) -> Int
        case answer
          ok(value) -> return value
          error(_) -> return 0
        end
      end

      def main() -> Void
        puts(total(pick(ok(1))))
      end

      """
    And the editor asks for the definition in "app.agc" at 4:5
    And the editor asks for the definition in "app.agc" at 4:12
    And the editor asks for the definition in "app.agc" at 6:10
    And the editor asks for the definition in "app.agc" at 6:17
    And the editor asks for the definition in "app.agc" at 11:26
    Then the definition at 4:5 is in "app.agc" at 2:3-2:6
    And the definition at 4:12 is in "app.agc" at 3:7-3:11
    And the definition at 6:10 is in "app.agc" at 2:3-2:6
    And the definition at 6:17 is in "app.agc" at 1:11-1:16
    And the definition at 11:26 is in "app.agc" at 11:8-11:13

  Scenario: a builtin and a comment have no definition
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
    And the editor asks for the definition in "app.agc" at 4:16
    And the editor asks for the definition in "app.agc" at 5:4
    And the editor asks for the definition in "app.agc" at 3:6
    And the editor asks for the definition in "ghost.agc" at 1:1
    Then there is no definition at 4:16
    And there is no definition at 5:4
    And there is no definition at 3:6
    And there is no definition at 1:1

  Scenario: a function with an error does not stop the definition in the others
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
    And the editor asks for the definition in "app.agc" at 10:9
    And the editor asks for the definition in "app.agc" at 6:10
    Then the definition at 10:9 is in "app.agc" at 1:5-1:11
    And there is no definition at 6:10

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

  Scenario: a name that is not declared has no definition
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
    And the editor asks for the definition in "app.agc" at 6:16
    Then the definition at 6:9 is in "app.agc" at 1:5-1:11
    And there is no definition at 6:16

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
