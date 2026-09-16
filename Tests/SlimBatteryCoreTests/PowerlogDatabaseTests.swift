import Foundation
import SQLite3
import Testing
@testable import SlimBatteryCore

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// One fixture interval: start, end, bundle id, launchd name, energy, gpu, ane.
struct FixtureRow {
	var start: Double
	var end: Double
	var bundleId: String
	var launchdName: String
	var energy: Int
	var gpu: Int = 0
	var ane: Int = 0
}

/// Writes a powerlog-shaped SQLite file and returns its path. Pass `columns` to simulate a schema change.
@discardableResult
func makeFixture(
	rows: [FixtureRow],
	columns: String = """
	ID INTEGER PRIMARY KEY, timestamp REAL, timestampEnd REAL,
	BundleId TEXT, LaunchdName TEXT,
	energy INTEGER, gpu_energy_nj INTEGER, ane_energy_nj INTEGER
	"""
) -> String {
	let path = FileManager.default.temporaryDirectory
		.appendingPathComponent(UUID().uuidString + ".PLSQL").path
	var db: OpaquePointer?
	// precondition, not #expect: this helper runs outside a @Test function, and a fixture that
	// fails to build is a broken test rig rather than a failing expectation.
	precondition(sqlite3_open(path, &db) == SQLITE_OK, "fixture: cannot create \(path)")
	defer { sqlite3_close(db) }
	let ddl = "CREATE TABLE \(PowerlogDatabase.table) (\(columns));"
	precondition(sqlite3_exec(db, ddl, nil, nil, nil) == SQLITE_OK, "fixture: cannot create table")
	guard !rows.isEmpty else { return path }
	for (index, row) in rows.enumerated() {
		var statement: OpaquePointer?
		let sql = "INSERT INTO \(PowerlogDatabase.table) VALUES (?,?,?,?,?,?,?,?)"
		precondition(sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, "fixture: cannot prepare insert")
		sqlite3_bind_int64(statement, 1, Int64(index + 1))
		sqlite3_bind_double(statement, 2, row.start)
		sqlite3_bind_double(statement, 3, row.end)
		sqlite3_bind_text(statement, 4, row.bundleId, -1, SQLITE_TRANSIENT)
		sqlite3_bind_text(statement, 5, row.launchdName, -1, SQLITE_TRANSIENT)
		sqlite3_bind_int64(statement, 6, Int64(row.energy))
		sqlite3_bind_int64(statement, 7, Int64(row.gpu))
		sqlite3_bind_int64(statement, 8, Int64(row.ane))
		precondition(sqlite3_step(statement) == SQLITE_DONE, "fixture: cannot insert row \(index)")
		sqlite3_finalize(statement)
	}
	return path
}

/// The shared fixture: window [700, 1000] against an anchor of 1000.
private func standardRows() -> [FixtureRow] {
	[
		FixtureRow(start: 800, end: 1000, bundleId: "com.a", launchdName: "", energy: 60, gpu: 30, ane: 10),
		FixtureRow(start: 600, end: 1000, bundleId: "com.b", launchdName: "", energy: 400),
		FixtureRow(start: 500, end: 800, bundleId: "com.c", launchdName: "", energy: 300),
		FixtureRow(start: 100, end: 200, bundleId: "com.d", launchdName: "", energy: 999),
		FixtureRow(start: 900, end: 950, bundleId: "com.a", launchdName: "", energy: 50),
		FixtureRow(start: 900, end: 1000, bundleId: "", launchdName: "sh.brew.thing", energy: 100),
	]
}

@Suite struct PowerlogDatabaseTests {
	@Test func anchorIsTheLatestEnd() throws {
		let path = makeFixture(rows: standardRows())
		defer { try? FileManager.default.removeItem(atPath: path) }
		let uri = PowerlogDatabase.readOnlyURI(path: path, immutable: false)
		#expect(try PowerlogDatabase.anchor(uri: uri) == 1000)
	}

