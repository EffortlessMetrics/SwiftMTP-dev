Feature: Action cameras and drones connect via MTP
  As a user with an action camera or drone
  I want to transfer media files from my device
  So that I can manage my photos and videos

  Background:
    Given the quirk database is loaded

  Scenario: GoPro Hero original is recognised in the quirk database
    Given a USB device with vid 0x2672 and pid 0x000c
    Then the matched quirk id should be "gopro-hero-000c"
    And requiresKernelDetach should be false

  Scenario: GoPro Hero 5 Black is recognised in the quirk database
    Given a USB device with vid 0x2672 and pid 0x0027
    Then the matched quirk id should be "gopro-hero5-black-0027"
    And requiresKernelDetach should be false

  Scenario: GoPro Hero 9 Black is recognised in the quirk database
    Given a USB device with vid 0x2672 and pid 0x004d
    Then the matched quirk id should be "gopro-hero9-black-004d"
    And requiresKernelDetach should be false

  Scenario: GoPro Hero 13 Black is recognised in the quirk database
    Given a USB device with vid 0x2672 and pid 0x005d
    Then the matched quirk id should be "gopro-hero13-black-005d"
    And requiresKernelDetach should be false

  Scenario: DJI Osmo Action 3 drone camera is recognised in the quirk database
    Given a USB device with vid 0x2ca3 and pid 0x001f
    Then the matched quirk id should be "dji-osmo-action-3-001f"
    And requiresKernelDetach should be false

  Scenario: DJI Mini 3 Pro drone is recognised in the quirk database
    Given a USB device with vid 0x2ca3 and pid 0x001c
    Then the matched quirk id should be "dji-mini-3-pro-001c"
    And requiresKernelDetach should be false

  Scenario: DJI Mavic 3 Pro drone is recognised in the quirk database
    Given a USB device with vid 0x2ca3 and pid 0x0027
    Then the matched quirk id should be "dji-mavic-3-pro-0027"
    And requiresKernelDetach should be false

  Scenario: DJI Air 3 drone is recognised in the quirk database
    Given a USB device with vid 0x2ca3 and pid 0x0026
    Then the matched quirk id should be "dji-air-3-0026"
    And requiresKernelDetach should be false

  Scenario: Garmin VIRB Ultra 30 action camera is recognised in the quirk database
    Given a USB device with vid 0x091e and pid 0x2468
    Then the matched quirk id should be "garmin-virb-ultra30-2468"
    And requiresKernelDetach should be false

  Scenario: Garmin VIRB 360 action camera is recognised in the quirk database
    Given a USB device with vid 0x091e and pid 0x2469
    Then the matched quirk id should be "garmin-virb-360-2469"
    And requiresKernelDetach should be false

  Scenario: Garmin VIRB X action camera is recognised in the quirk database
    Given a USB device with vid 0x091e and pid 0x2466
    Then the matched quirk id should be "garmin-virb-x-2466"
    And requiresKernelDetach should be false

  Scenario: Insta360 One X2 camera is recognised in the quirk database
    Given a USB device with vid 0x2e1a and pid 0x000a
    Then the matched quirk id should be "insta360-one-x2-000a"
    And requiresKernelDetach should be false

  Scenario: Insta360 X3 camera is recognised in the quirk database
    Given a USB device with vid 0x2e1a and pid 0x000c
    Then the matched quirk id should be "insta360-x3-000c"
    And requiresKernelDetach should be false

  Scenario: Insta360 Ace Pro camera is recognised in the quirk database
    Given a USB device with vid 0x2e1a and pid 0x000f
    Then the matched quirk id should be "insta360-ace-pro-000f"
    And requiresKernelDetach should be false

  Scenario: SJCAM SJ10 Pro action camera is recognised in the quirk database
    Given a USB device with vid 0x1b3f and pid 0x0201
    Then the matched quirk id should be "sjcam-sj10-pro-0201"
    And requiresKernelDetach should be false

  Scenario: SJCAM C300 action camera is recognised in the quirk database
    Given a USB device with vid 0x1b3f and pid 0x0203
    Then the matched quirk id should be "sjcam-c300-0203"
    And requiresKernelDetach should be false

  Scenario: Akaso EK7000 action camera is recognised in the quirk database
    Given a USB device with vid 0x3538 and pid 0x0001
    Then the matched quirk id should be "akaso-ek7000-0001"
    And requiresKernelDetach should be false

  Scenario: Akaso Brave 7 action camera is recognised in the quirk database
    Given a USB device with vid 0x3538 and pid 0x0009
    Then the matched quirk id should be "akaso-brave-7-0009"
    And requiresKernelDetach should be false

  Scenario: Akaso Brave 8 action camera is recognised in the quirk database
    Given a USB device with vid 0x3538 and pid 0x0007
    Then the matched quirk id should be "akaso-brave-8-0007"
    And requiresKernelDetach should be false
