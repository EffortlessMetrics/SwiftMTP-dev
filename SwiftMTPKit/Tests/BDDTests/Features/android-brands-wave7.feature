Feature: Wave-7 Android brand connectivity
  As a user with LG, HTC, ZTE, OPPO, vivo, or Huawei devices
  I want to connect with correct MTP policy
  So that file transfer works plug-and-play

  Background:
    Given SwiftMTP is initialized

  Scenario Outline: LG Android phones connect with Android MTP policy
    Given a device with vid <vid> and pid <pid>
    When the device policy is resolved
    Then supportsGetObjectPropList should be false
    And requiresKernelDetach should be true

    Examples:
      | vid    | pid    |
      | 0x1004 | 0x633e |
      | 0x1004 | 0x6300 |
      | 0x1004 | 0x61f1 |

  Scenario Outline: HTC Android phones connect with Android MTP policy
    Given a device with vid <vid> and pid <pid>
    When the device policy is resolved
    Then supportsGetObjectPropList should be false
    And requiresKernelDetach should be true

    Examples:
      | vid    | pid    |
      | 0x0bb4 | 0x0f15 |
      | 0x0bb4 | 0x0f91 |
      | 0x0bb4 | 0x0ffe |

  Scenario Outline: ZTE Android phones connect with Android MTP policy
    Given a device with vid <vid> and pid <pid>
    When the device policy is resolved
    Then supportsGetObjectPropList should be false
    And requiresKernelDetach should be true

    Examples:
      | vid    | pid    |
      | 0x19d2 | 0x0306 |
      | 0x19d2 | 0x0343 |
      | 0x19d2 | 0x0383 |

  Scenario Outline: OPPO and Realme Android phones connect with Android MTP policy
    Given a device with vid <vid> and pid <pid>
    When the device policy is resolved
    Then supportsGetObjectPropList should be false
    And requiresKernelDetach should be true

    Examples:
      | vid    | pid    |
      | 0x22d9 | 0x0001 |
      | 0x22d9 | 0x202a |
      | 0x22d9 | 0x2764 |

  Scenario Outline: vivo and iQOO Android phones connect with Android MTP policy
    Given a device with vid <vid> and pid <pid>
    When the device policy is resolved
    Then supportsGetObjectPropList should be false
    And requiresKernelDetach should be true

    Examples:
      | vid    | pid    |
      | 0x2d95 | 0x6002 |
      | 0x2d95 | 0x6003 |
      | 0x2d95 | 0x6012 |

  Scenario Outline: Huawei Android phones connect with Android MTP policy
    Given a device with vid <vid> and pid <pid>
    When the device policy is resolved
    Then supportsGetObjectPropList should be false
    And requiresKernelDetach should be true

    Examples:
      | vid    | pid    |
      | 0x12d1 | 0x107e |
      | 0x12d1 | 0x1052 |
      | 0x12d1 | 0x1054 |
