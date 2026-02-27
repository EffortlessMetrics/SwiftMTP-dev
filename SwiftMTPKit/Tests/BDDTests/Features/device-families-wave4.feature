Feature: Wave-4 device family connectivity
  As a user with various device types
  I want to connect successfully with correct behaviour
  So that my specific device works plug-and-play

  Background:
    Given SwiftMTP is initialized

  Scenario Outline: Android device connects with correct policy
    Given a device with vid <vid> and pid <pid>
    When the device policy is resolved
    Then supportsGetObjectPropList should be <proplist>
    And requiresKernelDetach should be <kernel_detach>

    Examples:
      | vid    | pid    | proplist | kernel_detach |
      | 0x2e04 | 0xc025 | false    | true          |
      | 0x1949 | 0x0007 | false    | false         |
      | 0x2d95 | 0x6002 | false    | true          |
      | 0x2a45 | 0x2008 | false    | true          |

  Scenario Outline: PTP camera connects with fast-path and no kernel detach
    Given a device with vid <vid> and pid <pid>
    When the device policy is resolved
    Then supportsGetObjectPropList should be true
    And requiresKernelDetach should be false

    Examples:
      | vid    | pid    |
      | 0x2672 | 0x004b |
      | 0x054c | 0x0c03 |

  Scenario Outline: PTP camera connects with fast-path and kernel detach
    Given a device with vid <vid> and pid <pid>
    When the device policy is resolved
    Then supportsGetObjectPropList should be true
    And requiresKernelDetach should be true

    Examples:
      | vid    | pid    |
      | 0x04b0 | 0x0443 |
      | 0x07b4 | 0x0113 |
