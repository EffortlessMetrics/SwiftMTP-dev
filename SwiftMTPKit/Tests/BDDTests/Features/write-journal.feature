Feature: Write-path journaling
  As a developer using SwiftMTP
  I want the transfer journal to track write operations accurately
  So that uploads can be resumed and partial objects cleaned up

  Background:
    Given a connected mock device
    And the device has an active session

  Scenario: Upload records remote handle on success
    Given a connected mock device
    When I upload a file to the device
    Then the transfer journal contains the remote handle

  Scenario: Partial upload is cleaned up on reconnect
    Given a write that failed after SendObjectInfo
    When the device reconnects
    Then the partial object is deleted from the device
