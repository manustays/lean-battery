import Testing
@testable import LeanBatteryCore

@Suite struct UpdatePolicyTests {
	let now = 1_000_000.0
	let releasesURL = "https://github.com/manustays/lean-battery/releases/tag/v0.2.0"

	// MARK: shouldCheck

	@Test func checksOnFirstPopoverOpen() {
		#expect(UpdatePolicy.shouldCheck(manual: false, enabled: true, inFlight: false, state: UpdateState(), now: now))
	}

	@Test func doesNotCheckWhenDisabled() {
		#expect(!UpdatePolicy.shouldCheck(manual: false, enabled: false, inFlight: false, state: UpdateState(), now: now))
		#expect(!UpdatePolicy.shouldCheck(manual: true, enabled: false, inFlight: false, state: UpdateState(), now: now))
	}

	@Test func doesNotCheckWhileARequestIsInFlight() {
		#expect(!UpdatePolicy.shouldCheck(manual: true, enabled: true, inFlight: true, state: UpdateState(), now: now))
	}

	@Test func honorsTheTwentyFourHourCooldownForAutomaticChecks() {
		var state = UpdateState()
		state.lastAttempt = now - UpdatePolicy.cooldown + 1
		#expect(!UpdatePolicy.shouldCheck(manual: false, enabled: true, inFlight: false, state: state, now: now))
		state.lastAttempt = now - UpdatePolicy.cooldown
		#expect(UpdatePolicy.shouldCheck(manual: false, enabled: true, inFlight: false, state: state, now: now))
	}

	@Test func manualChecksSkipTheCooldownButNotRateLimits() {
		var state = UpdateState()
		state.lastAttempt = now - 60
		#expect(UpdatePolicy.shouldCheck(manual: true, enabled: true, inFlight: false, state: state, now: now))
		state.rateLimitReset = now + 60
		#expect(!UpdatePolicy.shouldCheck(manual: true, enabled: true, inFlight: false, state: state, now: now))
		state.rateLimitReset = now
		#expect(UpdatePolicy.shouldCheck(manual: true, enabled: true, inFlight: false, state: state, now: now))
	}

	@Test func aLastAttemptInTheFutureIsEligibleOnce() {
		var state = UpdateState()
		state.lastAttempt = now + 10_000     // the user moved the clock back
		#expect(UpdatePolicy.shouldCheck(manual: false, enabled: true, inFlight: false, state: state, now: now))
	}

	// MARK: apply

	@Test func aSuccessfulResponseStoresTagEtagAndTimes() {
		let state = UpdatePolicy.apply(
			.ok(tag: "v0.2.0", url: releasesURL, etag: "\"abc\""),
			to: UpdateState(), now: now, currentVersion: "0.1.0")
		#expect(state.cachedTag == "v0.2.0")
		#expect(state.cachedURL == releasesURL)
		#expect(state.etag == "\"abc\"")
		#expect(state.lastAttempt == now)
		#expect(state.lastSuccess == now)
		#expect(state.rateLimitReset == nil)
	}

	@Test func notModifiedKeepsTheCachedReleaseAndRefreshesTheTimes() {
		var previous = UpdateState()
		previous.cachedTag = "v0.2.0"
		previous.cachedURL = releasesURL
		previous.etag = "\"abc\""
		let state = UpdatePolicy.apply(.notModified, to: previous, now: now, currentVersion: "0.1.0")
		#expect(state.cachedTag == "v0.2.0")
		#expect(state.etag == "\"abc\"")
		#expect(state.lastSuccess == now)
	}

	@Test func rateLimitingStoresTheResetAndDoesNotCountAsSuccess() {
		let state = UpdatePolicy.apply(.rateLimited(resetAt: now + 3600), to: UpdateState(), now: now, currentVersion: "0.1.0")
		#expect(state.rateLimitReset == now + 3600)
		#expect(state.lastAttempt == now)
		#expect(state.lastSuccess == nil)
	}

	@Test func aFailureStampsTheAttemptAndLeavesTheCacheAlone() {
		var previous = UpdateState()
		previous.cachedTag = "v0.2.0"
		let state = UpdatePolicy.apply(.failed(reason: "offline"), to: previous, now: now, currentVersion: "0.1.0")
		#expect(state.cachedTag == "v0.2.0")
		#expect(state.lastAttempt == now)
		#expect(state.lastSuccess == nil)
	}

	@Test func noReleasesClearsTheCache() {
		var previous = UpdateState()
		previous.cachedTag = "v0.2.0"
		previous.cachedURL = releasesURL
		let state = UpdatePolicy.apply(.noReleases, to: previous, now: now, currentVersion: "0.1.0")
		#expect(state.cachedTag == nil)
		#expect(state.cachedURL == nil)
	}

	@Test func aNewerReleaseClearsAnOlderDismissal() {
		var previous = UpdateState()
		previous.dismissedVersion = "0.2.0"
		let state = UpdatePolicy.apply(
			.ok(tag: "v0.3.0", url: releasesURL, etag: nil), to: previous, now: now, currentVersion: "0.1.0")
		#expect(state.dismissedVersion == nil)
	}

	@Test func rateLimitingWithoutAResetUsesTheFallbackWindow() {
		let state = UpdatePolicy.apply(.rateLimited(resetAt: nil), to: UpdateState(), now: now, currentVersion: "0.1.0")
		#expect(state.rateLimitReset == now + UpdatePolicy.cooldown / 24)
	}

