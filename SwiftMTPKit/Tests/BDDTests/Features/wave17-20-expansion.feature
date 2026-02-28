Feature: Wave 17-20 expansion: Android TV, regional phones, rugged phones, and libgphoto2 cameras

  Scenario: Nvidia Shield Android TV Pro matches quirk profile
    Given the quirks database is loaded
    When I look up VID 0x0955 PID 0xb42a
    Then a quirk profile should be found
    And the profile should have requiresKernelDetach enabled

  Scenario: Amazon Fire TV Stick 4K matches quirk profile
    Given the quirks database is loaded
    When I look up VID 0x1949 PID 0x0441
    Then a quirk profile should be found
    And the profile should have cameraClass disabled

  Scenario: Lava Z1 regional phone matches quirk profile
    Given the quirks database is loaded
    When I look up VID 0x29a9 PID 0x6001
    Then a quirk profile should be found
    And the profile should have requiresKernelDetach enabled

  Scenario: Micromax IN Note 1 regional phone matches quirk profile
    Given the quirks database is loaded
    When I look up VID 0x2a96 PID 0x6001
    Then a quirk profile should be found
    And the profile should have requiresKernelDetach enabled

  Scenario: BLU Vivo XL regional phone matches quirk profile
    Given the quirks database is loaded
    When I look up VID 0x271d PID 0x4008
    Then a quirk profile should be found
    And the profile should have requiresKernelDetach enabled

  Scenario: Doogee S100 Pro rugged phone matches quirk profile
    Given the quirks database is loaded
    When I look up VID 0x0e8d PID 0x2035
    Then a quirk profile should be found
    And the profile should have requiresKernelDetach enabled

  Scenario: Blackview BV9300 rugged phone matches quirk profile
    Given the quirks database is loaded
    When I look up VID 0x0e8d PID 0x2041
    Then a quirk profile should be found
    And the profile should have requiresKernelDetach enabled

  Scenario: Canon EOS R7 Mark II camera matches quirk profile
    Given the quirks database is loaded
    When I look up VID 0x04a9 PID 0x3319
    Then a quirk profile should be found
    And the profile should have cameraClass enabled

  Scenario: Nikon Z8 mirrorless camera matches quirk profile
    Given the quirks database is loaded
    When I look up VID 0x04b0 PID 0x0451
    Then a quirk profile should be found
    And the profile should have cameraClass enabled

  Scenario: Nikon Z9 mirrorless camera matches quirk profile
    Given the quirks database is loaded
    When I look up VID 0x04b0 PID 0x0450
    Then a quirk profile should be found
    And the profile should have cameraClass enabled