	@Test func earliestIsTheFirstStart() throws {
		let path = makeFixture(rows: standardRows())
		defer { try? FileManager.default.removeItem(atPath: path) }
		let uri = PowerlogDatabase.readOnlyURI(path: path, immutable: false)
		#expect(try PowerlogDatabase.earliest(uri: uri) == 100)
	}

	@Test func sumsAreProratedByOverlapAndMergedByWho() throws {
		let path = makeFixture(rows: standardRows())
		defer { try? FileManager.default.removeItem(atPath: path) }
		let uri = PowerlogDatabase.readOnlyURI(path: path, immutable: false)
		let sums = try PowerlogDatabase.sums(uri: uri, start: 700, end: 1000)
		// com.a: 100 fully inside + 50 fully inside = 150 (also proves energy+gpu+ane are summed)
		#expect(abs((sums["com.a"] ?? 0) - 150) < 0.001)
		// com.b: 400 nj over a 400 s interval, 300 s inside → 0.75 → 300
		#expect(abs((sums["com.b"] ?? 0) - 300) < 0.001)
		// com.c: 300 nj over a 300 s interval, 100 s inside → 1/3 → 100
		#expect(abs((sums["com.c"] ?? 0) - 100) < 0.001)
		// Empty BundleId falls back to LaunchdName.
		#expect(abs((sums["sh.brew.thing"] ?? 0) - 100) < 0.001)
		// Entirely before the window.
		#expect(sums["com.d"] == nil)
		#expect(abs(sums.values.reduce(0, +) - 650) < 0.001)
	}

	@Test func totalSumsIgnoreTheWindow() throws {
		let path = makeFixture(rows: standardRows())
		defer { try? FileManager.default.removeItem(atPath: path) }
		let uri = PowerlogDatabase.readOnlyURI(path: path, immutable: false)
		let sums = try PowerlogDatabase.totalSums(uri: uri)
		#expect(sums["com.d"] == 999)          // now included
		#expect(sums["com.a"] == 150)          // 100 + 50, unprorated
	}

	@Test func zeroLengthIntervalsAreSkipped() throws {
		let path = makeFixture(rows: [FixtureRow(start: 900, end: 900, bundleId: "com.z", launchdName: "", energy: 500)])
		defer { try? FileManager.default.removeItem(atPath: path) }
		let uri = PowerlogDatabase.readOnlyURI(path: path, immutable: false)
		// Must not divide by zero, and must not appear.
		#expect(try PowerlogDatabase.sums(uri: uri, start: 700, end: 1000).isEmpty)
	}

	@Test func schemaGuardRejectsAMissingColumn() throws {
		let path = makeFixture(rows: [], columns: "ID INTEGER PRIMARY KEY, timestamp REAL, BundleId TEXT")
		defer { try? FileManager.default.removeItem(atPath: path) }
		let uri = PowerlogDatabase.readOnlyURI(path: path, immutable: false)
		#expect(throws: PowerlogDatabase.Failure.self) {
			_ = try PowerlogDatabase.sums(uri: uri, start: 700, end: 1000)
		}
	}

	@Test func anchorThrowsNoDataOnEmptyTable() throws {
		// MAX()/MIN() over zero rows still yields one row holding SQL NULL, not 0.0 — a schema-valid
		// but empty database must not be silently reported as anchored at time zero.
		let path = makeFixture(rows: [])
		defer { try? FileManager.default.removeItem(atPath: path) }
		let uri = PowerlogDatabase.readOnlyURI(path: path, immutable: false)
		#expect(throws: PowerlogDatabase.Failure.noData) {
			_ = try PowerlogDatabase.anchor(uri: uri)
		}
		#expect(throws: PowerlogDatabase.Failure.noData) {
			_ = try PowerlogDatabase.earliest(uri: uri)
		}
	}

	@Test func missingFileCannotOpen() {
		let uri = PowerlogDatabase.readOnlyURI(path: "/nonexistent/nope.PLSQL", immutable: false)
		#expect(throws: PowerlogDatabase.Failure.cannotOpen) {
			_ = try PowerlogDatabase.anchor(uri: uri)
		}
	}
}
