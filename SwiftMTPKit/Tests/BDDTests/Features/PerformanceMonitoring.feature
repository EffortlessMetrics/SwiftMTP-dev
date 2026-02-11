Feature: Performance Monitoring
  As a SwiftMTP user
  I want to monitor transfer performance metrics
  So that I can optimize transfer operations and detect regressions

  Background:
    Given SwiftMTP is initialized
    And performance tracking is enabled

  Scenario: Track transfer throughput over time
    Given a transfer is in progress
    When I monitor the throughput
    Then I should see real-time throughput updates
    And the average throughput should be calculated
    And peak and minimum values should be recorded

  Scenario: Report performance regression
    Given historical performance data exists
    When current transfer performance drops below threshold
    Then a regression warning should be generated
    And the regression details should be logged

  Scenario Outline: Performance monitoring across device types
    Given a <device_type> device is connected
    When I perform a standard transfer
    Then performance metrics should be collected
    And should fall within expected range for device

    Examples:
      | device_type | expected_mbps_min |
      | pixel7      | 15                |
      | oneplus3t   | 10                |
      | mi-note2    | 8                 |

  Scenario: Adaptive buffer sizing based on performance
    Given performance metrics indicate low throughput
    When the system analyzes buffer efficiency
    Then buffer sizes should be adjusted
    And transfer parameters should be tuned

  Scenario: Latency measurement
    Given device operations are being performed
    When I measure command latency
    Then round-trip times should be recorded
    And latency trends should be graphed

  Scenario: Performance data persistence
    Given performance metrics are collected
    When the session ends
    Then data should be persisted for analysis
    And should be retrievable in future sessions

  Scenario: Performance benchmark comparison
    Given multiple transfers have been performed
    When I compare against baseline benchmarks
    Then percentage differences should be calculated
    And any significant changes should be highlighted

  Scenario: Concurrent transfer performance
    Given multiple transfers are running in parallel
    When I monitor overall system performance
    Then throughput should scale appropriately
    And individual transfer speeds should be tracked

  Scenario: Performance threshold alerts
    Given performance thresholds are configured
    When throughput drops below threshold
    Then an alert should be generated
    And notification should be sent

  Scenario: Transfer time estimation
    Given a file is queued for transfer
    When I request an estimated completion time
    Then based on historical data, time should be calculated
    And estimate should update as transfer progresses
