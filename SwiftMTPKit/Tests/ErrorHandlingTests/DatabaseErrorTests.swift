// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import XCTest
@testable import SwiftMTPIndex

final class DatabaseErrorTests: XCTestCase {

    // MARK: - DBError Cases

    func testDBErrorOpenWithMessage() {
        let error = DBError.open("Failed to open database: out of memory")
        XCTAssertEqual(error.description, "Failed to open database: out of memory")
    }

    func testDBErrorPrepareWithMessage() {
        let error = DBError.prepare("Failed to prepare statement: syntax error")
        XCTAssertEqual(error.description, "Failed to prepare statement: syntax error")
    }

    func testDBErrorStepWithMessage() {
        let error = DBError.step("Failed to step: no such table")
        XCTAssertEqual(error.description, "Failed to step: no such table")
    }

    func testDBErrorBindWithMessage() {
        let error = DBError.bind("Failed to bind: type mismatch")
        XCTAssertEqual(error.description, "Failed to bind: type mismatch")
    }

    func testDBErrorColumnWithName() {
        let error = DBError.column("nonExistentColumn")
        XCTAssertEqual(error.description, "Missing column: nonExistentColumn")
    }

    func testDBErrorNotFound() {
        let error = DBError.notFound
        XCTAssertEqual(error.description, "No rows")
    }

    func testDBErrorConstraintWithMessage() {
        let error = DBError.constraint("UNIQUE constraint failed: objects.handle")
        XCTAssertEqual(error.description, "UNIQUE constraint failed: objects.handle")
    }

    // MARK: - DBError Pattern Matching

    func testDBErrorOpenPatternMatching() {
        let error: DBError = .open("Test error")
        switch error {
        case .open(let message):
            XCTAssertEqual(message, "Test error")
        default:
            XCTFail("Expected .open case")
        }
    }

    func testDBErrorPreparePatternMatching() {
        let error: DBError = .prepare("Test error")
        switch error {
        case .prepare(let message):
            XCTAssertEqual(message, "Test error")
        default:
            XCTFail("Expected .prepare case")
        }
    }

    func testDBErrorStepPatternMatching() {
        let error: DBError = .step("Test error")
        switch error {
        case .step(let message):
            XCTAssertEqual(message, "Test error")
        default:
            XCTFail("Expected .step case")
        }
    }

    func testDBErrorBindPatternMatching() {
        let error: DBError = .bind("Test error")
        switch error {
        case .bind(let message):
            XCTAssertEqual(message, "Test error")
        default:
            XCTFail("Expected .bind case")
        }
    }

    func testDBErrorNotFoundPatternMatching() {
        let error: DBError = .notFound
        switch error {
        case .notFound:
            // Success
            break
        default:
            XCTFail("Expected .notFound case")
        }
    }

    func testDBErrorConstraintPatternMatching() {
        let error: DBError = .constraint("Test constraint")
        switch error {
        case .constraint(let message):
            XCTAssertEqual(message, "Test constraint")
        default:
            XCTFail("Expected .constraint case")
        }
    }

    // MARK: - SQLite Error Scenarios (Mock)

    func testConstraintViolationScenario() {
        // Simulating constraint violation when inserting duplicate
        let error = DBError.constraint("UNIQUE constraint failed: objects.storage_id, objects.handle")
        XCTAssertTrue(error.description.contains("UNIQUE constraint"))
    }

    func testMissingTableScenario() {
        // Simulating missing table error
        let error = DBError.step("no such table: objects")
        XCTAssertTrue(error.description.contains("no such table"))
    }

    func testColumnMismatchScenario() {
        // Simulating column type mismatch
        let error = DBError.bind("cannot STEP a statement that has no result")
        XCTAssertNotNil(error.description)
    }

    func testSchemaMismatchScenario() {
        // Simulating schema version mismatch
        let error = DBError.prepare("file is not a database")
        XCTAssertTrue(error.description.contains("file is not a database"))
    }

    func testDiskFullScenario() {
        // Simulating disk full scenario
        let error = DBError.open("out of memory")
        // SQLite often reports disk full as out of memory
        XCTAssertNotNil(error.description)
    }

    func testReadOnlyDatabaseScenario() {
        // Simulating read-only database access
        let error = DBError.bind("attempt to write a readonly database")
        XCTAssertTrue(error.description.contains("readonly"))
    }

