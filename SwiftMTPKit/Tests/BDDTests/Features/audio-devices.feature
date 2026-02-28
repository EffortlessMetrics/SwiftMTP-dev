Feature: Audio devices connect via MTP
  As a user with a portable audio player, speaker, or headphone
  I want to transfer files to and from my audio device
  So that I can manage my music and firmware updates

  Background:
    Given the quirk database is loaded

  Scenario: Fiio M11 DAP is recognised in the quirk database
    Given a USB device with vid 0x2972 and pid 0x0015
    Then the matched quirk id should be "fiio-m11-0015"
    And requiresKernelDetach should be true

  Scenario: Fiio M7 DAP is recognised in the quirk database
    Given a USB device with vid 0x2972 and pid 0x0011
    Then the matched quirk id should be "fiio-m7-0011"
    And requiresKernelDetach should be true

  Scenario: Fiio M15 DAP is recognised in the quirk database
    Given a USB device with vid 0x2972 and pid 0x001b
    Then the matched quirk id should be "fiio-m15-001b"
    And requiresKernelDetach should be true

  Scenario: Sony NW-A105 Walkman is recognised in the quirk database
    Given a USB device with vid 0x054c and pid 0x0d00
    Then the matched quirk id should be "sony-nw-a105-0d00"
    And requiresKernelDetach should be false

  Scenario: Sony NW-A45 Walkman is recognised in the quirk database
    Given a USB device with vid 0x054c and pid 0x0c71
    Then the matched quirk id should be "sony-nw-a45-0c71"
    And requiresKernelDetach should be false

  Scenario: Sony NW-ZX500 Walkman is recognised in the quirk database
    Given a USB device with vid 0x054c and pid 0x0d01
    Then the matched quirk id should be "sony-nw-zx500-0d01"
    And requiresKernelDetach should be false

  Scenario: Marshall London speaker phone is recognised in the quirk database
    Given a USB device with vid 0x2ad9 and pid 0x000b
    Then the matched quirk id should be "marshall-london-000b"
    And requiresKernelDetach should be true

  Scenario: Marshall Emberton speaker is recognised in the quirk database
    Given a USB device with vid 0x2ad9 and pid 0x000d
    Then the matched quirk id should be "marshall-emberton-000d"
    And requiresKernelDetach should be false

  Scenario: Marshall Emberton II speaker is recognised in the quirk database
    Given a USB device with vid 0x2ad9 and pid 0x000f
    Then the matched quirk id should be "marshall-emberton-ii-000f"
    And requiresKernelDetach should be false

  Scenario: JBL Charge 5 speaker is recognised in the quirk database
    Given a USB device with vid 0x0ecb and pid 0x2070
    Then the matched quirk id should be "jbl-charge5-2070"
    And requiresKernelDetach should be false

  Scenario: JBL Flip 6 speaker is recognised in the quirk database
    Given a USB device with vid 0x0ecb and pid 0x2072
    Then the matched quirk id should be "jbl-flip6-2072"
    And requiresKernelDetach should be false

  Scenario: JBL PartyBox 310 speaker is recognised in the quirk database
    Given a USB device with vid 0x0ecb and pid 0x2074
    Then the matched quirk id should be "jbl-partybox310-2074"
    And requiresKernelDetach should be false

  Scenario: Bose QC35 II headphone is recognised in the quirk database
    Given a USB device with vid 0x05a7 and pid 0x4002
    Then the matched quirk id should be "bose-qc35ii-4002"
    And requiresKernelDetach should be false

  Scenario: Bose NC 700 headphone is recognised in the quirk database
    Given a USB device with vid 0x05a7 and pid 0x4004
    Then the matched quirk id should be "bose-nc700-4004"
    And requiresKernelDetach should be false

  Scenario: Bose QC45 headphone is recognised in the quirk database
    Given a USB device with vid 0x05a7 and pid 0x4006
    Then the matched quirk id should be "bose-qc45-4006"
    And requiresKernelDetach should be false

  Scenario: Bose QC Ultra headphone is recognised in the quirk database
    Given a USB device with vid 0x05a7 and pid 0x4008
    Then the matched quirk id should be "bose-qc-ultra-4008"
    And requiresKernelDetach should be false

  Scenario: Bose SoundLink Flex speaker is recognised in the quirk database
    Given a USB device with vid 0x05a7 and pid 0x40fe
    Then the matched quirk id should be "bose-soundlink-flex-40fe"
    And requiresKernelDetach should be false
