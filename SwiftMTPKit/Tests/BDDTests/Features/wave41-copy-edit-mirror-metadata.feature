Feature: Wave 41 – Server-side copy, in-place edit, mirror filtering, conflict resolution, and rich metadata

  Background:
    Given a connected MTP device
    And the device has an active session

  Scenario: Server-side file copy
    Given a connected device with a file "photo.jpg"
    When I copy "photo.jpg" to storage "Internal"
    Then a new copy should exist on the device
    And the original file should still exist

  Scenario: In-place file editing
    Given a connected device with a file "notes.txt"
    When I begin editing "notes.txt"
    And I truncate the file to 0 bytes
    And I write new content "Updated content"
    And I end editing
    Then the file content should be "Updated content"

  Scenario: Mirror with format filter
    Given a connected device with photos and videos
    When I mirror with --photos-only
    Then only image files should be downloaded
    And video files should be skipped

  Scenario: Conflict resolution
    Given a file modified both locally and on device
    When I mirror with --on-conflict newer-wins
    Then the newer version should be kept

  Scenario: Rich metadata display
    Given a connected device with a JPEG photo
    When I run "info" on the photo
    Then I should see format, size, dates, and storage info
