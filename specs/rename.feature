Feature: Rename
  The editor renames a name with the declaration and the uses that `agentica refs` finds. The rename is refused when
  it could leave a use behind: a name that is not declared by the program, a program with errors elsewhere, and a
  public name that another file of the workspace writes.

  Scenario: a local variable is renamed at its declaration and at every use
    Given the language server has started
    When the editor opens "app.agc" with:
      """
      def main() -> Void
        count = 1
        puts(count + count)
      end

      """
    And the editor prepares the rename in "app.agc" at 3:10
    And the editor renames in "app.agc" at 2:3 to "total"
    Then the prepared rename at 3:10 covers 3:8-3:13 named "count"
    And the rename at 2:3 edits:
      | file    | at        | text  |
      | app.agc | 2:3-2:8   | total |
      | app.agc | 3:8-3:13  | total |
      | app.agc | 3:16-3:21 | total |

  Scenario: a parameter is renamed with its uses and the named arguments of its calls
    Given the language server has started
    When the editor opens "app.agc" with:
      """
      def greet(name: String, loud: Bool = false) -> String
        if loud
          return "HI #{name}"
        end

        return "hi #{name}"
      end

      def main() -> Void
        puts(greet("ana", loud: true))
      end

      """
    And the editor renames in "app.agc" at 1:25 to "shout"
    Then the rename at 1:25 edits:
      | file    | at          | text  |
      | app.agc | 1:25-1:29   | shout |
      | app.agc | 2:6-2:10    | shout |
      | app.agc | 10:21-10:25 | shout |

  Scenario: a function that no other file writes is renamed from a call
    Given the language server has started
    When the editor opens "app.agc" with:
      """
      def double(n: Int) -> Int
        return n * 2
      end

      def main() -> Void
        puts(double(4))
      end

      """
    And the editor renames in "app.agc" at 6:8 to "twice"
    Then the rename at 6:8 edits:
      | file    | at       | text  |
      | app.agc | 1:5-1:11 | twice |
      | app.agc | 6:8-6:14 | twice |

  Scenario: a field is renamed with its reads and the named arguments that build the struct
    Given the language server has started
    When the editor opens "app.agc" with:
      """
      struct User
        name: String
        email: String
      end

      def main() -> Void
        user = User(name: "ana", email: "a@b")
        puts(user.email)
      end

      """
    And the editor renames in "app.agc" at 3:3 to "mail"
    Then the rename at 3:3 edits:
      | file    | at        | text |
      | app.agc | 3:3-3:8   | mail |
      | app.agc | 7:28-7:33 | mail |
      | app.agc | 8:13-8:18 | mail |

  Scenario: a public function that another file imports is renamed in both files
    Given the editor offers the workspace as "workspace folders"
    And the language server has started
    And the file "lib.agc" contains:
      """
      def helper() -> Int = 1
      """
    When the editor opens "app.agc" with:
      """
      import Lib from "lib"

      def main() -> Void
        puts(Lib.helper())
      end

      """
    And the editor renames in "app.agc" at 4:12 to "assist"
    Then the rename at 4:12 edits:
      | file    | at        | text   |
      | lib.agc | 1:5-1:11  | assist |
      | app.agc | 4:12-4:18 | assist |

  Scenario: a public name that a third file of the workspace writes is not renamed
    Given the editor offers the workspace as "workspace folders"
    And the language server has started
    And the file "lib.agc" contains:
      """
      def helper() -> Int = 1
      """
    And the file "other.agc" contains:
      """
      import Lib from "lib"

      def main() -> Void
        puts(Lib.helper())
      end

      """
    When the editor opens "lib.agc"
    And the editor prepares the rename in "lib.agc" at 1:5
    And the editor renames in "lib.agc" at 1:5 to "assist"
    Then there is no prepared rename at 1:5
    And the rename at 1:5 is refused with "other.agc"

  Scenario: a program with an error in another function is not renamed
    Given the language server has started
    When the editor opens "app.agc" with:
      """
      def broken() -> Int
        return oops
      end

      def main() -> Void
        count = 1
        puts(count)
      end

      """
    And the editor prepares the rename in "app.agc" at 6:3
    And the editor renames in "app.agc" at 6:3 to "total"
    Then there is no prepared rename at 6:3
    And the rename at 6:3 is refused with "have errors"

  Scenario: a builtin and a keyword are not renamed
    Given the language server has started
    When the editor opens "app.agc" with:
      """
      def main() -> Void
        puts("hi")
      end

      """
    And the editor prepares the rename in "app.agc" at 2:4
    And the editor prepares the rename in "app.agc" at 1:2
    And the editor renames in "app.agc" at 2:4 to "show"
    Then there is no prepared rename at 2:4
    And there is no prepared rename at 1:2
    And the rename at 2:4 is refused with "builtin"

  Scenario Outline: a new name that agentica would not accept is refused
    Given the language server has started
    When the editor opens "app.agc" with:
      """
      def main() -> Void
        count = 1
        puts(count)
      end

      """
    And the editor renames in "app.agc" at 2:3 to "<name>"
    Then the rename at 2:3 is refused with "<reason>"

    Examples:
      | name  | reason            |
      | end   | not a name        |
      | 2go   | not a name        |
      | a b   | not a name        |
      | Count | lower case letter |
