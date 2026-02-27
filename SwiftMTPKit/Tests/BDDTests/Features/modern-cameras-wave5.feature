Feature: Modern cameras from wave-4 and wave-5 connect via PTP
  As a photographer with a modern mirrorless or DSLR camera
  I want to transfer photos to my Mac without special configuration
  So that I can start editing immediately

  Background:
    Given the quirk database is loaded

  Scenario: Fujifilm X-T10 is recognised as a PTP camera
    Given a USB device with vid 0x04cb and pid 0x02c8
    Then the matched quirk id should be "fujifilm-xt10-02c8"
    And supportsGetObjectPropList should be true
    And requiresKernelDetach should be false

  Scenario: GoPro Hero 11 Black connects via PTP
    Given a USB device with vid 0x2672 and pid 0x0059
    Then the matched quirk id should be "gopro-hero11-black-0059"
    And supportsGetObjectPropList should be true
    And requiresKernelDetach should be false

  Scenario: GoPro Hero 12 Black connects via PTP
    Given a USB device with vid 0x2672 and pid 0x005c
    Then the matched quirk id should be "gopro-hero12-black-005c"
    And supportsGetObjectPropList should be true

  Scenario: Canon EOS 70D is recognised in the database
    Given a USB device with vid 0x04a9 and pid 0x3253
    Then the matched quirk id should be "canon-eos-70d-3253"
    And supportsGetObjectPropList should be true
    And requiresKernelDetach should be false

  Scenario: Garmin Fenix 6 Pro connects as MTP wearable
    Given a USB device with vid 0x091e and pid 0x4cda
    Then the matched quirk id should be "garmin-fenix6-pro-4cda"
    And requiresKernelDetach should be false
