Feature: Media players and e-readers connect via MTP
  As a user with a portable audio player, e-reader, or tablet
  I want to transfer files to and from my device
  So that I can manage my music, books, and podcasts

  Background:
    Given the quirk database is loaded

  Scenario: SanDisk Sansa m230 is recognised in the quirk database
    Given a USB device with vid 0x0781 and pid 0x7400
    Then the matched quirk id should be "sandisk-sansa-m230-7400"
    And supportsGetObjectPropList should be false
    And requiresKernelDetach should be false

  Scenario: Creative ZEN Micro is recognised in the quirk database
    Given a USB device with vid 0x041e and pid 0x411e
    Then the matched quirk id should be "creative-zen-micro-411e"
    And requiresKernelDetach should be false

  Scenario: iRiver iFP-880 is recognised in the quirk database
    Given a USB device with vid 0x4102 and pid 0x1008
    Then the matched quirk id should be "iriver-ifp-880-1008"
    And requiresKernelDetach should be false

  Scenario: Amazon Kindle Fire is recognised in the quirk database
    Given a USB device with vid 0x1949 and pid 0x0007
    Then the matched quirk id should be "amazon-kindle-fire-0007"
    And requiresKernelDetach should be false

  Scenario: Philips GoGear HDD6320 is recognised in the quirk database
    Given a USB device with vid 0x0471 and pid 0x014b
    Then the matched quirk id should be "philips-hdd6320-014b"
    And requiresKernelDetach should be false

  Scenario: Kobo Arc Android tablet is recognised in the quirk database
    Given a USB device with vid 0x2237 and pid 0xb108
    Then the matched quirk id should be "kobo-arc-android-b108"
    And requiresKernelDetach should be false
