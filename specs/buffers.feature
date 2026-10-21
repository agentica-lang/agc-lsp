Feature: Unsaved buffers
  The server checks the text of the editor's buffer, not the file on disk. It
  checks again on every change, so a diagnostic follows what is typed before
  the file is saved.

  Scenario: typing an error shows its diagnostic and fixing it clears it
    Given the language server has started
    And the file "draft.agc" contains:
      """
      def main() -> Void
        puts("hi")
      end

      """
    When the editor opens "draft.agc"
    And the editor types in "draft.agc":
      """
      def main() -> Void
        puts(oops)
      end

      """
    And the editor types in "draft.agc":
      """
      def main() -> Void
        puts("fixed")
      end

      """
    Then "draft.agc" gets no diagnostics
    And "draft.agc" gets these diagnostics:
      | at       | severity | code               |
      | 2:8-2:12 | error    | CHECK-UNKNOWN-NAME |
    And "draft.agc" gets no diagnostics

  Scenario: a new file that is not on disk is checked from its buffer
    Given the language server has started
    When the editor opens "new.agc" with:
      """
      def main() -> Void
        puts(oops)
      end

      """
    Then "new.agc" gets these diagnostics:
      | at       | severity | code               |
      | 2:8-2:12 | error    | CHECK-UNKNOWN-NAME |

  Scenario: the buffer wins over the file on disk
    Given the language server has started
    And the file "draft.agc" contains:
      """
      def main() -> Void
        puts(oops)
      end

      """
    When the editor opens "draft.agc" with:
      """
      def main() -> Void
        puts("fixed")
      end

      """
    And the editor saves "draft.agc" without changes
    Then "draft.agc" gets no diagnostics
    And "draft.agc" gets no diagnostics

  Scenario: positions count in the buffer, not in the file on disk
    Given the language server has started
    And the file "emoji.agc" contains:
      """
      def main() -> Void
        names = ["x", oops]
      end

      """
    When the editor opens "emoji.agc" with:
      """
      def main() -> Void
        names = ["😀", oops]
      end

      """
    Then "emoji.agc" gets these diagnostics:
      | at        | severity | code               |
      | 2:18-2:22 | error    | CHECK-UNKNOWN-NAME |

  Scenario: several quick changes publish only the diagnostics of the last text
    Given the language server has started with the arguments "--agentica specs/fixtures/slow-agentica"
    And the file "draft.agc" contains:
      """
      def main() -> Void
        puts("hi")
      end

      """
    When the editor opens "draft.agc" without waiting
    And the editor types in "draft.agc" without waiting:
      """
      def main() -> Void
        puts(oops)
      end

      """
    And the editor types in "draft.agc" without waiting:
      """
      def main() -> Void
        puts(nothing)
      end

      """
    And the editor types in "draft.agc" without waiting:
      """
      def main() -> Void
        puts(x)
      end

      """
    And the editor waits for diagnostics
    And the editor waits 1500 milliseconds
    Then "draft.agc" gets these diagnostics:
      | at      | severity | code               |
      | 2:8-2:9 | error    | CHECK-UNKNOWN-NAME |
    And "draft.agc" gets nothing more

  Scenario: an unsaved file imports from its own folder
    Given the language server has started
    And the file "app/lib.agc" contains:
      """
      export def answer() -> Int
        return "a"
      end

      """
    When the editor opens "app/main.agc" with:
      """
      import Lib from "lib"

      def main() -> Void
        puts(Lib.answer())
      end

      """
    Then "app/main.agc" gets these diagnostics:
      | at      | severity | code                |
      | 1:1-1:1 | error    | CHECK-TYPE-MISMATCH |
    And the diagnostic of "app/main.agc" points into "app/lib.agc" at 2:10-2:13
