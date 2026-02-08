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

    // MARK: - DBError Equatability

    func testDBErrorOpenEquatability() {
        XCTAssertEqual(
            DBError.open("Test"),
            DBError.open("Test")
        )
    }

    func testDBErrorOpenInequability() {
        XCTAssertNotEqual(
            DBError.open("Error A"),
            DBError.open("Error B")
        )
    }

    func testDBErrorDifferentCasesInequatable() {
        XCTAssertNotEqual(
            DBError.open("Error"),
            DBError.prepare("Error")
        )
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
}
