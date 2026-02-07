Feature: Device Connection
  As a user
  I want to connect to an MTP device
  So that I can transfer files

  Scenario: connecting to a valid device
    Given a connected MTP device
    When I request to open the device
    Then the session should be active
