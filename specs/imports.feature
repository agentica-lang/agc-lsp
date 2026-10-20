Feature: Errors that come from another file
  An error in an imported file, or in the agentica.toml of the project, is
  shown at the start of the opened file, with a related location that points
  into the file where the error is. Saving that file checks again the open
  files that were pointing into it.

  Scenario Outline: the location in the imported file counts in the encoding the editor asked for
    Given the language server has started with the position encodings "<offered>"
    And the file "lib.agc" contains:
      """
      export def answer() -> Int
        names = ["😀", oops]
        return 1
      end

      """
    And the file "app.agc" contains:
      """
      import Lib from "lib"

      def main() -> Void
        puts(Lib.answer())
      end

      """
    When the editor opens "app.agc"
    Then "app.agc" gets these diagnostics:
      | at      | severity | code               |
      | 1:1-1:1 | error    | CHECK-UNKNOWN-NAME |
    And the diagnostic of "app.agc" points into "lib.agc" at <at>

    Examples:
      | offered        | at        |
      | utf-16         | 2:18-2:22 |
      | utf-16, utf-32 | 2:17-2:21 |

  Scenario: an imported file with a space and an accent in its path is located
    Given the language server has started
    And the file "né/my lib.agc" contains:
      """
      export def answer() -> Int
        return "a"
      end

      """
    And the file "app.agc" contains:
      """
      import Lib from "né/my lib"

      def main() -> Void
        puts(Lib.answer())
      end

      """
    When the editor opens "app.agc"
    Then "app.agc" gets these diagnostics:
      | at      | severity | code                |
      | 1:1-1:1 | error    | CHECK-TYPE-MISMATCH |
    And the diagnostic of "app.agc" points into "né/my lib.agc" at 2:10-2:13

  Scenario: an error in the syntax of agentica.toml points at its position
    Given the language server has started
    And the file "agentica.toml" contains:
      """
      [package

      """
    And the file "app.agc" contains:
      """
      def main() -> Void
        puts("hi")
      end

      """
    When the editor opens "app.agc"
    Then "app.agc" gets these diagnostics:
      | at      | severity | code                 |
      | 1:1-1:1 | error    | PKG-MANIFEST-INVALID |
    And the diagnostic of "app.agc" points into "agentica.toml" at 1:9-1:10

  Scenario: the agentica.toml in a folder above the file is the one reported
    Given the language server has started
    And the file "agentica.toml" contains:
      """
      [package]
      name = 3

      """
    And the file "src/app.agc" contains:
      """
      def main() -> Void
        puts("hi")
      end

      """
    When the editor opens "src/app.agc"
    Then "src/app.agc" gets these diagnostics:
      | at      | severity | code                 |
      | 1:1-1:1 | error    | PKG-MANIFEST-INVALID |
    And the diagnostic of "src/app.agc" points to "agentica.toml (package)"
    And the diagnostic of "src/app.agc" points into "agentica.toml" at 1:1-1:1

  Scenario: saving the imported file after fixing it clears the error of the file that imports it
    Given the language server has started
    And the file "lib.agc" contains:
      """
      export def answer() -> Int
        return "a"
      end

      """
    And the file "app.agc" contains:
      """
      import Lib from "lib"

      def main() -> Void
        puts(Lib.answer())
      end

      """
    When the editor opens "app.agc"
    And the editor saves "lib.agc" without waiting as:
      """
      export def answer() -> Int
        return 1
      end

      """
    And the editor waits for the diagnostics of 2 files
    Then "app.agc" gets these diagnostics:
      | at      | severity | code                |
      | 1:1-1:1 | error    | CHECK-TYPE-MISMATCH |
    And "app.agc" gets no diagnostics
    And "app.agc" gets nothing more

  Scenario: saving the imported file with another error moves the location
    Given the language server has started
    And the file "lib.agc" contains:
      """
      export def answer() -> Int
        return "a"
      end

      """
    And the file "app.agc" contains:
      """
      import Lib from "lib"

      def main() -> Void
        puts(Lib.answer())
      end

      """
    When the editor opens "app.agc"
    And the editor saves "lib.agc" without waiting as:
      """
      export def answer() -> Int
        puts("x")
        return "b"
      end

      """
    And the editor waits for the diagnostics of 2 files
    Then "app.agc" gets these diagnostics:
      | at      | severity | code                |
      | 1:1-1:1 | error    | CHECK-TYPE-MISMATCH |
    And "app.agc" gets these diagnostics:
      | at      | severity | code                |
      | 1:1-1:1 | error    | CHECK-TYPE-MISMATCH |
    And the diagnostic of "app.agc" points into "lib.agc" at 3:10-3:13

  Scenario: saving the agentica.toml after fixing it clears the error of the open file
    Given the language server has started
    And the file "agentica.toml" contains:
      """
      [package]
      name = 3

      """
    And the file "app.agc" contains:
      """
      def main() -> Void
        puts("hi")
      end

      """
    When the editor opens "app.agc"
    And the editor saves "agentica.toml" without waiting as:
      """
      name = "app"

      """
    And the editor waits for diagnostics
    Then "app.agc" gets these diagnostics:
      | at      | severity | code                 |
      | 1:1-1:1 | error    | PKG-MANIFEST-INVALID |
    And "app.agc" gets no diagnostics

  Scenario: every open file that imports the saved file is checked again
    Given the language server has started
    And the file "lib.agc" contains:
      """
      export def answer() -> Int
        return "a"
      end

      """
    And the files "first.agc, second.agc" contain:
      """
      import Lib from "lib"

      def main() -> Void
        puts(Lib.answer())
      end

      """
    When the editor opens the files "first.agc, second.agc" without waiting
    And the editor waits for the diagnostics of 2 files
    And the editor saves "lib.agc" without waiting as:
      """
      export def answer() -> Int
        return 1
      end

      """
    And the editor waits for the diagnostics of 3 files
    Then "first.agc" gets these diagnostics:
      | at      | severity | code                |
      | 1:1-1:1 | error    | CHECK-TYPE-MISMATCH |
    And "first.agc" gets no diagnostics
    And "second.agc" gets these diagnostics:
      | at      | severity | code                |
      | 1:1-1:1 | error    | CHECK-TYPE-MISMATCH |
    And "second.agc" gets no diagnostics

  Scenario: saving a file that nobody was pointing into checks no other file
    Given the language server has started
    And the file "lib.agc" contains:
      """
      export def answer() -> Int
        return "a"
      end

      """
    And the file "app.agc" contains:
      """
      import Lib from "lib"

      def main() -> Void
        puts(Lib.answer())
      end

      """
    And the file "other.agc" contains:
      """
      def main() -> Void
        puts("hi")
      end

      """
    When the editor opens "app.agc"
    And the editor saves "other.agc" as:
      """
      def main() -> Void
        puts("changed")
      end

      """
    And the editor waits 1500 milliseconds
    Then "app.agc" gets these diagnostics:
      | at      | severity | code                |
      | 1:1-1:1 | error    | CHECK-TYPE-MISMATCH |
    And "app.agc" gets nothing more

  Scenario: a closed file is not checked again when the imported file is saved
    Given the language server has started
    And the file "lib.agc" contains:
      """
      export def answer() -> Int
        return "a"
      end

      """
    And the file "app.agc" contains:
      """
      import Lib from "lib"

      def main() -> Void
        puts(Lib.answer())
      end

      """
    When the editor opens "app.agc"
    And the editor closes "app.agc"
    And the editor saves "lib.agc" as:
      """
      export def answer() -> Int
        return 1
      end

      """
    And the editor waits 1500 milliseconds
    Then "app.agc" gets these diagnostics:
      | at      | severity | code                |
      | 1:1-1:1 | error    | CHECK-TYPE-MISMATCH |
    And "app.agc" gets no diagnostics
    And "app.agc" gets nothing more

  Scenario: a file that no longer imports the saved file is not checked again
    Given the language server has started
    And the file "lib.agc" contains:
      """
      export def answer() -> Int
        return "a"
      end

      """
    And the file "app.agc" contains:
      """
      import Lib from "lib"

      def main() -> Void
        puts(Lib.answer())
      end

      """
    When the editor opens "app.agc"
    And the editor saves "app.agc" as:
      """
      def main() -> Void
        puts("no import")
      end

      """
    And the editor saves "lib.agc" as:
      """
      export def answer() -> Int
        return 1
      end

      """
    And the editor waits 1500 milliseconds
    Then "app.agc" gets these diagnostics:
      | at      | severity | code                |
      | 1:1-1:1 | error    | CHECK-TYPE-MISMATCH |
    And "app.agc" gets no diagnostics
    And "app.agc" gets nothing more

  Scenario: saving an imported file under a path with an accent, a space and a hash refreshes the importer
    Given the language server has started
    And the file "né/my #lib.agc" contains:
      """
      export def answer() -> Int
        return "a"
      end

      """
    And the file "app.agc" contains:
      """
      import Lib from "né/my #lib"

      def main() -> Void
        puts(Lib.answer())
      end

      """
    When the editor opens "app.agc"
    And the editor saves "né/my #lib.agc" without waiting as:
      """
      export def answer() -> Int
        return 1
      end

      """
    And the editor waits for the diagnostics of 2 files
    Then "app.agc" gets these diagnostics:
      | at      | severity | code                |
      | 1:1-1:1 | error    | CHECK-TYPE-MISMATCH |
    And "app.agc" gets no diagnostics

  Scenario: an error in a library module is shown without a related location
    Given the language server has started with the arguments "--agentica specs/fixtures/library-agentica"
    And the file "app.agc" contains:
      """
      import Queue from "std/queue"

      def main() -> Void
        puts("hi")
      end

      """
    When the editor opens "app.agc"
    Then "app.agc" gets these diagnostics:
      | at      | severity | code                |
      | 1:1-1:1 | error    | CHECK-TYPE-MISMATCH |
    And the diagnostic of "app.agc" points to "queue.agc:2:10"
    And the diagnostic of "app.agc" has no related location
