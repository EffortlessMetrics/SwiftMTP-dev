Feature: Paged enumeration
  Scenario: Large directory returns first page of 500 items
    Given a virtual device with 1200 files in root storage
    When I enumerate items from the initial page
    Then I receive exactly 500 items
    And a next-page cursor is provided

  Scenario: Second page returns correct offset
    Given a virtual device with 1200 files in root storage
    When I enumerate items from page cursor at offset 500
    Then I receive exactly 500 items

  Scenario: Last page has no cursor
    Given a virtual device with 1200 files in root storage
    When I enumerate items from page cursor at offset 1000
    Then I receive exactly 200 items
    And no next-page cursor is provided
