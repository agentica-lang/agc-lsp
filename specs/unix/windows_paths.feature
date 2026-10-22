Feature: Paths of a Windows drive
  A Windows editor names a folder as `C:\proj` and a file as `file:///c%3A/proj/a.agc`, with either case for the drive
  letter. The server reads them all as the path `c:/proj/a.agc`. These scenarios put a folder called `c:` inside the
  folder of the project, which only Linux and macOS allow; the Windows CI reaches the same code with the drive of the
  real folder of every scenario.

  Scenario: a workspace folder with a drive letter and backslashes is searched, also in a file open as C:
    Given the editor offers the workspace as "root path of a Windows drive"
    And the language server has started in the folder of the project
    And the file "c:/proj/shapes.agc" contains:
      """
      export def area(side: Int) -> Int
        return side * side
      end
      """
    When the editor opens "C:/proj/fresh.agc" with:
      """
      export def area(width: Int) -> Int
        return width
      end
      """
    And the editor searches the workspace for "area"
    Then the workspace symbols for "area" are:
      | symbol | kind     | file                       | at        |
      | area   | Function | file:///c:/proj/fresh.agc  | 1:12-1:16 |
      | area   | Function | file:///c:/proj/shapes.agc | 1:12-1:16 |

  Scenario: a file named by the URI of VS Code is the same file as under the lower case letter
    Given the editor offers the workspace as "root path of a Windows drive"
    And the language server has started in the folder of the project
    And the file "c:/proj/shapes.agc" contains:
      """
      export def area(side: Int) -> Int
        return side * side
      end
      """
    When the editor opens the URI "file:///C%3A/proj/fresh.agc" with:
      """
      export def area(width: Int) -> Int
        return width
      end
      """
    And the editor searches the workspace for "area"
    Then the workspace symbols for "area" are:
      | symbol | kind     | file                       | at        |
      | area   | Function | file:///c:/proj/fresh.agc  | 1:12-1:16 |
      | area   | Function | file:///c:/proj/shapes.agc | 1:12-1:16 |
