Feature: Wave-11 emerging brand device matching

  Scenario: Tecno Camon 30 Pro matches quirk profile
    Given the quirks database is loaded
    When I look up VID 0x1d5b PID 0x600b
    Then a quirk profile should be found
    And the profile should have requiresKernelDetach enabled

  Scenario: Infinix Note 40 Pro matches quirk profile
    Given the quirks database is loaded
    When I look up VID 0x1d5c PID 0x6009
    Then a quirk profile should be found
    And the profile should have requiresKernelDetach enabled

  Scenario: Valve Steam Deck LCD matches quirk profile
    Given the quirks database is loaded
    When I look up VID 0x28de PID 0x1002
    Then a quirk profile should be found
    And the profile should have requiresKernelDetach enabled

  Scenario: Meta Quest 2 matches quirk profile
    Given the quirks database is loaded
    When I look up VID 0x2833 PID 0x0182
    Then a quirk profile should be found
    And the profile should have requiresKernelDetach enabled

  Scenario: Toshiba Gigabeat S matches quirk profile
    Given the quirks database is loaded
    When I look up VID 0x0930 PID 0x0010
    Then a quirk profile should be found

  Scenario: Philips GoGear Vibe matches quirk profile
    Given the quirks database is loaded
    When I look up VID 0x0471 PID 0x2075
    Then a quirk profile should be found

  Scenario: Archos 504 matches quirk profile
    Given the quirks database is loaded
    When I look up VID 0x0e79 PID 0x1307
    Then a quirk profile should be found

  Scenario: YotaPhone 2 matches quirk profile
    Given the quirks database is loaded
    When I look up VID 0x2916 PID 0x914d
    Then a quirk profile should be found
    And the profile should have requiresKernelDetach enabled