	@Test func notModifiedWithNoCachedReleaseLeavesStateEmptyAndReportsNoReleases() {
		let state = UpdatePolicy.apply(.notModified, to: UpdateState(), now: now, currentVersion: "0.1.0")
		#expect(state.cachedTag == nil)
		#expect(state.cachedURL == nil)
		#expect(state.etag == nil)
		#expect(state.lastSuccess == now)
		#expect(UpdatePolicy.status(state: state, enabled: true, currentVersion: "0.1.0", now: now) == .noReleases)
	}

	// MARK: status

	@Test func offersOnlyStrictlyNewerStableVersions() {
		var state = UpdateState()
		state.cachedTag = "v0.2.0"
		state.cachedURL = releasesURL
		state.lastSuccess = now
		#expect(UpdatePolicy.status(state: state, enabled: true, currentVersion: "0.1.0", now: now)
			== .available(version: "0.2.0", url: releasesURL))
		#expect(UpdatePolicy.status(state: state, enabled: true, currentVersion: "0.2.0", now: now) == .current("0.2.0"))
		#expect(UpdatePolicy.status(state: state, enabled: true, currentVersion: "0.3.0", now: now) == .current("0.3.0"))
	}

	@Test func ignoresAnUnparseableOrPrereleaseTag() {
		var state = UpdateState()
		state.cachedTag = "v0.2.0-beta.1"
		state.cachedURL = releasesURL
		state.lastSuccess = now
		#expect(UpdatePolicy.status(state: state, enabled: true, currentVersion: "0.1.0", now: now) == .current("0.1.0"))
	}

	@Test func ignoresAReleaseUrlOutsideTheProjectsReleases() {
		var state = UpdateState()
		state.cachedTag = "v0.2.0"
		state.cachedURL = "https://evil.example.com/releases/v0.2.0"
		state.lastSuccess = now
		#expect(UpdatePolicy.status(state: state, enabled: true, currentVersion: "0.1.0", now: now) == .current("0.1.0"))
	}

	@Test func hidesADismissedVersionUntilANewerOneArrives() {
		var state = UpdateState()
		state.cachedTag = "v0.2.0"
		state.cachedURL = releasesURL
		state.lastSuccess = now
		state.dismissedVersion = "0.2.0"
		#expect(UpdatePolicy.status(state: state, enabled: true, currentVersion: "0.1.0", now: now) == .current("0.1.0"))
		state.cachedTag = "v0.3.0"
		#expect(UpdatePolicy.status(state: state, enabled: true, currentVersion: "0.1.0", now: now)
			== .available(version: "0.3.0", url: releasesURL))
	}

	@Test func anUnparseableDismissedVersionIsInert() {
		// Garbage in dismissedVersion should neither suppress an offer nor get cleared by a newer release.
		var state = UpdateState()
		state.cachedTag = "v0.2.0"
		state.cachedURL = releasesURL
		state.lastSuccess = now
		state.dismissedVersion = "not-a-version"
		#expect(UpdatePolicy.status(state: state, enabled: true, currentVersion: "0.1.0", now: now)
			== .available(version: "0.2.0", url: releasesURL))

		let applied = UpdatePolicy.apply(
			.ok(tag: "v0.3.0", url: releasesURL, etag: nil), to: state, now: now, currentVersion: "0.1.0")
		#expect(applied.dismissedVersion == "not-a-version")
	}

	@Test func reportsDisabledIdleRateLimitedAndNoReleases() {
		#expect(UpdatePolicy.status(state: UpdateState(), enabled: false, currentVersion: "0.1.0", now: now) == .disabled)
		#expect(UpdatePolicy.status(state: UpdateState(), enabled: true, currentVersion: "0.1.0", now: now) == .idle)
		var limited = UpdateState()
		limited.lastAttempt = now
		limited.rateLimitReset = now + 3600
		#expect(UpdatePolicy.status(state: limited, enabled: true, currentVersion: "0.1.0", now: now) == .failed(reason: "rate limited"))
		var empty = UpdateState()
		empty.lastSuccess = now
		#expect(UpdatePolicy.status(state: empty, enabled: true, currentVersion: "0.1.0", now: now) == .noReleases)
	}

	@Test func rateLimitedStatusExpiresAtTheResetTimeNotByCooldown() {
		// Regression: status used to compare the reset against lastAttempt instead of the clock, so it could
		// stay "rate limited" for up to a full cooldown after the limit had actually expired.
		let state = UpdatePolicy.apply(.rateLimited(resetAt: now + 3600), to: UpdateState(), now: now, currentVersion: "0.1.0")
		#expect(UpdatePolicy.status(state: state, enabled: true, currentVersion: "0.1.0", now: now + 60)
			== .failed(reason: "rate limited"))
		#expect(UpdatePolicy.status(state: state, enabled: true, currentVersion: "0.1.0", now: now + 7200)
			== .failed(reason: "couldn't reach GitHub"))
	}

	@Test func reportsCouldNotReachGitHubAfterAFailedAttemptWithNoPriorSuccess() {
		var state = UpdateState()
		state.lastAttempt = now
		#expect(UpdatePolicy.status(state: state, enabled: true, currentVersion: "0.1.0", now: now)
			== .failed(reason: "couldn't reach GitHub"))
	}

	// MARK: releaseURL

	@Test func acceptsOnlyProjectReleaseUrls() {
		#expect(UpdatePolicy.releaseURL(releasesURL) == releasesURL)
		#expect(UpdatePolicy.releaseURL("https://github.com/manustays/lean-battery/issues/1") == nil)
		#expect(UpdatePolicy.releaseURL("http://github.com/manustays/lean-battery/releases/tag/v1") == nil)
		#expect(UpdatePolicy.releaseURL("https://github.com/manustays/lean-battery-evil/releases/x") == nil)
		#expect(UpdatePolicy.releaseURL("") == nil)
	}
}
