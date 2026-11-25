Feature: Completion
  After a dot or at the start of a word, the editor offers the builtins of
  Agentica and the names of the program: its declarations, the names that its
  imports bring in, the parameters and variables of the function the cursor is
  in, the methods of a value, the fields of a struct, the variants of an enum
  and the names of an imported module. In the path of an import it offers the
  std modules and the files of the project. The buffer need not parse: the
  line being typed is cut at the cursor to ask the compiler.

  Scenario: after a namespace and a dot the functions of that namespace are offered
    Given the language server has loaded the builtin catalog
    When the editor opens "app.agc" with:
      """
      def main() -> Void
        words = String.sp
        String.
        names = ["😀", String.up]
      end

      """
    And the editor asks for completion in "app.agc" at 2:20
    And the editor asks for completion in "app.agc" at 3:10
    And the editor asks for completion in "app.agc" at 4:27
    Then the completion at 2:20 offers:
      | label | kind     | builtin      |
      | split | Function | String.split |
    And the completion at 2:20 does not offer "upcase"
    And the completion item "split" at 2:20 replaces 2:18-2:20
    And the completion at 3:10 offers:
      | label  | kind     | builtin       |
      | split  | Function | String.split  |
      | upcase | Function | String.upcase |
    And the completion at 3:10 does not offer "puts"
    And the completion at 4:27 offers:
      | label  | kind     | builtin       |
      | upcase | Function | String.upcase |
    And the completion item "upcase" at 4:27 replaces 4:25-4:27

  Scenario: at the start of a word namespaces and bare functions are offered
    Given the language server has loaded the builtin catalog
    When the editor opens "app.agc" with:
      """
      def main() -> Void
        pu
        Str
      end

      """
    And the editor asks for completion in "app.agc" at 2:5
    And the editor asks for completion in "app.agc" at 3:6
    Then the completion at 2:5 offers:
      | label | kind     | builtin |
      | puts  | Function | puts    |
    And the completion at 2:5 does not offer "String"
    And the completion item "puts" at 2:5 replaces 2:3-2:5
    And the completion at 3:6 offers:
      | label  | kind   | builtin |
      | String | Module |         |
    And the completion at 3:6 does not offer "puts"

  Scenario: Math, a module of Agentica 0.23.0, is offered with its functions
    Given the language server has loaded the builtin catalog
    When the editor opens "app.agc" with:
      """
      def main() -> Void
        root = Math.sq
        Mat
      end

      """
    And the editor asks for completion in "app.agc" at 2:17
    And the editor asks for completion in "app.agc" at 3:6
    Then the completion at 2:17 offers:
      | label | kind     | builtin   |
      | sqrt  | Function | Math.sqrt |
    And the completion item "sqrt" at 2:17 replaces 2:15-2:17
    And the completion at 3:6 offers:
      | label | kind   | builtin |
      | Math  | Module |         |

  Scenario: OpenSSL.Digest, a family of Agentica 0.27.0, has its members offered after OpenSSL. and after OpenSSL.Digest.
    Given the language server has loaded the builtin catalog
    When the editor opens "app.agc" with:
      """
      def main() -> Void
        a = OpenSSL.Dig
        b = OpenSSL.Digest.sha25
      end

      """
    And the editor asks for completion in "app.agc" at 2:17
    And the editor asks for completion in "app.agc" at 3:26
    Then the completion at 2:17 offers:
      | label         | kind     | builtin               |
      | Digest.sha256 | Function | OpenSSL.Digest.sha256 |
    And the completion at 3:26 offers:
      | label  | kind     | builtin               |
      | sha256 | Function | OpenSSL.Digest.sha256 |

  Scenario: nothing is offered in a comment, in a string or after a question mark
    Given the language server has loaded the builtin catalog
    When the editor opens "app.agc" with:
      """
      def main() -> Void
        # String.
        t = "Str"
        e = IO.eof?
      end

      """
    And the editor asks for completion in "app.agc" at 2:12
    And the editor asks for completion in "app.agc" at 3:11
    And the editor asks for completion in "app.agc" at 4:14
    Then the completion at 2:12 offers nothing
    And the completion at 3:11 offers nothing
    And the completion at 4:14 offers nothing

  Scenario: a position past the end of the line offers what the end of the line offers
    Given the language server has loaded the builtin catalog with the position encodings "utf-16, utf-32"
    When the editor opens "app.agc" with:
      """
      def main() -> Void
        pu
      end

      """
    And the editor asks for completion in "app.agc" at 2:40
    And the editor asks for completion in "app.agc" at 2:5
    Then the completion at 2:40 offers:
      | label | kind     | builtin |
      | puts  | Function | puts    |
    And the completion item "puts" at 2:40 replaces 2:3-2:5
    And the completion at 2:5 offers:
      | label | kind     | builtin |
      | puts  | Function | puts    |

  Scenario: a Windows line ending is not part of the line
    Given the language server has loaded the builtin catalog
    When the editor opens "app.agc" with Windows line endings:
      """
      def main() -> Void
        pu
      end

      """
    And the editor asks for completion in "app.agc" at 2:40
    Then the completion at 2:40 offers:
      | label | kind     | builtin |
      | puts  | Function | puts    |
    And the completion item "puts" at 2:40 replaces 2:3-2:5

  Scenario: a document that was never opened offers nothing
    Given the language server has loaded the builtin catalog
    When the editor asks for completion in "ghost.agc" at 1:1
    Then the completion at 1:1 offers nothing

  Scenario: the names of the function, the declarations and the imports are offered at the start of a word
    Given the language server has loaded the builtin catalog
    And the file "lib.agc" contains:
      """
      def area(w: Int, h: Int) -> Int = w * h
      """
    When the editor opens "app.agc" with:
      """
      import {area} from "lib"
      import Lib from "lib"

      struct Point
        x: Int
        y: Int
      end

      def total(items: List[Int]) -> Int
        count = 0
        for item in items
          count = count + item
        end

        cou
        ite
        Po
        ar
        Li
        return count
      end

      """
    And the editor asks for completion in "app.agc" at 15:6
    And the editor asks for completion in "app.agc" at 16:6
    And the editor asks for completion in "app.agc" at 17:5
    And the editor asks for completion in "app.agc" at 18:5
    And the editor asks for completion in "app.agc" at 19:5
    Then the completion at 15:6 offers:
      | label | kind     | builtin |
      | count | Variable |         |
    And the completion at 15:6 does not offer "items"
    And the completion at 16:6 offers:
      | label | kind     | builtin |
      | items | Variable |         |
      | item  | Variable |         |
    And the completion at 17:5 offers:
      | label | kind   | builtin |
      | Point | Struct |         |
    And the completion at 18:5 offers:
      | label | kind     | builtin |
      | area  | Function |         |
    And the completion at 19:5 offers:
      | label | kind   | builtin |
      | Lib   | Module |         |

  Scenario: after a dot the methods of the type, the fields of a struct, the variants of an enum and the exports of a module are offered
    Given the language server has loaded the builtin catalog
    And the file "lib.agc" contains:
      """
      def area(w: Int, h: Int) -> Int = w * h

      private

      def hidden() -> Int = 1
      """
    When the editor opens "app.agc" with:
      """
      import Lib from "lib"

      struct Point
        x: Int
        y: Int
      end

      enum Color
        Red
        Green(Int)
      end

      def main() -> Void
        xs = [1, 2]
        p = Point(x: 1, y: 2)
        puts(xs.size())
        puts(p.x)
        puts(Color.Red)
        puts(Lib.area(1, 2))
      end

      """
    And the editor asks for completion in "app.agc" at 16:11
    And the editor asks for completion in "app.agc" at 17:10
    And the editor asks for completion in "app.agc" at 18:14
    And the editor asks for completion in "app.agc" at 19:12
    Then the completion at 16:11 offers:
      | label | kind   | builtin |
      | map   | Method |         |
      | size  | Method |         |
    And the completion at 17:10 offers:
      | label | kind  | builtin |
      | x     | Field |         |
      | y     | Field |         |
    And the completion at 17:10 does not offer "map"
    And the completion at 18:14 offers:
      | label | kind       | builtin |
      | Red   | EnumMember |         |
      | Green | EnumMember |         |
    And the completion at 19:12 offers:
      | label | kind     | builtin |
      | area  | Function |         |
    And the completion at 19:12 does not offer "hidden"

  Scenario: after &. the members of the type inside the Optional are offered
    Given the language server has loaded the builtin catalog
    When the editor opens "app.agc" with:
      """
      struct Home
        city: String
        zip: Int
      end

      struct User
        address: Optional[Home]
      end

      def main() -> Void
        user = some(User(address: none))
        puts(user&.address&.city)
      end

      """
    And the editor asks for completion in "app.agc" at 12:14
    And the editor asks for completion in "app.agc" at 12:23
    Then the completion at 12:14 offers:
      | label   | kind  | builtin |
      | address | Field |         |
    And the completion at 12:14 does not offer "unwrap_or"
    And the completion at 12:23 offers:
      | label | kind  | builtin |
      | city  | Field |         |
      | zip   | Field |         |
    And the completion at 12:23 does not offer "address"

  Scenario: after &. on a line that does not parse yet the members of the type inside the Optional are offered
    Given the language server has loaded the builtin catalog
    When the editor opens "app.agc" with:
      """
      struct Home
        city: String
        zip: Int
      end

      struct User
        address: Optional[Home]
      end

      def main() -> Void
        user = some(User(address: none))
        town = user&.
      end

      """
    And the editor asks for completion in "app.agc" at 12:16
    Then the completion at 12:16 offers:
      | label   | kind  | builtin |
      | address | Field |         |

  Scenario: after &. the members follow a call and a chain through a field that is not an Optional
    Given the language server has loaded the builtin catalog
    When the editor opens "app.agc" with:
      """
      struct User
        name: String
      end

      def main() -> Void
        u = User(name: "a")
        maybe = some(u)
        puts(some(u)&.name)
        puts(maybe&.name&.size)
      end

      """
    And the editor asks for completion in "app.agc" at 8:17
    And the editor asks for completion in "app.agc" at 9:21
    Then the completion at 8:17 offers:
      | label | kind  | builtin |
      | name  | Field |         |
    And the completion at 9:21 offers:
      | label  | kind   | builtin |
      | upcase | Method |         |
    And the completion at 9:21 does not offer "name"

  Scenario: after &. a value that is not an Optional, a type and a module offer nothing
    Given the language server has loaded the builtin catalog
    When the editor opens "app.agc" with:
      """
      struct User
        name: String
      end

      def main() -> Void
        u = User(name: "a")
        maybe = some(u)
        puts(u&.name)
        puts(User&.name)
        puts(Math&.pi)
      end

      """
    And the editor asks for completion in "app.agc" at 8:11
    And the editor asks for completion in "app.agc" at 9:14
    And the editor asks for completion in "app.agc" at 10:14
    Then the completion at 8:11 offers nothing
    And the completion at 9:14 offers nothing
    And the completion at 10:14 offers nothing

  Scenario: a line that does not parse is cut at the cursor, also after a call
    Given the language server has loaded the builtin catalog
    When the editor opens "app.agc" with:
      """
      def main() -> Void
        xs = [1, 2]
        puts(xs.map(->(n) { n }).
      end

      """
    And the editor asks for completion in "app.agc" at 3:28
    Then the completion at 3:28 offers:
      | label | kind   | builtin |
      | size  | Method |         |

  Scenario: the fields of a struct are offered on a line that does not parse yet
    Given the language server has loaded the builtin catalog
    When the editor opens "app.agc" with:
      """
      struct Point
        x: Int
        y: Int
      end

      def main() -> Void
        p = Point(x: 1, y: 2)
        z = p.
      end

      """
    And the editor asks for completion in "app.agc" at 8:9
    Then the completion at 8:9 offers:
      | label | kind  | builtin |
      | x     | Field |         |
      | y     | Field |         |

  Scenario: the methods follow the type of a variable that has no other use
    Given the language server has loaded the builtin catalog
    When the editor opens "app.agc" with:
      """
      def main() -> Void
        name = "a"
        name.
      end

      """
    And the editor asks for completion in "app.agc" at 3:8
    Then the completion at 3:8 offers:
      | label  | kind   | builtin |
      | upcase | Method |         |
    And the completion at 3:8 does not offer "size"

  Scenario: an import offers the exports of its module, the std modules and the files and folders of the project
    Given the language server has loaded the builtin catalog
    And the files "lib.agc, geo/shapes.agc" contain:
      """
      def area(w: Int, h: Int) -> Int = w * h

      private

      def hidden() -> Int = 1
      """
    When the editor opens "app.agc" with:
      """
      import {ar} from "lib"
      import Queue from "std/qu"
      import Third from "l"
      import Fourth from "g"
      """
    And the editor asks for completion in "app.agc" at 1:11
    And the editor asks for completion in "app.agc" at 2:26
    And the editor asks for completion in "app.agc" at 3:21
    And the editor asks for completion in "app.agc" at 4:22
    Then the completion at 1:11 offers:
      | label | kind     | builtin |
      | area  | Function |         |
    And the completion at 1:11 does not offer "hidden"
    And the completion at 1:11 does not offer "puts"
    And the completion at 2:26 offers:
      | label     | kind   | builtin |
      | std/queue | Module |         |
    And the completion at 2:26 does not offer "std/http"
    And the completion at 3:21 offers:
      | label | kind | builtin |
      | lib   | File |         |
    And the completion at 3:21 does not offer "app"
    And the completion at 4:22 offers:
      | label | kind   | builtin |
      | geo/  | Folder |         |

  Scenario: the path of an import names nothing outside the workspace
    Given the language server has loaded the builtin catalog
    And the editor offers the workspace as "workspace folders"
    And the file "geo/lib.agc" contains:
      """
      def area(w: Int, h: Int) -> Int = w * h
      """
    When the editor opens "app.agc" with:
      """
      import Down from "g"
      import Up from "../"
      import Out from "geo/../../"
      """
    And the editor asks for completion in "app.agc" at 1:20
    And the editor asks for completion in "app.agc" at 2:20
    And the editor asks for completion in "app.agc" at 3:28
    Then the completion at 1:20 offers:
      | label | kind   | builtin |
      | geo/  | Folder |         |
    And the completion at 2:20 offers nothing
    And the completion at 3:28 offers nothing
