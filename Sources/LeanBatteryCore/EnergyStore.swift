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

	/// True when staleness should hide `range`'s rows. Staleness is a `Now`-only concept: it
	/// exists so a quiet log doesn't present hours-old numbers as "now", and has no bearing on
	/// whether archived history for a longer range is valid (spec §9).
	public func suppressesRows(for range: EnergyRange) -> Bool {
		range == .now && isStale
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

	/// Everything worth remembering about one immutable archive, so a cache hit needs no
	/// decompression at all. `totals` is populated only once the archive has been seen lying
	/// entirely inside some window — until then it stays `nil` even though `earliest`/`latest`
	/// are already known and save the two scalar queries on the next call.
	private struct ArchiveFacts {
		var earliest: Double
		var latest: Double
		var totals: [String: Double]?
	}
	/// Facts keyed by archive filename. Archives are immutable, so these never expire while the
	/// popover is open.
	private var archiveCache: [String: ArchiveFacts] = [:]

	/// One archive's clamped, prorated contribution to the exact `[start, end]` it was computed
	/// against — for the archive that straddles the window start, where (unlike the wholly-inside
	/// or wholly-outside cases) the answer genuinely depends on where the window begins.
	private struct StraddleContribution {
		var start: Double
		var end: Double
		var sums: [String: Double]
	}
	/// Straddler contribution keyed by archive filename. `Now` and `7d` both re-derive `start` every
	/// 5-second tick, but for a multi-day range that only drifts by a few seconds tick to tick — far
	/// smaller than the window itself — so reusing the last clamped result while `[start, end]` is
	/// unchanged is a negligible, bounded trade-off. Archives rotate daily, which would invalidate
	/// this, but not within a single popover session, and `clearCache()` drops it on close anyway.
	private var straddleCache: [String: StraddleContribution] = [:]

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
		straddleCache = [:]
	}

	/// Energy per `who` for `range`, anchored to the newest logged moment rather than to `now`.
	public func sums(for range: EnergyRange, now: Double) throws -> EnergySums {
		let liveURI = PowerlogDatabase.readOnlyURI(path: livePath, immutable: false)
		// One open + one schema guard instead of three (`anchor`, `earliest`, `sums` used to each pay
		// their own).
		let window = try PowerlogDatabase.liveWindow(uri: liveURI, rangeSeconds: range.seconds)
		let anchor = window.anchor
		let start = anchor - range.seconds
		// The anchor often runs ahead of the wall clock; only a log that has gone quiet is stale.
		let isStale = (now - anchor) > stalenessLimit

		var totals = window.sums
		var earliestSeen = max(start, window.earliest)

		// Archives are only worth opening when the window reaches back past the live database.
		if start < window.earliest {
			for archive in archiveFiles() {
				guard let contribution = try? archiveSums(archive, start: start, end: window.earliest) else { continue }
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

	/// Decompresses `archive` if it isn't already open, runs `body` against its read-only URI, and
	/// always cleans up the temp file afterward.
	private func withArchive<T>(_ archive: URL, _ body: (String) throws -> T) throws -> T {
		let temporary = try decompress(archive)
		defer { try? FileManager.default.removeItem(at: temporary) }
		let uri = PowerlogDatabase.readOnlyURI(path: temporary.path, immutable: true)
		return try body(uri)
	}

	/// Returns one archive's contribution to `[start, end]`, decompressing only when the cache
	/// cannot answer the question on its own.
	private func archiveSums(_ archive: URL, start: Double, end: Double) throws -> (sums: [String: Double], earliest: Double) {
		let name = archive.lastPathComponent

		let facts: ArchiveFacts
		if let cached = archiveCache[name] {
			facts = cached
		} else {
			// Cache miss: one decompression learns everything this call needs — earliest, latest,
			// and (when it turns out to matter) the whole-archive totals — so later calls don't pay
			// for a second one just to get totals a moment later.
			facts = try withArchive(archive) { uri in
				let earliest = try PowerlogDatabase.earliest(uri: uri)
				let latest = try PowerlogDatabase.anchor(uri: uri)
				guard earliest >= start && latest <= end else {
					return ArchiveFacts(earliest: earliest, latest: latest, totals: nil)
				}
				return ArchiveFacts(earliest: earliest, latest: latest, totals: try PowerlogDatabase.totalSums(uri: uri))
			}
			archiveCache[name] = facts
		}

		// Entirely outside the window — known from the cached facts alone, no decompression needed.
		guard facts.latest > start, facts.earliest < end else { return ([:], facts.earliest) }

		// Entirely inside it: every row counts in full, so the sums do not depend on the window and
		// are safe to cache for the popover's lifetime.
		if facts.earliest >= start && facts.latest <= end {
			if let totals = facts.totals { return (totals, facts.earliest) }
			// Facts were cached under a different window shape that never needed totals — fetch them now.
			let totals = try withArchive(archive) { uri in try PowerlogDatabase.totalSums(uri: uri) }
			archiveCache[name] = ArchiveFacts(earliest: facts.earliest, latest: facts.latest, totals: totals)
			return (totals, facts.earliest)
		}

		// Straddling the window start: genuinely window-dependent, so it must always be a clamped,
		// prorated query — never the whole-archive totals above. But re-deriving that clamp every
		// tick is the cost this cache removes: reuse it verbatim while `[start, end]` is unchanged,
		// and recompute the moment either edge moves.
		if let cached = straddleCache[name], cached.start == start, cached.end == end {
			return (cached.sums, facts.earliest)
		}
		let sums = try withArchive(archive) { uri in try PowerlogDatabase.sums(uri: uri, start: start, end: end) }
		straddleCache[name] = StraddleContribution(start: start, end: end, sums: sums)
		return (sums, facts.earliest)
	}

	/// Decompresses a `.gz` to a temp file via `/usr/bin/gunzip` (66–72 ms per archive).
	/// ponytail: shelling out beats hand-rolling a gzip reader; Foundation has no gzip container support.
	public static func gunzip(_ url: URL) throws -> URL {
		let output = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".PLSQL")
		FileManager.default.createFile(atPath: output.path, contents: nil)
		do {
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
		} catch {
			try? FileManager.default.removeItem(at: output)
			throw error
		}
	}
}
