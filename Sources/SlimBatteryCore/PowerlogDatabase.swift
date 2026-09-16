import Foundation
import SQLite3

/// Read-only access to a powerlog SQLite database (spec §8.3, as amended by Plan 2b).
///
/// The window is anchored to the data (`MAX(timestampEnd)`), not to the wall clock, so the
/// powerlog epoch never has to be resolved. Each row contributes only the fraction of its
/// interval that lies inside the window: the mean interval (628 s) is longer than the `Now`
/// window (300 s), so unprorated sums badly distort short ranges.
public enum PowerlogDatabase {
	/// Thrown when a database cannot be opened or its schema is not the one we query.
	public enum Failure: Error, Equatable {
		case cannotOpen
		case schemaMismatch(missing: [String])
		/// A scalar query's single row held SQL NULL — the aggregate had no rows to aggregate.
		case noData
		/// `sqlite3_step` returned something other than `SQLITE_ROW`/`SQLITE_DONE` mid-scan
		/// (e.g. `SQLITE_BUSY`, `SQLITE_IOERR`): the result set is incomplete and must not be trusted.
		case queryFailed(code: Int32)
	}

	/// The powerlog table every query in this file reads from.
	static let table = "PLCoalitionAgent_EventInterval_CoalitionInterval"

	/// Columns the query depends on. Verified present on the live database and all archives (41 columns).
	static let requiredColumns: Set<String> = [
		"timestamp", "timestampEnd", "BundleId", "LaunchdName",
		"energy", "gpu_energy_nj", "ane_energy_nj",
	]

	/// Calibration knob (spec §8.3): `energy` appears to exclude GPU — on a real Mac
	/// `gpu_energy_nj > energy` in 140 of 2,553 rows with GPU activity — so all three are summed.
	static let energyExpression = "(energy + gpu_energy_nj + ane_energy_nj)"

	/// The `who` key: bundle id when present, launchd name otherwise.
	private static let whoExpression = "COALESCE(NULLIF(BundleId, ''), LaunchdName)"

	/// Builds a read-only SQLite URI. Archives are immutable; the live database is WAL and needs `mode=ro`.
	public static func readOnlyURI(path: String, immutable: Bool) -> String {
		"file:\(path)?\(immutable ? "immutable=1" : "mode=ro")"
	}

	/// Latest `timestampEnd` — the window anchor.
	public static func anchor(uri: String) throws -> Double {
		try scalar(uri: uri, sql: "SELECT MAX(timestampEnd) FROM \(table)")
	}

	/// Earliest `timestamp` — how far back this database reaches.
	public static func earliest(uri: String) throws -> Double {
		try scalar(uri: uri, sql: "SELECT MIN(timestamp) FROM \(table)")
	}

	/// Per-`who` energy in nanojoules over `[start, end]`, prorated by each interval's overlap.
	public static func sums(uri: String, start: Double, end: Double) throws -> [String: Double] {
		let sql = """
		SELECT \(whoExpression) AS who,
		       SUM(\(energyExpression) *
		           (MAX(0.0, MIN(timestampEnd, :end) - MAX(timestamp, :start)) / (timestampEnd - timestamp))) AS nj
		FROM \(table)
		WHERE timestampEnd > :start AND timestamp < :end AND timestampEnd > timestamp
		GROUP BY who
		HAVING nj > 0
		"""
		return try grouped(uri: uri, sql: sql) { statement in
			sqlite3_bind_double(statement, sqlite3_bind_parameter_index(statement, ":start"), start)
			sqlite3_bind_double(statement, sqlite3_bind_parameter_index(statement, ":end"), end)
		}
	}

	/// Per-`who` energy over the whole database, unclamped. Used for archives that lie entirely
	/// inside the window, whose sums are then window-independent and safe to cache.
	public static func totalSums(uri: String) throws -> [String: Double] {
		let sql = """
		SELECT \(whoExpression) AS who, SUM(\(energyExpression)) AS nj
		FROM \(table)
		WHERE timestampEnd > timestamp
		GROUP BY who
		HAVING nj > 0
		"""
		return try grouped(uri: uri, sql: sql) { _ in }
	}

	// MARK: - Plumbing

	/// Opens read-only and verifies the schema before any query runs.
	private static func open(_ uri: String) throws -> OpaquePointer {
		var handle: OpaquePointer?
		let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_URI
		guard sqlite3_open_v2(uri, &handle, flags, nil) == SQLITE_OK, let handle else {
			if let handle { sqlite3_close(handle) }
			throw Failure.cannotOpen
		}
		do {
			let present = try columns(handle)
			let missing = requiredColumns.subtracting(present)
			guard missing.isEmpty else { throw Failure.schemaMismatch(missing: missing.sorted()) }
		} catch {
			sqlite3_close(handle)
			throw error
		}
		return handle
	}

	/// Column names of the interval table, empty when it is absent.
	private static func columns(_ handle: OpaquePointer) throws -> Set<String> {
		var statement: OpaquePointer?
		guard sqlite3_prepare_v2(handle, "PRAGMA table_info(\(table))", -1, &statement, nil) == SQLITE_OK else { throw Failure.cannotOpen }
		defer { sqlite3_finalize(statement) }
		var names = Set<String>()
		var step = sqlite3_step(statement)
		while step == SQLITE_ROW {
			if let text = sqlite3_column_text(statement, 1) { names.insert(String(cString: text)) }
			step = sqlite3_step(statement)
		}
		guard step == SQLITE_DONE else { throw Failure.queryFailed(code: step) }
		return names
	}

	/// Runs a one-value query.
	private static func scalar(uri: String, sql: String) throws -> Double {
		let handle = try open(uri)
		defer { sqlite3_close(handle) }
		var statement: OpaquePointer?
		let prepared = sqlite3_prepare_v2(handle, sql, -1, &statement, nil)
		guard prepared == SQLITE_OK else { throw Failure.queryFailed(code: prepared) }
		defer { sqlite3_finalize(statement) }
		let step = sqlite3_step(statement)
		guard step == SQLITE_ROW else { throw Failure.queryFailed(code: step) }
		// MAX()/MIN() over zero rows still yields one row, holding SQL NULL rather than 0.0.
		guard sqlite3_column_type(statement, 0) != SQLITE_NULL else { throw Failure.noData }
		return sqlite3_column_double(statement, 0)
	}

	/// Runs a `who → nanojoules` query.
	private static func grouped(uri: String, sql: String, bind: (OpaquePointer?) -> Void) throws -> [String: Double] {
		let handle = try open(uri)
		defer { sqlite3_close(handle) }
		var statement: OpaquePointer?
		guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else { throw Failure.cannotOpen }
		defer { sqlite3_finalize(statement) }
		bind(statement)
		var sums: [String: Double] = [:]
		var step = sqlite3_step(statement)
		while step == SQLITE_ROW {
			if let text = sqlite3_column_text(statement, 0) {
				sums[String(cString: text), default: 0] += sqlite3_column_double(statement, 1)
			}
			step = sqlite3_step(statement)
		}
		guard step == SQLITE_DONE else { throw Failure.queryFailed(code: step) }
		return sums
	}
}
