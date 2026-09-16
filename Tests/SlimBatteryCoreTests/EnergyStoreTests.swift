import Foundation
import Testing
@testable import SlimBatteryCore

/// Builds a temp directory holding a live DB and named archive files (already uncompressed).
private func makeTree(live: [FixtureRow], archives: [(String, [FixtureRow])]) -> (livePath: String, directory: URL) {
	let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
	try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
	let livePath = makeFixture(rows: live)
	for (name, rows) in archives {
		let path = makeFixture(rows: rows)
		try? FileManager.default.moveItem(atPath: path, toPath: directory.appendingPathComponent(name).path)
	}
	return (livePath, directory)
}

/// Stands in for gunzip: the fixtures are already plain SQLite, so copy to a fresh temp file.
private let passthrough: @Sendable (URL) throws -> URL = { url in
	let copy = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".PLSQL")
	try FileManager.default.copyItem(at: url, to: copy)
	return copy
}

/// Thread-safe decompression-call counter, so a test can prove the cache actually suppresses work.
private final class CallCounter: @unchecked Sendable {
	private let lock = NSLock()
	private var count = 0
	func increment() { lock.lock(); count += 1; lock.unlock() }
	var value: Int { lock.lock(); defer { lock.unlock() }; return count }
}

@Suite struct EnergyStoreTests {
	@Test func shortRangeNeverTouchesArchives() async throws {
		let tree = makeTree(
			live: [FixtureRow(start: 700, end: 1000, bundleId: "com.a", launchdName: "", energy: 300)],
			archives: [("powerlog_2026-09-10_AAAA.PLSQL.gz", [FixtureRow(start: 0, end: 100, bundleId: "com.old", launchdName: "", energy: 999)])])
		let store = EnergyStore(livePath: tree.livePath, archivesDirectory: tree.directory, decompress: passthrough)
		let result = try await store.sums(for: .now, now: 1000)
		#expect(result.sums["com.old"] == nil)
		#expect(abs((result.sums["com.a"] ?? 0) - 300) < 0.001)
	}

	@Test func longRangeMergesArchives() async throws {
		// Live covers [900, 1000]; the archive covers [0, 900] and ends exactly where live begins.
		let tree = makeTree(
			live: [FixtureRow(start: 900, end: 1000, bundleId: "com.a", launchdName: "", energy: 100)],
			archives: [("powerlog_2026-09-10_AAAA.PLSQL.gz", [FixtureRow(start: 800, end: 900, bundleId: "com.a", launchdName: "", energy: 50)])])
		let store = EnergyStore(livePath: tree.livePath, archivesDirectory: tree.directory, decompress: passthrough)
		let result = try await store.sums(for: .week, now: 1000)
		// 100 from live + 50 from the archive, merged under one id.
		#expect(abs((result.sums["com.a"] ?? 0) - 150) < 0.001)
	}

	@Test func coveredSpanReportsRealHistory() async throws {
		let tree = makeTree(
			live: [FixtureRow(start: 900, end: 1000, bundleId: "com.a", launchdName: "", energy: 100)],
			archives: [("powerlog_2026-09-10_AAAA.PLSQL.gz", [FixtureRow(start: 800, end: 900, bundleId: "com.a", launchdName: "", energy: 50)])])
		let store = EnergyStore(livePath: tree.livePath, archivesDirectory: tree.directory, decompress: passthrough)
		let result = try await store.sums(for: .week, now: 1000)
		// Only 200 s of history exists behind the 1000 anchor, not 7 days.
		#expect(abs(result.coveredSeconds - 200) < 0.001)
		#expect(EnergyRange.week.label(covering: result.coveredSeconds) == "3m")
	}

	@Test func staleLogIsFlagged() async throws {
		let tree = makeTree(live: [FixtureRow(start: 700, end: 1000, bundleId: "com.a", launchdName: "", energy: 300)], archives: [])
		let store = EnergyStore(livePath: tree.livePath, archivesDirectory: tree.directory, stalenessLimit: 900, decompress: passthrough)
		#expect(try await store.sums(for: .now, now: 1000).isStale == false)
		// The anchor is 1000; a wall clock 2000 s later means nothing has been logged for a long time.
		#expect(try await store.sums(for: .now, now: 3000).isStale)
	}

