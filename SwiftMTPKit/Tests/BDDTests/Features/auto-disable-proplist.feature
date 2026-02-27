Feature: Auto-disable GetObjectPropList on OperationNotSupported
  As a user with a device that claims PTP support but fails on 0x9805
  I want SwiftMTP to automatically fall back to per-handle enumeration
  So that my device still works without manual configuration

  Background:
    Given a connected MTP device
    And the device has an active session
    And the initial policy has supportsGetObjectPropList=true

  Scenario: Device returning OperationNotSupported disables fast path
    Given a device that returns OperationNotSupported for GetObjectPropList
    When I enumerate device files
    Then the GetObjectPropList fast path should be disabled for this session
    And the fallback per-handle enumeration should be used
    And all files should still be returned correctly

  Scenario: Auto-disable persists for remainder of session
    Given a device that returned OperationNotSupported for GetObjectPropList
    And GetObjectPropList was auto-disabled this session
    When I enumerate files a second time
    Then GetObjectPropList should not be attempted again
    And the fallback path should be used directly

  Scenario: Auto-disable does not affect other sessions
    Given session A where GetObjectPropList was auto-disabled
    When a new session B is opened to the same device
    Then session B should start with the configured default policy
