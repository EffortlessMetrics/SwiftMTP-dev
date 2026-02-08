Feature: Device Error Handling
  As a user of SwiftMTP
  I want the library to handle errors gracefully
  So that my application can recover from failure conditions

  Background:
    Given a connected MTP device

  Scenario: Device disconnects during transfer
    Given the device is connected
    When the device is disconnected unexpectedly
    Then I should receive a deviceDisconnected error

  Scenario: Permission denied for protected device
    Given a protected MTP device
    When I attempt to open the device
    Then I should receive a permissionDenied error

  Scenario: Unsupported operation
    Given a device that does not support deleteObject
    When I attempt to delete an object
    Then I should receive a notSupported error with message

  Scenario: Transport timeout
    Given a slow device response
    When I make a request that exceeds timeout
    Then I should receive a transport timeout error

  Scenario: Storage full condition
    Given a device with full storage
    When I attempt to send an object
    Then I should receive a storageFull error

  Scenario: Object not found
    Given an object that was deleted
    When I attempt to get object info
    Then I should receive an objectNotFound error

  Scenario: Device is busy
    Given a device handling another operation
    When I attempt a new operation
    Then I should receive a busy error

  Scenario: Protocol error handling
    Given a device that returns an unexpected response
    When I parse the response
    Then I should receive a protocolError with code and message
