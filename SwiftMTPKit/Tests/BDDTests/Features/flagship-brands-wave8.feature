Feature: Flagship Android brand quirk matching (wave-8)
  Covers Google Pixel, OnePlus, ASUS ROG, and Nothing Phone.
  All use iface class 0xff (Android MTP) with requiresKernelDetach.

  Background:
    Given the quirk database is loaded

  Scenario: Google Pixel 8 is matched with standard Android quirks
    Given a device with VID 0x18d1 PID 0x4ef7 and iface class 0xff
    When I look up quirks for this device
    Then a quirk entry is returned
    And requiresKernelDetach is true
    And ioTimeoutMs is at least 15000

  Scenario: Google Pixel Fold is matched
    Given a device with VID 0x18d1 PID 0x4efe and iface class 0xff
    When I look up quirks for this device
    Then a quirk entry is returned
    And requiresKernelDetach is true

  Scenario: OnePlus 12 is matched with Android quirks
    Given a device with VID 0x2a70 PID 0xf014 and iface class 0xff
    When I look up quirks for this device
    Then a quirk entry is returned
    And requiresKernelDetach is true
    And ioTimeoutMs is at least 15000

  Scenario: OnePlus Nord 3 is matched
    Given a device with VID 0x2a70 PID 0xf019 and iface class 0xff
    When I look up quirks for this device
    Then a quirk entry is returned

  Scenario: ASUS ROG Phone 6 is matched
    Given a device with VID 0x0b05 PID 0x4dba and iface class 0xff
    When I look up quirks for this device
    Then a quirk entry is returned
    And requiresKernelDetach is true

  Scenario: ASUS ZenFone 10 is matched
    Given a device with VID 0x0b05 PID 0x4dbb and iface class 0xff
    When I look up quirks for this device
    Then a quirk entry is returned

  Scenario: Nothing Phone 2 is matched with Android quirks
    Given a device with VID 0x2b0e PID 0x0002 and iface class 0xff
    When I look up quirks for this device
    Then a quirk entry is returned
    And requiresKernelDetach is true

  Scenario: Motorola Razr 40 Ultra is matched
    Given a device with VID 0x22b8 PID 0x2e92 and iface class 0xff
    When I look up quirks for this device
    Then a quirk entry is returned
    And requiresKernelDetach is true

  Scenario: Google Pixel 9 Pro Fold is matched
    Given a device with VID 0x18d1 PID 0x4efd and iface class 0xff
    When I look up quirks for this device
    Then a quirk entry is returned

  Scenario: OnePlus Open (foldable) is matched
    Given a device with VID 0x2a70 PID 0xf01a and iface class 0xff
    When I look up quirks for this device
    Then a quirk entry is returned
