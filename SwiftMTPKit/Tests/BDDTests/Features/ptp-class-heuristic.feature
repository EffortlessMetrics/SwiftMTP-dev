Feature: PTP class-based heuristic for unrecognized cameras
  As a user connecting an unknown camera
  I want SwiftMTP to automatically use fast-path enumeration
  So that my camera works without needing a quirk entry

  Background:
    Given SwiftMTP is initialized
    And the quirk database is loaded

  Scenario: Unrecognized PTP camera gets fast-path enumeration
    Given a USB device with interface class 0x06 and no matching quirk entry
    When the device policy is resolved
    Then supportsGetObjectPropList should be true
    And requiresKernelDetach should be false
    And prefersPropListEnumeration should be true

  Scenario: Unrecognized Android device gets conservative defaults
    Given a USB device with interface class 0xFF and no matching quirk entry
    When the device policy is resolved
    Then supportsGetObjectPropList should be false

  Scenario: Unrecognized device with no class info gets conservative defaults
    Given a USB device with no interface class information and no matching quirk entry
    When the device policy is resolved
    Then supportsGetObjectPropList should be false

  Scenario Outline: Recognized device uses quirk database
    Given a USB device with vid <vid> and pid <pid>
    When the device policy is resolved
    Then the matched quirk id should be "<quirk_id>"
    And supportsGetObjectPropList should be <proplist>

    Examples:
      | vid    | pid    | quirk_id                   | proplist |
      | 0x04a9 | 0x3139 | canon-eos-rebel-3139       | false    |
      | 0x2a70 | 0xf003 | oneplus-3t-f003            | false    |
      | 0x2672 | 0x0056 | gopro-hero10-black-0056    | true     |
