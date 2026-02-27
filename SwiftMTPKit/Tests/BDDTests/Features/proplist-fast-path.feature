Feature: GetObjectPropList fast-path enumeration
  As a developer using SwiftMTP
  I want devices with supportsGetObjectPropList=true to use the 0x9805 fast path
  So that file listings are faster with a single round-trip

  Background:
    Given a virtual MTP device with quirk supportsGetObjectPropList=true

  Scenario: Fast-path returns all objects in one round-trip
    Given the device has 3 files in root storage
    When I call getObjectPropList for the root handle
    Then I should receive 3 MTPObjectInfo entries
    And the GetObjectPropList opcode (0x9805) should have been sent

  Scenario: Fallback when quirk is disabled
    Given a virtual MTP device without GetObjectPropList quirk
    And the device has files in storage
    When I enumerate the files
    Then the GetObjectPropList opcode (0x9805) should NOT have been sent
    And I should still receive the file list via GetObjectInfo fallback

  Scenario: String properties decoded correctly in fast-path
    Given the device supports GetObjectPropList
    And the device has a file named "photo.jpg"
    When I call getObjectPropList
    Then the returned MTPObjectInfo should have name "photo.jpg"
    And the modified date should be non-nil if dateModified was in the response
