Feature: Code actions
  A suggestion of agentica lint, such as LINT-BOOL-COMPARE, that has a plain
  fix is offered as a quick fix at its range. The linted text is the buffer,
  saved or not; a suggestion without a fix, and a line without suggestions,
  have no action.

  Scenario: a comparison with a Bool literal is replaced by the Bool
    Given the language server has started
    When the editor opens "app.agc" with:
      """
      def main() -> Void
        done = true
        if done == true
          puts("a")
        end

        if done != true
          puts("b")
        end

        if false == done
          puts("c")
        end
      end

      """
    And the editor asks for code actions in "app.agc" at 3:8-3:8
    And the editor asks for code actions in "app.agc" at 7:8-7:8
    And the editor asks for code actions in "app.agc" at 11:8-11:8
    Then the code actions at 3:8 are:
      | title                 | at       | text |
      | Use the Bool as it is | 3:6-3:18 | done |
    And the code actions at 7:8 are:
      | title                 | at       | text     |
      | Use the Bool as it is | 7:6-7:18 | not done |
    And the code actions at 11:8 are:
      | title                 | at         | text     |
      | Use the Bool as it is | 11:6-11:19 | not done |

  Scenario Outline: a text joined with + and to_s is replaced by an interpolated string, in the encoding of the editor
    Given the language server has started with the position encodings "<offered>"
    When the editor opens "app.agc" with:
      """
      def main() -> Void
        n = 3
        puts("😀" + n.to_s + "!")
      end

      """
    And the editor asks for code actions in "app.agc" at 3:10-3:10
    Then the code actions at 3:10 are:
      | title             | at      | text      |
      | Use interpolation | <range> | "😀#{n}!" |

    Examples:
      | offered        | range     |
      | utf-16         | 3:8-3:27  |
      | utf-16, utf-32 | 3:8-3:26  |

  Scenario: a suggestion without a plain fix and a line without suggestions have no code actions
    Given the language server has started
    When the editor opens "app.agc" with:
      """
      def main() -> Void
        done = true
        if not done
          puts("x")
        else
          puts("y")
        end

        puts(done)
      end

      """
    And the editor asks for code actions in "app.agc" at 3:6-3:6
    And the editor asks for code actions in "app.agc" at 9:4-9:4
    Then there are no code actions at 3:6
    And there are no code actions at 9:4
