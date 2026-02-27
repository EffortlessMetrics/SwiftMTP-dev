Feature: Transport stall recovery
  As a developer using SwiftMTP
  I want USB stalls to be recovered automatically
  So that transient pipe errors don't abort transfers

  Background:
    Given a connected mock device
    And the device has an active session

  Scenario: USB stall is recovered automatically
    Given a mock transport that reports a USB stall
    When a bulk transfer is attempted
    Then the stall is cleared and transfer succeeds
