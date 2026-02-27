Feature: Path sanitization
  Scenario: Dotdot traversal is rejected
    Given a path "../../../etc/passwd"
    When I sanitize the path
    Then the result does not contain ".."

  Scenario: Null byte is stripped
    Given a path "hello\0world"
    When I sanitize the path
    Then the result does not contain a null byte

  Scenario: Normal path is unchanged
    Given a path "DCIM/Camera/photo.jpg"
    When I sanitize the path
    Then the result equals "DCIM/Camera/photo.jpg"
