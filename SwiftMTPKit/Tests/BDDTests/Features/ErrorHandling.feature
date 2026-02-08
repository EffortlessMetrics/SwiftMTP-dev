Feature: Device Error Handling
  As a user of SwiftMTP
  I want the library to handle errors gracefully
  So that my application can recover from failure conditions

  Background:
    Given a connected MTP device
    And the device has an active session

  Scenario: Device disconnects during transfer
    Given the device is connected
    When the device is disconnected unexpectedly
    Then I should receive a deviceDisconnected error
    And the session should be invalidated
    And cleanup should be performed

  Scenario: Permission denied for protected device
    Given a protected MTP device
    When I attempt to open the device
    Then I should receive a permissionDenied error
    And user should be prompted for access

  Scenario: Unsupported operation
    Given a device that does not support deleteObject
    When I attempt to delete an object
    Then I should receive a notSupported error with message

  Scenario: Transport timeout
    Given a slow device response
    When I make a request that exceeds timeout
    Then I should receive a transport timeout error
    And the operation should be retryable

  Scenario: Storage full condition
    Given a device with full storage
    When I attempt to send an object
    Then I should receive a storageFull error
    And available space should be reported

  Scenario: Object not found
    Given an object that was deleted
    When I attempt to get object info
    Then I should receive an objectNotFound error

  Scenario: Device is busy
    Given a device handling another operation
    When I attempt a new operation
    Then I should receive a busy error
    And retry suggestion should be provided

  Scenario: Device sends unexpected response
    Given a device that returns an unexpected response code
    When I parse the response
    Then I should receive a protocolError with code and message
    And the error should be logged for debugging

  Scenario: Timeout on slow device
    Given a device with high latency
    When I perform an operation
    Then timeout should be adjusted based on device profile
    And I should not receive premature timeout errors

  Scenario: Out of memory on device
    Given a device with limited memory
    When I attempt a large transfer
    Then I should receive a deviceMemoryError
    And I should retry with smaller chunks

  Scenario: Invalid USB packet handling
    Given corrupted USB packet data
    When I process the packet
    Then I should receive a checksumError
    And the packet should be discarded
    And a retry should be initiated

  Scenario Outline: Error handling across device types
    Given a <device_type> device is connected
    When an <error_condition> occurs
    Then the appropriate error should be returned
    And recovery should be attempted

    Examples:
      | device_type | error_condition         |
      | pixel7      | unexpected_response      |
      | pixel7      | timeout                 |
      | oneplus3t  | device_busy             |
      | mi-note2   | storage_full            |
      | mi-note2   | out_of_memory           |

  Scenario: Cascading error recovery
    Given an operation fails with error A
    And retry triggers another failure with error B
    When I handle the error chain
    Then the root cause should be identified
    And appropriate recovery should be attempted

  Scenario: Error rate limiting
    Given multiple rapid errors occur
    When error rate exceeds threshold
    Then backoff should be applied automatically
    And I should receive a rateLimited notification

  Scenario: Error logging and diagnostics
    Given an error occurs during operation
    When the error is handled
    Then detailed diagnostics should be logged
    And error context should be preserved for debugging
