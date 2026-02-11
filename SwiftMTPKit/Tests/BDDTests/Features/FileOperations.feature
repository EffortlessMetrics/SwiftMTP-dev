Feature: File Operations
  As a user of SwiftMTP
  I want to perform file and folder operations on my MTP device
  So that I can organize my files and transfer data

  Background:
    Given a connected MTP device
    And the device has an active session

  Scenario: Create folder on device
    Given I am in the root directory
    When I create a new folder named "TestFolder"
    Then the folder "TestFolder" should exist
    And the folder should have the correct MTP object format

  Scenario: Delete file from device
    Given a file exists on the device at path "/test.txt"
    When I delete the file
    Then the file should no longer exist
    And I should receive a success confirmation

  Scenario: Delete folder from device
    Given a folder exists on the device at path "/TestFolder"
    And the folder is empty
    When I delete the folder
    Then the folder should no longer exist
    And the parent directory should be updated

  Scenario: Rename file on device
    Given a file exists on the device at path "/oldname.txt"
    When I rename the file to "newname.txt"
    Then the file should be accessible at "/newname.txt"
    And the original path should no longer exist

  Scenario: Move file between folders
    Given a file exists at "/source/file.txt"
    And a folder "/destination" exists
    When I move the file to "/destination/file.txt"
    Then the file should be accessible at the new location
    And the source location should be empty

  Scenario: Copy file to device
    Given a local file exists at "/local/path/file.txt"
    When I copy the file to the device at "/device/path/file.txt"
    Then the file should exist on the device
    And the file size should match the original

  Scenario: Copy folder recursively
    Given a local folder exists with nested structure
    When I copy the folder to the device
    Then all files and subfolders should be copied
    And the folder structure should be preserved

  Scenario Outline: File operations with different device types
    Given a <device_type> device is connected
    And the device has an active session
    When I create a folder named "<folder_name>"
    Then the folder should be created successfully
    And the MTP object format should match the device quirks

    Examples:
      | device_type | folder_name    |
      | pixel7      | PixelDocs      |
      | oneplus3t   | OnePlusStorage |
      | mi-note2    | MiFiles        |

  Scenario: Batch file creation
    Given I need to create multiple folders
    When I create folders "Folder1", "Folder2", "Folder3" in batch
    Then all folders should be created
    And the operations should complete within acceptable time

  Scenario: Delete non-empty folder
    Given a folder exists with files inside
    When I attempt to delete the folder recursively
    Then all contents should be deleted
    And the folder should no longer exist

  Scenario: Handle duplicate file names
    Given a file named "test.txt" exists in the current directory
    When I create another file with the same name
    Then I should receive a duplicate name error
    Or the device should auto-rename the file
