Feature: Transfer Resume
  As a user of SwiftMTP
  I want to resume interrupted transfers
  So that I don't lose progress on large file transfers

  Background:
    Given a connected MTP device
    And the device has an active session
    And transfer journaling is enabled

  Scenario: Resume interrupted download
    Given a large file exists on the device
    And a previous transfer was interrupted at 50% completion
    When I resume the download
    Then the transfer should continue from the last checkpoint
    And the total time should be less than a full retransfer

  Scenario: Resume interrupted upload
    Given a large local file exists
    And a previous upload was interrupted at 75% completion
    When I resume the upload
    Then the transfer should continue from the checkpoint
    And the file should be fully transferred

  Scenario: Handle device disconnect during transfer
    Given a transfer is in progress
    When the device is disconnected unexpectedly
    Then the transfer journal should record the interruption
    And when the device is reconnected, I should be able to resume

  Scenario: Verify file integrity after transfer
    Given a file was transferred to the device
    When I verify the file integrity using checksum
    Then the checksum should match the original file
    And I should receive a verification success confirmation

  Scenario: Retry failed transfers with exponential backoff
    Given a transfer that fails due to device error
    When I retry the transfer with exponential backoff
    Then the retry should use increasing delays
    And after successful completion, normal timing should resume

  Scenario Outline: Resume behavior across device types
    Given a <device_type> device is connected
    And a previous transfer was interrupted at <interruption_point>%
    When I resume the transfer
    Then the resume should complete successfully
    And the transfer speed should be consistent with device capabilities

    Examples:
      | device_type | interruption_point |
      | pixel7      | 25                  |
      | pixel7      | 50                  |
      | pixel7      | 75                  |
      | oneplus3t   | 30                  |
      | oneplus3t   | 60                  |
      | mi-note2    | 40                  |

  Scenario: Handle corrupt transfer journal
    Given a transfer journal exists but is corrupt
    When I attempt to resume a transfer
    Then the system should detect the corruption
    And I should be prompted to start fresh or abort

  Scenario: Partial transfer cleanup
    Given a transfer was interrupted and never resumed
    When the cleanup process runs
    Then partial files should be removed
    And disk space should be reclaimed

  Scenario: Multiple concurrent transfer resumes
    Given multiple transfers were interrupted
    When I resume all transfers
    Then each transfer should resume from its own checkpoint
    And transfers should not interfere with each other

  Scenario: Transfer resume with different file sizes
    Given interrupted transfers of different sizes
    When I resume each transfer
    Then small files should resume quickly
    And large files should maintain their checkpoint accuracy