	@Test func anchorAheadOfTheClockIsNotStale() async throws {
		// MAX(timestampEnd) routinely runs ahead of the wall clock on a real Mac.
		let tree = makeTree(live: [FixtureRow(start: 700, end: 1000, bundleId: "com.a", launchdName: "", energy: 300)], archives: [])
		let store = EnergyStore(livePath: tree.livePath, archivesDirectory: tree.directory, decompress: passthrough)
		#expect(try await store.sums(for: .now, now: 800).isStale == false)
	}

	@Test func unreadableLiveDatabaseThrows() async {
		let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
		let store = EnergyStore(livePath: "/nonexistent/nope.PLSQL", archivesDirectory: directory, decompress: passthrough)
		await #expect(throws: PowerlogDatabase.Failure.self) {
			_ = try await store.sums(for: .now, now: 1000)
		}
	}

	@Test func aBrokenArchiveIsSkippedRatherThanFailing() async throws {
		let tree = makeTree(
			live: [FixtureRow(start: 900, end: 1000, bundleId: "com.a", launchdName: "", energy: 100)],
			archives: [])
		// An archive that cannot be decompressed must not take the whole range down (spec §9).
		try "not a database".write(to: tree.directory.appendingPathComponent("powerlog_2026-09-10_BAD.PLSQL.gz"), atomically: true, encoding: .utf8)
		let store = EnergyStore(livePath: tree.livePath, archivesDirectory: tree.directory, decompress: passthrough)
		let result = try await store.sums(for: .week, now: 1000)
		#expect(abs((result.sums["com.a"] ?? 0) - 100) < 0.001)
	}

	@Test func cacheAvoidsRepeatedDecompression() async throws {
		// The archive lies wholly inside the .week window, so once its facts and totals are
		// cached, a second identical call must not decompress it again.
		let tree = makeTree(
			live: [FixtureRow(start: 900, end: 1000, bundleId: "com.a", launchdName: "", energy: 100)],
			archives: [("powerlog_2026-09-10_AAAA.PLSQL.gz", [FixtureRow(start: 800, end: 900, bundleId: "com.a", launchdName: "", energy: 50)])])
		let counter = CallCounter()
		let countingDecompress: @Sendable (URL) throws -> URL = { url in
			counter.increment()
			return try passthrough(url)
		}
		let store = EnergyStore(livePath: tree.livePath, archivesDirectory: tree.directory, decompress: countingDecompress)

		let beforeFirst = counter.value
		_ = try await store.sums(for: .week, now: 1000)
		let firstCallDecompressions = counter.value - beforeFirst
		#expect(firstCallDecompressions > 0)

		let beforeSecond = counter.value
		_ = try await store.sums(for: .week, now: 1000)
		let secondCallDecompressions = counter.value - beforeSecond
		#expect(secondCallDecompressions < firstCallDecompressions)
		#expect(secondCallDecompressions == 0)

		await store.clearCache()
		let beforeThird = counter.value
		_ = try await store.sums(for: .week, now: 1000)
		let thirdCallDecompressions = counter.value - beforeThird
		#expect(thirdCallDecompressions > secondCallDecompressions)
	}

	@Test func cacheIsClearedOnDemand() async throws {
		let tree = makeTree(
			live: [FixtureRow(start: 900, end: 1000, bundleId: "com.a", launchdName: "", energy: 100)],
			archives: [("powerlog_2026-09-10_AAAA.PLSQL.gz", [FixtureRow(start: 800, end: 900, bundleId: "com.a", launchdName: "", energy: 50)])])
		let store = EnergyStore(livePath: tree.livePath, archivesDirectory: tree.directory, decompress: passthrough)
		_ = try await store.sums(for: .week, now: 1000)
		await store.clearCache()
		// Still correct after the cache is dropped.
		#expect(abs((try await store.sums(for: .week, now: 1000).sums["com.a"] ?? 0) - 150) < 0.001)
	}
}
