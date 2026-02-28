Feature: Android TV and streaming devices connect via MTP
  As a user with a streaming device or set-top box
  I want to transfer files to and from my device
  So that I can sideload apps and manage media

  Background:
    Given the quirk database is loaded

  Scenario: Nvidia Shield TV Pro matches quirk profile
    Given a USB device with vid 0x0955 and pid 0xb42a
    Then the matched quirk id should be "nvidia-shield-android-tv-pro-mtp-b42a"
    And requiresKernelDetach should be true

  Scenario: Nvidia Shield MTP mode matches quirk profile
    Given a USB device with vid 0x0955 and pid 0xb401
    Then the matched quirk id should be "nvidia-shield-mtp-b401"
    And requiresKernelDetach should be true

  Scenario: Nvidia Shield MTP+ADB mode matches quirk profile
    Given a USB device with vid 0x0955 and pid 0xb400
    Then the matched quirk id should be "nvidia-shield-mtpadb-b400"
    And requiresKernelDetach should be true

  Scenario: Amazon Fire TV Stick 1st Gen matches quirk profile
    Given a USB device with vid 0x1949 and pid 0x02a1
    Then the matched quirk id should be "amazon-fire-tv-stick-1gen-02a1"
    And requiresKernelDetach should be false

  Scenario: Amazon Fire TV Stick 2nd Gen matches quirk profile
    Given a USB device with vid 0x1949 and pid 0x0311
    Then the matched quirk id should be "amazon-fire-tv-stick-2gen-0311"
    And requiresKernelDetach should be false

  Scenario: Amazon Fire TV Stick 4K matches quirk profile
    Given a USB device with vid 0x1949 and pid 0x0441
    Then the matched quirk id should be "amazon-fire-tv-stick-4k-0441"
    And requiresKernelDetach should be false

  Scenario: Amazon Fire TV Stick 4K Max matches quirk profile
    Given a USB device with vid 0x1949 and pid 0x0461
    Then the matched quirk id should be "amazon-fire-tv-stick-4kmax-0461"
    And requiresKernelDetach should be false

  Scenario: Amazon Fire TV Cube 2nd Gen matches quirk profile
    Given a USB device with vid 0x1949 and pid 0x0381
    Then the matched quirk id should be "amazon-fire-tv-cube-2gen-0381"
    And requiresKernelDetach should be false

  Scenario: Amazon Fire TV Cube 3rd Gen matches quirk profile
    Given a USB device with vid 0x1949 and pid 0x0741
    Then the matched quirk id should be "amazon-fire-tv-cube-3gen-0741"
    And requiresKernelDetach should be false

  Scenario: Xiaomi Mi Box S matches quirk profile
    Given a USB device with vid 0x2717 and pid 0x5001
    Then the matched quirk id should be "xiaomi-mi-box-s-5001"
    And requiresKernelDetach should be false

  Scenario: Xiaomi Mi Box 4 matches quirk profile
    Given a USB device with vid 0x2717 and pid 0x5002
    Then the matched quirk id should be "xiaomi-mi-box-4-5002"
    And requiresKernelDetach should be false
