import Foundation
import Testing
@testable import SlimBatteryCore

/// A `makeTree` fixture: the live DB path and the archive directory, removed automatically once
/// the test is done with them (Swift Testing has no `tearDown`, so `deinit` stands in for one).
private final class FixtureTree {
	let livePath: String
	let directory: URL
	init(livePath: String, directory: URL) {
		self.livePath = livePath
		self.directory = directory
	}
	deinit {
		try? FileManager.default.removeItem(atPath: livePath)
		try? FileManager.default.removeItem(at: directory)
	}
}

/// Builds a temp directory holding a live DB and named archive files (already uncompressed).
private func makeTree(live: [FixtureRow], archives: [(String, [FixtureRow])]) -> FixtureTree {
	let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
	try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
	let livePath = makeFixture(rows: live)
	for (name, rows) in archives {
		let path = makeFixture(rows: rows)
		try? FileManager.default.moveItem(atPath: path, toPath: directory.appendingPathComponent(name).path)
	}
	return FixtureTree(livePath: livePath, directory: directory)
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
	@Test func stalenessOnlySuppressesTheNowRange() {
		// Staleness must hide only `Now` — it has no business hiding a week of valid archived
		// history just because the live log has gone quiet.
		let stale = EnergySums(sums: [:], coveredSeconds: 100, isStale: true)
		#expect(stale.suppressesRows(for: .now))
		#expect(!stale.suppressesRows(for: .eightHours))
		#expect(!stale.suppressesRows(for: .day))
		#expect(!stale.suppressesRows(for: .week))

		let fresh = EnergySums(sums: [:], coveredSeconds: 100, isStale: false)
		#expect(!fresh.suppressesRows(for: .now))
	}

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

	@Test func straddlingArchiveCachesItsClampedContribution() async throws {
		// Live covers [900, 1000]; the archive covers [600, 900]. `.now` (300 s) against now: 1000
		// gives start = 700, which falls inside the archive's own span — it straddles the window
		// start, unlike `cacheAvoidsRepeatedDecompression`'s wholly-inside archive.
		let tree = makeTree(
			live: [FixtureRow(start: 900, end: 1000, bundleId: "com.a", launchdName: "", energy: 100)],
			archives: [("powerlog_2026-09-10_AAAA.PLSQL.gz", [FixtureRow(start: 600, end: 900, bundleId: "com.a", launchdName: "", energy: 300)])])
		let counter = CallCounter()
		let countingDecompress: @Sendable (URL) throws -> URL = { url in
			counter.increment()
			return try passthrough(url)
		}
		let store = EnergyStore(livePath: tree.livePath, archivesDirectory: tree.directory, decompress: countingDecompress)

		let beforeFirst = counter.value
		let first = try await store.sums(for: .now, now: 1000)
		let firstCallDecompressions = counter.value - beforeFirst
		#expect(firstCallDecompressions > 0)

		// By hand: the archive row spans [600, 900] carrying 300 nJ, clamped to the window's
		// [700, 900] slice — an overlap of 200 out of its own 300 s duration — so it contributes
		// 300 * (200 / 300) = 200. The live row fully occupies [900, 1000] inside [700, 1000], so it
		// contributes its whole 100. Total: 300. A regression that served the archive's unclamped
		// total (300) instead of its clamped slice (200) would sum to 400, not 300.
		#expect(abs((first.sums["com.a"] ?? 0) - 300) < 0.001)

		let beforeSecond = counter.value
		let second = try await store.sums(for: .now, now: 1000)
		let secondCallDecompressions = counter.value - beforeSecond
		#expect(secondCallDecompressions == 0)
		#expect(abs((second.sums["com.a"] ?? 0) - 300) < 0.001)

		await store.clearCache()
		let beforeThird = counter.value
		_ = try await store.sums(for: .now, now: 1000)
		let thirdCallDecompressions = counter.value - beforeThird
		#expect(thirdCallDecompressions > 0)
	}

	@Test func straddlingArchiveCacheRecomputesWhenTheRangeChanges() async throws {
		// An archive old enough that both `.now` and `.week` straddle it (rather than one landing
		// wholly inside), so a switch between them must miss the straddle cache and recompute.
		let tree = makeTree(
			live: [FixtureRow(start: 900, end: 1000, bundleId: "com.a", launchdName: "", energy: 100)],
			archives: [("powerlog_2026-09-10_AAAA.PLSQL.gz", [FixtureRow(start: -700_000, end: 900, bundleId: "com.a", launchdName: "", energy: 1_000_000)])])
		let counter = CallCounter()
		let countingDecompress: @Sendable (URL) throws -> URL = { url in
			counter.increment()
			return try passthrough(url)
		}
		let store = EnergyStore(livePath: tree.livePath, archivesDirectory: tree.directory, decompress: countingDecompress)

		let beforeNow = counter.value
		_ = try await store.sums(for: .now, now: 1000)
		#expect(counter.value - beforeNow > 0)

		// Same archive, but `.week` derives a different `start`, so the cached `.now` contribution
		// must not be reused — this must decompress again rather than answering from the cache.
		let beforeWeek = counter.value
		_ = try await store.sums(for: .week, now: 1000)
		#expect(counter.value - beforeWeek > 0)
	}
}
