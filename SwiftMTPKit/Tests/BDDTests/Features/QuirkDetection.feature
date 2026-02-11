Feature: Quirk Detection
  As a SwiftMTP developer
  I want the library to automatically detect device quirks
  So that transfers work correctly across different device types

  Background:
    Given SwiftMTP is initialized
    And the quirk database is available

  Scenario: Auto-detect device quirks from probe
    Given an MTP device with unknown quirks
    When I probe the device
    Then the system should analyze USB descriptors
    And query device capabilities
    And compare against known quirk patterns
    And apply matching quirks

  Scenario: Apply fallback tuning when quirks unknown
    Given a device with no matching quirks in database
    When I attempt to connect
    Then the system should apply conservative fallback settings
    And monitor for error patterns
    And suggest potential quirk profiles

  Scenario Outline: Quirk detection for known devices
    Given a <device_type> device is connected
    When I perform quirk detection
    Then the detected quirks should match the known profile
    And the tuning parameters should be applied

    Examples:
      | device_type |
      | pixel7      |
      | oneplus3t   |
      | mi-note2    |

  Scenario: Quirk fingerprint evolution over time
    Given a device has been used multiple times
    When error patterns are collected over time
    Then the quirk fingerprint should evolve
    And new quirks may be discovered
    And the device profile should be updated

  Scenario: Store learned quirks for device
    Given quirks are discovered for a device
    When the device is disconnected
    Then the learned quirks should be persisted
    And on reconnection, stored quirks should be loaded
    And applied without requiring fresh probe

  Scenario: Handle quirk database corruption
    Given the quirk database is corrupt
    When I attempt to load device quirks
    Then the system should detect corruption
    And fall back to conservative defaults
    And attempt database repair

  Scenario: Quirk validation on new device
    Given a new device variant of a known type
    When quirks are applied from parent profile
    Then the system should validate quirk compatibility
    And adjust any mismatched parameters

  Scenario: Multiple quirk profiles for same device
    Given a device that behaves differently under conditions
    When I switch operation modes
    Then appropriate quirk profiles should be selected
    And profile transitions should be seamless

  Scenario: Quirk override by user configuration
    Given a device with detected quirks
    And user-provided quirk overrides
    When the device is connected
    Then user overrides should take precedence
    And detected quirks should be used as fallback

  Scenario: Quirk conflict detection
    Given multiple quirk sources are available
    When conflicting quirks are detected
    Then the system should log a warning
    And apply the most conservative option
