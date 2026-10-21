Feature: Workspace symbols
  The editor searches the whole project for a name. The name must be written in full, as it is declared, and the
  files are read from disk, below the folder that the editor opened.

  Scenario Outline: a name is found in the files below the workspace folder, however the editor names the folder
    Given the editor offers the workspace as "<offered>"
    And the language server has started
    And the file "shapes.agc" contains:
      """
      export struct Point
        x: Int
        y: Int
      end

      export def area(point: Point) -> Int
        return point.x * point.y
      end
      """
    And the file "text/names.agc" contains:
      """
      LIMIT = 3

      export def area(name: String) -> Int
        return name.length * LIMIT
      end
      """
    When the editor searches the workspace for "area"
    Then the workspace symbols for "area" are:
      | symbol | kind     | file           | at        |
      | area   | Function | shapes.agc     | 6:12-6:16 |
      | area   | Function | text/names.agc | 3:12-3:16 |

    Examples:
      | offered           |
      | workspace folders |
      | root URI          |
      | root path         |

  Scenario: a struct, a field and a constant are found by their names
    Given the editor offers the workspace as "workspace folders"
    And the language server has started
    And the file "shapes.agc" contains:
      """
      LIMIT = 3

      export struct Point
        x: Int
        y: Int
      end
      """
    When the editor searches the workspace for "Point"
    And the editor searches the workspace for "Point.y"
    And the editor searches the workspace for "LIMIT"
    Then the workspace symbols for "Point" are:
      | symbol | kind   | file       | at        |
      | Point  | Struct | shapes.agc | 3:15-3:20 |
    And the workspace symbols for "Point.y" are:
      | symbol  | kind  | file       | at      |
      | Point.y | Field | shapes.agc | 5:3-5:4 |
    And the workspace symbols for "LIMIT" are:
      | symbol | kind     | file       | at      |
      | LIMIT  | Constant | shapes.agc | 1:1-1:6 |

  Scenario: a name that is not declared in full has no symbols
    Given the editor offers the workspace as "workspace folders"
    And the language server has started
    And the file "shapes.agc" contains:
      """
      export def area(side: Int) -> Int
        return side * side
      end
      """
    When the editor searches the workspace for "ar"
    And the editor searches the workspace for "Area"
    And the editor searches the workspace for "perimeter"
    And the editor searches the workspace for ""
    Then there are no workspace symbols for "ar"
    And there are no workspace symbols for "Area"
    And there are no workspace symbols for "perimeter"
    And there are no workspace symbols for ""

  Scenario: an editor without a workspace folder gets no symbols
    Given the language server has started
    And the file "shapes.agc" contains:
      """
      export def area(side: Int) -> Int
        return side * side
      end
      """
    When the editor searches the workspace for "area"
    Then there are no workspace symbols for "area"
    And the server never logs "cannot answer the request"

  Scenario: a file that cannot be read is left out and logged
    Given the editor offers the workspace as "workspace folders"
    And the language server has started with the arguments "--log-level debug"
    And the file "shapes.agc" contains:
      """
      export def area(side: Int) -> Int
        return side * side
      end
      """
    And the file "broken.agc" contains:
      """
      def double(n: Int -> Int
        return n * 2
      end
      """
    When the editor searches the workspace for "area"
    Then the workspace symbols for "area" are:
      | symbol | kind     | file       | at        |
      | area   | Function | shapes.agc | 1:12-1:16 |
    And the server logs a "debug" line containing "broken.agc"

  Scenario: a newer search supersedes the older ones, which are answered with null
    Given the editor offers the workspace as "workspace folders"
    And the language server has started with the arguments "--agentica specs/fixtures/lagging-agentica"
    And the file "shapes.agc" contains:
      """
      export def area(side: Int) -> Int
        return side * side
      end
      """
    When the editor searches the workspace for "area" three times in a row
    Then the earlier requests in a row are answered with null
    And the workspace symbols for "area" are:
      | symbol | kind     | file       | at        |
      | area   | Function | shapes.agc | 1:12-1:16 |

  Scenario: an agentica that cannot run leaves the symbols empty and warns
    Given the editor offers the workspace as "workspace folders"
    And the language server has started with the arguments "--agentica specs/fixtures/broken-agentica"
    And the file "shapes.agc" contains:
      """
      export def area(side: Int) -> Int
        return side * side
      end
      """
    When the editor searches the workspace for "area"
    Then the search for "area" is answered with null
    And the server warns "cannot answer the request for the workspace symbols"
