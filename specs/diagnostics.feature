Feature: Diagnostics in the editor
  On open and on save, the server checks the file on disk with
  `agentica check` and publishes its first diagnostic, or none. Positions are
  written as `agentica check` shows them: line:column, from 1, end exclusive.

  Scenario: a clean file publishes no diagnostics
    Given the language server has started
    And the file "ok.agc" contains:
      """
      def main() -> Void
        puts("hi")
      end

      """
    When the editor opens "ok.agc"
    Then "ok.agc" gets no diagnostics

  Scenario: a file with an error publishes its first diagnostic
    Given the language server has started
    And the file "unknown.agc" contains:
      """
      def main() -> Void
        puts(oops)
      end

      """
    When the editor opens "unknown.agc"
    Then "unknown.agc" gets these diagnostics:
      | at       | severity | code               |
      | 2:8-2:12 | error    | CHECK-UNKNOWN-NAME |

  Scenario: the help of a diagnostic follows its message
    Given the language server has started
    And the file "types.agc" contains:
      """
      def main() -> Void
        age: Int = "25"
      end

      """
    When the editor opens "types.agc"
    Then "types.agc" gets these diagnostics:
      | at        | severity | code                |
      | 2:14-2:18 | error    | CHECK-TYPE-MISMATCH |
    And the diagnostic of "types.agc" has a help line

  Scenario Outline: positions count in the encoding the editor asked for
    Given the language server has started with the position encodings "<offered>"
    And the file "emoji.agc" contains:
      """
      def main() -> Void
        names = ["😀", oops]
      end

      """
    When the editor opens "emoji.agc"
    Then "emoji.agc" gets these diagnostics:
      | at   | severity | code               |
      | <at> | error    | CHECK-UNKNOWN-NAME |

    Examples:
      | offered        | at        |
      | utf-16         | 2:18-2:22 |
      | utf-16, utf-32 | 2:17-2:21 |

  Scenario: saving a fixed file clears its diagnostic
    Given the language server has started
    And the file "draft.agc" contains:
      """
      def main() -> Void
        puts(oops)
      end

      """
    When the editor opens "draft.agc"
    And the editor saves "draft.agc" as:
      """
      def main() -> Void
        puts("fixed")
      end

      """
    Then "draft.agc" gets these diagnostics:
      | at       | severity | code               |
      | 2:8-2:12 | error    | CHECK-UNKNOWN-NAME |
    And "draft.agc" gets no diagnostics

  Scenario: closing a file clears its diagnostic
    Given the language server has started
    And the file "unknown.agc" contains:
      """
      def main() -> Void
        puts(oops)
      end

      """
    When the editor opens "unknown.agc"
    And the editor closes "unknown.agc"
    Then "unknown.agc" gets these diagnostics:
      | at       | severity | code               |
      | 2:8-2:12 | error    | CHECK-UNKNOWN-NAME |
    And "unknown.agc" gets no diagnostics

  Scenario: an error in an imported file is shown at the start of the opened file
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
    Then "app.agc" gets these diagnostics:
      | at      | severity | code                |
      | 1:1-1:1 | error    | CHECK-TYPE-MISMATCH |
    And the diagnostic of "app.agc" points to "lib.agc:2:10"

  Scenario: a file name with a space is decoded from its URI
    Given the language server has started
    And the file "my file.agc" contains:
      """
      def main() -> Void
        puts(oops)
      end

      """
    When the editor opens "my file.agc"
    Then "my file.agc" gets these diagnostics:
      | at       | severity | code               |
      | 2:8-2:12 | error    | CHECK-UNKNOWN-NAME |

  Scenario: a URI with the localhost authority names a local file
    Given the language server has started
    And the file "unknown.agc" contains:
      """
      def main() -> Void
        puts(oops)
      end

      """
    When the editor opens "unknown.agc" through a localhost URI
    Then "unknown.agc" through a localhost URI gets these diagnostics:
      | at       | severity | code               |
      | 2:8-2:12 | error    | CHECK-UNKNOWN-NAME |

  Scenario: other output of the checker before the diagnostic is skipped
    Given the language server has started with the arguments "--agentica specs/fixtures/noisy-agentica"
    And the file "unknown.agc" contains:
      """
      def main() -> Void
        puts(oops)
      end

      """
    When the editor opens "unknown.agc"
    Then "unknown.agc" gets these diagnostics:
      | at       | severity | code               |
      | 2:8-2:12 | error    | CHECK-UNKNOWN-NAME |

  Scenario: the checker named after --stdio is the one used
    Given the language server has started with the arguments "--stdio --agentica specs/fixtures/missing-agentica"
    And the file "unknown.agc" contains:
      """
      def main() -> Void
        puts(oops)
      end

      """
    When the editor opens "unknown.agc"
    Then "unknown.agc" gets no diagnostics

  Scenario: a file reached through a link and a double slash keeps its position
    Given the language server has started
    And the folder has the link "link" to itself
    And the file "unknown.agc" contains:
      """
      def main() -> Void
        puts(oops)
      end

      """
    When the editor opens "link//unknown.agc"
    Then "link//unknown.agc" gets these diagnostics:
      | at       | severity | code               |
      | 2:8-2:12 | error    | CHECK-UNKNOWN-NAME |

  Scenario: a file name with accents is decoded from its URI
    Given the language server has started
    And the file "café.agc" contains:
      """
      def main() -> Void
        puts(oops)
      end

      """
    When the editor opens "café.agc"
    Then "café.agc" gets these diagnostics:
      | at       | severity | code               |
      | 2:8-2:12 | error    | CHECK-UNKNOWN-NAME |

  Scenario: an error at a key of agentica.toml names the key
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
    Then "app.agc" gets these diagnostics:
      | at      | severity | code                 |
      | 1:1-1:1 | error    | PKG-MANIFEST-INVALID |
    And the diagnostic of "app.agc" points to "agentica.toml (package)"

  Scenario: a checker that hangs is stopped
    Given the language server has started with the arguments "--agentica specs/fixtures/hanging-agentica"
    And the file "unknown.agc" contains:
      """
      def main() -> Void
        puts(oops)
      end

      """
    When the editor opens "unknown.agc"
    Then "unknown.agc" gets no diagnostics
    And the server exits with code 0

  Scenario: a checker that fails without a diagnostic is reported
    Given the language server has started with the arguments "--agentica specs/fixtures/silent-agentica"
    And the file "unknown.agc" contains:
      """
      def main() -> Void
        puts(oops)
      end

      """
    When the editor opens "unknown.agc"
    Then "unknown.agc" gets no diagnostics
    And the server warns "agentica exited with status 1 and no diagnostic"

  Scenario: a checker that cannot run the check is reported
    Given the language server has started with the arguments "--agentica specs/fixtures/broken-agentica"
    And the file "unknown.agc" contains:
      """
      def main() -> Void
        puts(oops)
      end

      """
    When the editor opens "unknown.agc"
    Then "unknown.agc" gets no diagnostics
    And the server warns "agentica exited with status 2"

  Scenario: a buffer that is not a file is not checked
    Given the language server has started
    When the editor opens an untitled buffer
    Then no diagnostics are published

  Scenario: a file that is gone publishes no diagnostics
    Given the language server has started
    When the editor opens "missing.agc"
    Then "missing.agc" gets no diagnostics
    And the server exits with code 0
