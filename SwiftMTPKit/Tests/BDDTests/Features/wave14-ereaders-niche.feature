Feature: Wave-14 e-readers, dashcams, and niche device matching

  Scenario: Kobo Clara 2E matches quirk profile
    Given the quirks database is loaded
    When I look up VID 0x2237 PID 0x418c
    Then a quirk profile should be found
    And the profile should have cameraClass disabled

  Scenario: Onyx Boox Tab Ultra matches quirk profile
    Given the quirks database is loaded
    When I look up VID 0x2207 PID 0x001a
    Then a quirk profile should be found
    And the profile should have requiresKernelDetach enabled

  Scenario: Amazon Kindle Fire HD 8 matches quirk profile
    Given the quirks database is loaded
    When I look up VID 0x1949 PID 0x0006
    Then a quirk profile should be found
    And the profile should have requiresKernelDetach enabled

  Scenario: PocketBook Era matches quirk profile
    Given the quirks database is loaded
    When I look up VID 0x0525 PID 0xa4a7
    Then a quirk profile should be found

  Scenario: Garmin Dash Cam matches quirk profile
    Given the quirks database is loaded
    When I look up VID 0x091e PID 0x0003
    Then a quirk profile should be found
    And the profile should have cameraClass enabled

  Scenario: TomTom GO 520 matches quirk profile
    Given the quirks database is loaded
    When I look up VID 0x1390 PID 0x7474
    Then a quirk profile should be found

  Scenario: FLIR E8-XT thermal camera matches quirk profile
    Given the quirks database is loaded
    When I look up VID 0x09cb PID 0x1007
    Then a quirk profile should be found
    And the profile should have cameraClass enabled

  Scenario: Anbernic RG556 gaming handheld matches quirk profile
    Given the quirks database is loaded
    When I look up VID 0x1d6b PID 0x0104
    Then a quirk profile should be found
    And the profile should have requiresKernelDetach enabled

  Scenario: WD My Passport Wireless Pro matches quirk profile
    Given the quirks database is loaded
    When I look up VID 0x1058 PID 0x0830
    Then a quirk profile should be found

  Scenario: Archos media player matches quirk profile
    Given the quirks database is loaded
    When I look up VID 0x0e79 PID 0x1307
    Then a quirk profile should be found
