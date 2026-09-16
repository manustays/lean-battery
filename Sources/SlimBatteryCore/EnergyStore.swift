import Foundation

/// Energy sums for one range, with how much real history stands behind them.
public struct EnergySums: Sendable, Equatable {
	public var sums: [String: Double]
	/// Seconds of history actually covered — drives the short-span segment label.
	public var coveredSeconds: Double
	/// True when the log has not been written recently enough to call this "now".
	public var isStale: Bool

	public init(sums: [String: Double], coveredSeconds: Double, isStale: Bool) {
		self.sums = sums
		self.coveredSeconds = coveredSeconds
		self.isStale = isStale
	}
}

/// Reads energy from the live powerlog and, for long ranges, the daily archives (spec §8.3).
///
/// An actor because every call does blocking file and SQLite work: a single live query costs
/// 33–73 ms and the seven-day path costs roughly a second, so none of it may run on the main actor.
public actor EnergyStore {
	private let livePath: String
	private let archivesDirectory: URL
	private let stalenessLimit: Double
	private let decompress: @Sendable (URL) throws -> URL
	/// Whole-archive sums keyed by archive filename. Archives are immutable, so these never expire
	/// while the popover is open; they are only valid for archives lying entirely inside the window.
	private var archiveCache: [String: [String: Double]] = [:]

	public static let defaultLivePath = "/private/var/db/powerlog/Library/BatteryLife/CurrentPowerlog.PLSQL"
	public static let defaultArchivesDirectory = URL(fileURLWithPath: "/private/var/db/powerlog/Library/BatteryLife/Archives")

	/// - Parameter stalenessLimit: seconds without a log write after which the range reads as empty.
	///   ponytail: 15 min is a judgement call — the real write cadence could not be measured without a
	///   long idle observation. Raise it if an idle Mac shows "no activity" too eagerly.
	public init(
		livePath: String = EnergyStore.defaultLivePath,
		archivesDirectory: URL = EnergyStore.defaultArchivesDirectory,
		stalenessLimit: Double = 900,
		decompress: @escaping @Sendable (URL) throws -> URL = EnergyStore.gunzip
	) {
		self.livePath = livePath
		self.archivesDirectory = archivesDirectory
		self.stalenessLimit = stalenessLimit
		self.decompress = decompress
	}

	/// Drops cached archive sums. Called when the popover closes.
	public func clearCache() {
		archiveCache = [:]
	}

	/// Energy per `who` for `range`, anchored to the newest logged moment rather than to `now`.
	public func sums(for range: EnergyRange, now: Double) throws -> EnergySums {
		let liveURI = PowerlogDatabase.readOnlyURI(path: livePath, immutable: false)
		let anchor = try PowerlogDatabase.anchor(uri: liveURI)
		let liveEarliest = try PowerlogDatabase.earliest(uri: liveURI)
		let start = anchor - range.seconds
		// The anchor often runs ahead of the wall clock; only a log that has gone quiet is stale.
		let isStale = (now - anchor) > stalenessLimit

		var totals = try PowerlogDatabase.sums(uri: liveURI, start: start, end: anchor)
		var earliestSeen = max(start, liveEarliest)

		// Archives are only worth opening when the window reaches back past the live database.
		if start < liveEarliest {
			for archive in archiveFiles() {
				guard let contribution = try? archiveSums(archive, start: start, end: liveEarliest) else { continue }
				for (who, energy) in contribution.sums {
					totals[who, default: 0] += energy
				}
				earliestSeen = min(earliestSeen, max(start, contribution.earliest))
			}
		}

		return EnergySums(sums: totals, coveredSeconds: max(0, anchor - earliestSeen), isStale: isStale)
	}

	// MARK: - Archives

	/// Archive files, newest first. Names look like `powerlog_2026-09-14_8EE53CD0.PLSQL.gz`.
	private func archiveFiles() -> [URL] {
		let contents = (try? FileManager.default.contentsOfDirectory(at: archivesDirectory, includingPropertiesForKeys: nil)) ?? []
		return contents
			.filter { $0.lastPathComponent.hasSuffix(".gz") }
			.sorted { $0.lastPathComponent > $1.lastPathComponent }
	}

	/// Decompresses one archive and returns its contribution to `[start, end]`.
	private func archiveSums(_ archive: URL, start: Double, end: Double) throws -> (sums: [String: Double], earliest: Double) {
		let name = archive.lastPathComponent
		let temporary = try decompress(archive)
		defer { try? FileManager.default.removeItem(at: temporary) }
		let uri = PowerlogDatabase.readOnlyURI(path: temporary.path, immutable: true)
		let earliest = try PowerlogDatabase.earliest(uri: uri)
		let latest = try PowerlogDatabase.anchor(uri: uri)

		// Entirely outside the window.
		guard latest > start, earliest < end else { return ([:], earliest) }

		// Entirely inside it: every row counts in full, so the sums do not depend on the window
		// and can be cached for the popover's lifetime. Only the oldest archive ever straddles
		// `start`, so at most one archive is re-queried per tick.
		if earliest >= start && latest <= end {
			if let cached = archiveCache[name] { return (cached, earliest) }
			let sums = try PowerlogDatabase.totalSums(uri: uri)
			archiveCache[name] = sums
			return (sums, earliest)
		}
		return (try PowerlogDatabase.sums(uri: uri, start: start, end: end), earliest)
	}

	/// Decompresses a `.gz` to a temp file via `/usr/bin/gunzip` (66–72 ms per archive).
	/// ponytail: shelling out beats hand-rolling a gzip reader; Foundation has no gzip container support.
	public static func gunzip(_ url: URL) throws -> URL {
		let output = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".PLSQL")
		FileManager.default.createFile(atPath: output.path, contents: nil)
		let handle = try FileHandle(forWritingTo: output)
		defer { try? handle.close() }
		let process = Process()
		process.executableURL = URL(fileURLWithPath: "/usr/bin/gunzip")
		process.arguments = ["-c", url.path]
		process.standardOutput = handle
		process.standardError = FileHandle.nullDevice
		try process.run()
		process.waitUntilExit()
		guard process.terminationStatus == 0 else {
			try? FileManager.default.removeItem(at: output)
			throw CocoaError(.fileReadCorruptFile)
		}
		return output
	}
}