    func testLockedDatabaseScenario() {
        // Simulating database is locked
        let error = DBError.step("database is locked")
        XCTAssertTrue(error.description.contains("locked"))
    }

    func testBusyTimeoutScenario() {
        // Simulating busy timeout
        let error = DBError.step("database is locked")
        XCTAssertTrue(error.description.contains("locked"))
    }

    func testCorruptedDatabaseScenario() {
        // Simulating corrupted database
        let error = DBError.prepare("file is not a database")
        XCTAssertTrue(error.description.contains("file is not a database"))
    }

    func testTooManyColumnsScenario() {
        // Simulating too many columns
        let error = DBError.prepare("too many columns")
        XCTAssertTrue(error.description.contains("too many columns"))
    }

    func testTooManyTablesScenario() {
        // Simulating too many tables
        let error = DBError.prepare("too many tables")
        XCTAssertTrue(error.description.contains("too many tables"))
    }

    func testRowIDConflictScenario() {
        // Simulating rowid conflict
        let error = DBError.constraint("UNIQUE constraint failed: sqlite_sequence.name")
        XCTAssertTrue(error.description.contains("UNIQUE constraint"))
    }

    func testForeignKeyViolationScenario() {
        // Simulating foreign key violation
        let error = DBError.constraint("FOREIGN KEY constraint failed")
        XCTAssertTrue(error.description.contains("FOREIGN KEY constraint"))
    }

    func testCheckConstraintViolationScenario() {
        // Simulating check constraint violation
        let error = DBError.constraint("CHECK constraint failed: object_size >= 0")
        XCTAssertTrue(error.description.contains("CHECK constraint"))
    }

    func testNotNullConstraintViolationScenario() {
        // Simulating NOT NULL constraint violation
        let error = DBError.constraint("NOT NULL constraint failed: object_path")
        XCTAssertTrue(error.description.contains("NOT NULL constraint"))
    }

    func testTransactionRollbackScenario() {
        // Simulating transaction rollback
        let error = DBError.step("cannot rollback - no transaction is active")
        XCTAssertTrue(error.description.contains("rollback"))
    }

    func testDoubleBeginScenario() {
        // Simulating double BEGIN
        let error = DBError.step("cannot start a transaction within a transaction")
        XCTAssertTrue(error.description.contains("transaction"))
    }

    func testCommitWithoutBeginScenario() {
        // Simulating COMMIT without BEGIN
        let error = DBError.step("cannot commit - no transaction is active")
        XCTAssertTrue(error.description.contains("commit"))
    }

    // MARK: - Error Recovery Patterns

    func testRetryOnLockedScenario() {
        // Test that locked error can be identified for retry
        let error = DBError.step("database is locked")
        XCTAssertTrue(error.description.contains("locked"))
        // In real code, this would trigger retry logic
    }

    func testAbortOnConstraintViolation() {
        // Test that constraint violations are not retried
        let error = DBError.constraint("UNIQUE constraint failed")
        XCTAssertTrue(error.description.contains("UNIQUE"))
        // In real code, this would abort the operation
    }

    // MARK: - Error Descriptions are User-Friendly

    func testErrorDescriptionsAreLocalizedFriendly() {
        let errors: [DBError] = [
            .open("error"),
            .prepare("error"),
            .step("error"),
            .bind("error"),
            .column("col"),
            .notFound,
            .constraint("error")
        ]

        for error in errors {
            XCTAssertFalse(error.description.isEmpty)
            XCTAssertTrue(error.description.count > 0)
        }
    }

    // MARK: - Different Error Types Are Distinguishable

    func testDifferentErrorTypesAreDistinguishable() {
        let openError: DBError = .open("error")
        let prepareError: DBError = .prepare("error")
        let stepError: DBError = .step("error")

        // Each error type should be distinguishable
        XCTAssertFalse(matches(openError, other: prepareError))
        XCTAssertFalse(matches(prepareError, other: stepError))
        XCTAssertFalse(matches(openError, other: stepError))
    }

    private func matches(_ error1: DBError, other: DBError) -> Bool {
        switch (error1, other) {
        case (.open, .open): return true
        case (.prepare, .prepare): return true
        case (.step, .step): return true
        case (.bind, .bind): return true
        case (.column, .column): return true
        case (.notFound, .notFound): return true
        case (.constraint, .constraint): return true
        default: return false
        }
    }
}
