Feature: Device quirk policy application
  As a developer
  I want quirk policies to correctly configure device behaviour
  So that device-specific workarounds are applied automatically

  Scenario: Android device with broken proplist uses fallback
    Given a device matching an Android quirk with supportsGetObjectPropList=false
    When I connect and enumerate files
    Then the fallback GetObjectInfo path should be used
    And supportsGetObjectPropList in the resolved policy should be false

  Scenario: Camera device with PTP stack uses fast path
    Given a device matching a camera quirk with supportsGetObjectPropList=true
    When I connect and enumerate files
    Then supportsGetObjectPropList in the resolved policy should be true

  Scenario: Quirk timeout values are applied
    Given a device with a known quirk that has ioTimeoutMs=30000
    When the quirk policy is loaded
    Then the effective ioTimeoutMs should be 30000
