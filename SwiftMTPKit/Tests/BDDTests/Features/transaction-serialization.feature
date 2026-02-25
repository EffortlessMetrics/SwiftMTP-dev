Feature: Transaction serialization
  As a developer using SwiftMTP
  I want concurrent device operations to be serialized
  So that protocol state is never corrupted by interleaved commands

  Background:
    Given a connected mock device
    And the device has an active session

  Scenario: Concurrent operations are serialized
    Given a device with active operations
    When two concurrent write operations are attempted
    Then they execute sequentially without overlap
