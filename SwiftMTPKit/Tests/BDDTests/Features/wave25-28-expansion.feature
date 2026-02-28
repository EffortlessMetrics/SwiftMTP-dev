Feature: Wave 25-28 expansion: cameras, industrial, medical, media players, and phones

  Scenario: OM System OM-1 camera matches quirk profile
    Given the quirks database is loaded
    When I look up VID 0x33a2 PID 0x0135
    Then a quirk profile should be found
    And the profile should have cameraClass enabled

  Scenario: Leica M11-P camera matches quirk profile
    Given the quirks database is loaded
    When I look up VID 0x1a98 PID 0x0013
    Then a quirk profile should be found
    And the profile should have cameraClass enabled

  Scenario: Bambu Lab X1 Carbon 3D printer matches quirk profile
    Given the quirks database is loaded
    When I look up VID 0x3311 PID 0x0001
    Then a quirk profile should be found
    And the profile should have cameraClass disabled

  Scenario: Dexcom G6 glucose monitor matches quirk profile
    Given the quirks database is loaded
    When I look up VID 0x22a3 PID 0x0003
    Then a quirk profile should be found
    And the profile should have cameraClass disabled

  Scenario: Microsoft Zune HD matches quirk profile
    Given the quirks database is loaded
    When I look up VID 0x045e PID 0x0710
    Then a quirk profile should be found
    And the profile should have requiresKernelDetach disabled

  Scenario: Motorola Moto Z2 matches quirk profile
    Given the quirks database is loaded
    When I look up VID 0x22b8 PID 0x2e81
    Then a quirk profile should be found
    And the profile should have requiresKernelDetach enabled
