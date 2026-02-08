Feature: Device Connection
  As a user of SwiftMTP
  I want to discover and connect to MTP devices
  So that I can perform file operations

  Background:
    Given SwiftMTP library is initialized

  Scenario: Discover MTP device when plugged in
    Given no devices are currently connected
    When I plug in an MTP device
    Then the device should be discovered
    And I should receive a device attached notification
    And the device should be accessible for connection

  Scenario: Auto-reconnect after USB disconnect
    Given a device is connected and in use
    When the USB connection is lost temporarily
    And the device is reconnected within timeout period
    Then the session should be automatically restored
    And all pending operations should resume

  Scenario: Handle device in use by another process
    Given a device is opened by another process
    When I attempt to connect to the device
    Then I should receive a device busy error
    And the system should retry according to backoff strategy

  Scenario: Multiple simultaneous device connections
    Given multiple MTP devices are available
    When I connect to multiple devices
    Then each device should have an independent session
    And operations on one device should not affect others

  Scenario: Device timeout handling
    Given a device that stops responding
    When the timeout threshold is reached
    Then the session should be terminated
    And I should receive a timeout error

  Scenario: USB descriptor parsing
    Given a connected MTP device
    When I parse the USB descriptors
    Then the device vendor and product IDs should be extracted
    And the supported USB endpoints should be identified
    And the device class information should be recorded

  Scenario Outline: Connection behavior across device types
    Given a <device_type> device is connected via USB
    When I attempt to open a session
    Then the session should open successfully
    And the device should respond within <timeout>ms

    Examples:
      | device_type | timeout |
      | pixel7      | 500     |
      | oneplus3t   | 1000    |
      | mi-note2    | 1500    |

  Scenario: Device removal notification
    Given a device is connected
    When the device is safely unplugged
    Then I should receive a device removed notification
    And all open sessions should be invalidated
    And resources should be cleaned up

  Scenario: Invalid device rejection
    Given a non-MTP USB device is connected
    When I attempt to connect as MTP device
    Then the connection should be rejected
    And I should receive an unsupported device error

  Scenario: Session concurrency limits
    Given maximum concurrent sessions is configured
    When I exceed the maximum connections
    Then new connections should be queued
    Or rejected with appropriate error

  Scenario: Device hibernation handling
    Given a connected device enters hibernation
    When I attempt an operation
    Then the device should wake up
    Or a hibernation error should be returned

  Scenario: Hotplug detection
    Given USB hotplug monitoring is active
    When I plug in and unplug devices rapidly
    Then each event should be detected
    And no events should be missed
