Feature: Diagnostics in the editor
  On open, on change and on save, the server checks the text of the buffer as
  `agentica check` does and publishes its first diagnostic, or none. Positions
  are written as `agentica check` shows them: line:column, from 1, end
  exclusive. Checks run one at a time; the slow ones in these scenarios import
  a module of thousands of functions.
  These scenarios open files whose buffer is what is on disk; the ones where
  the buffer differs are in buffers.feature.

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
        names = ["<text>", oops]
      end

      """
    When the editor opens "emoji.agc"
    Then "emoji.agc" gets these diagnostics:
      | at   | severity | code               |
      | <at> | error    | CHECK-UNKNOWN-NAME |

    Examples:
      | text | offered        | at        |
      | 😀   | utf-16         | 2:18-2:22 |
      | 😀   | utf-16, utf-32 | 2:17-2:21 |
      | é👩‍💻 | utf-16         | 2:23-2:27 |
      | é👩‍💻 | utf-16, utf-32 | 2:21-2:25 |

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
    And the diagnostic of "app.agc" points into "lib.agc" at 2:10-2:13

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
    And the diagnostic of "app.agc" points into "agentica.toml" at 1:1-1:1

  Scenario: a buffer that is not a file is not checked
    Given the language server has started
    When the editor opens an untitled buffer
    Then no diagnostics are published

  Scenario: a file that is not Agentica is not checked
    Given the language server has started
    And the file "notes.txt" contains:
      """
      not a program

      """
    When the editor opens "notes.txt"
    Then no diagnostics are published

  Scenario: a check that is running does not delay the answer to shutdown
    Given the language server has started
    And the file "heavy.agc" is a module of 5000 functions
    And the file "unknown.agc" contains:
      """
      import Heavy from "heavy"

      def main() -> Void
        puts(oops)
      end

      """
    When the editor opens "unknown.agc" without waiting
    Then the server answers "shutdown" within 2000 milliseconds
    And the server exits with code 0

  Scenario: an older check that is still running is not published
    Given the language server has started
    And the file "heavy.agc" is a module of 5000 functions
    And the file "draft.agc" contains:
      """
      import Heavy from "heavy"

      def main() -> Void
        puts(oops)
      end

      """
    When the editor opens "draft.agc" without waiting
    And the editor waits 300 milliseconds
    And the editor saves "draft.agc" without waiting as:
      """
      import Heavy from "heavy"

      def main() -> Void
        puts("fixed")
      end

      """
    And the editor waits for diagnostics
    And the editor waits 1500 milliseconds
    Then "draft.agc" gets no diagnostics
    And "draft.agc" gets nothing more

  Scenario: closing a file while it is checked leaves its diagnostics empty
    Given the language server has started
    And the file "heavy.agc" is a module of 5000 functions
    And the file "draft.agc" contains:
      """
      import Heavy from "heavy"

      def main() -> Void
        puts(oops)
      end

      """
    When the editor opens "draft.agc" without waiting
    And the editor waits 300 milliseconds
    And the editor closes "draft.agc" without waiting
    And the editor waits for diagnostics
    And the editor waits 1500 milliseconds
    Then "draft.agc" gets no diagnostics
    And "draft.agc" gets nothing more

  Scenario: nothing is published after shutdown
    Given the language server has started
    And the file "heavy.agc" is a module of 5000 functions
    And the file "unknown.agc" contains:
      """
      import Heavy from "heavy"

      def main() -> Void
        puts(oops)
      end

      """
    When the editor opens "unknown.agc" without waiting
    And the editor waits 300 milliseconds
    And the editor sends the request "shutdown"
    And the editor waits 1500 milliseconds
    Then no diagnostics are published
    And the server exits with code 0

  Scenario: files opened together are all checked, one after the other
    Given the language server has started
    And the files "one.agc, two.agc, three.agc, four.agc, five.agc, six.agc" contain:
      """
      def main() -> Void
        puts(oops)
      end

      """
    When the editor opens the files "one.agc, two.agc, three.agc, four.agc, five.agc, six.agc" without waiting
    And the editor waits for the diagnostics of 6 files
    Then "one.agc" gets these diagnostics:
      | at       | severity | code               |
      | 2:8-2:12 | error    | CHECK-UNKNOWN-NAME |
    And "two.agc" gets these diagnostics:
      | at       | severity | code               |
      | 2:8-2:12 | error    | CHECK-UNKNOWN-NAME |
    And "three.agc" gets these diagnostics:
      | at       | severity | code               |
      | 2:8-2:12 | error    | CHECK-UNKNOWN-NAME |
    And "four.agc" gets these diagnostics:
      | at       | severity | code               |
      | 2:8-2:12 | error    | CHECK-UNKNOWN-NAME |
    And "five.agc" gets these diagnostics:
      | at       | severity | code               |
      | 2:8-2:12 | error    | CHECK-UNKNOWN-NAME |
    And "six.agc" gets these diagnostics:
      | at       | severity | code               |
      | 2:8-2:12 | error    | CHECK-UNKNOWN-NAME |

  Scenario: a file waiting for the running check is checked once, with its latest text
    Given the language server has started
    And the file "heavy.agc" is a module of 5000 functions
    And the file "slow.agc" contains:
      """
      import Heavy from "heavy"

      def main() -> Void
        puts(oops)
      end

      """
    And the file "quick.agc" contains:
      """
      def main() -> Void
        puts(oops)
      end

      """
    When the editor opens "slow.agc" without waiting
    And the editor opens "quick.agc" without waiting
    And the editor saves "quick.agc" without waiting as:
      """
      def main() -> Void
        puts("fixed")
      end

      """
    And the editor waits for the diagnostics of 2 files
    And the editor waits 1500 milliseconds
    Then "slow.agc" gets these diagnostics:
      | at       | severity | code               |
      | 4:8-4:12 | error    | CHECK-UNKNOWN-NAME |
    And "quick.agc" gets no diagnostics
    And "quick.agc" gets nothing more

  Scenario: the file being typed in is checked before the check that its typing cancelled
    Given the language server has started
    And the file "heavy.agc" is a module of 5000 functions
    And the file "slow.agc" contains:
      """
      import Heavy from "heavy"

      def main() -> Void
        puts(oops)
      end

      """
    And the file "quick.agc" contains:
      """
      def main() -> Void
        puts("fine")
      end

      """
    When the editor opens "quick.agc"
    And the editor opens "slow.agc" without waiting
    And the editor waits 300 milliseconds
    And the editor types in "quick.agc" without waiting:
      """
      def main() -> Void
        puts(typed)
      end

      """
    And the editor waits for the diagnostics of 2 files
    Then "quick.agc" gets no diagnostics
    And "quick.agc" gets these diagnostics:
      | at       | severity | code               |
      | 2:8-2:13 | error    | CHECK-UNKNOWN-NAME |
    And "slow.agc" gets these diagnostics:
      | at       | severity | code               |
      | 4:8-4:12 | error    | CHECK-UNKNOWN-NAME |
    And the diagnostics of "quick.agc" are published before those of "slow.agc"

  Scenario: a module without main that is fine publishes no diagnostics
    Given the language server has started
    And the file "helpers.agc" contains:
      """
      export def double(n: Int) -> Int
        return n * 2
      end

      """
    When the editor opens "helpers.agc"
    Then "helpers.agc" gets no diagnostics

  Scenario: a type error in a module without main is shown at its place
    Given the language server has started
    And the file "helpers.agc" contains:
      """
      export def double(n: Int) -> Int
        return "x"
      end
      """
    When the editor opens "helpers.agc"
    Then "helpers.agc" gets these diagnostics:
      | at        | severity | code                |
      | 2:10-2:13 | error    | CHECK-TYPE-MISMATCH |

  Scenario: a main with the wrong signature is still reported
    Given the language server has started
    And the file "wrong.agc" contains:
      """
      def main(name: String) -> Void
        puts(name)
      end

      """
    When the editor opens "wrong.agc"
    Then "wrong.agc" gets these diagnostics:
      | at      | severity | code       |
      | 1:1-4:1 | error    | CHECK-MAIN |
