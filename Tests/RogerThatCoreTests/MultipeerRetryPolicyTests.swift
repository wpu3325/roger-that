import Testing
import Foundation
@testable import RogerThatCore

@Suite("MultipeerRetryPolicy")
struct MultipeerRetryPolicyTests {

    private let policy = MultipeerRetryPolicy(baseDelay: 2, maxDelay: 16, nonInviterFallbackAfter: 20)

    // MARK: - Backoff

    @Test func firstAttemptIsImmediate() {
        #expect(policy.backoff(forAttempt: 0) == 0)
    }

    @Test func backoffDoublesThenCaps() {
        #expect(policy.backoff(forAttempt: 1) == 2)
        #expect(policy.backoff(forAttempt: 2) == 4)
        #expect(policy.backoff(forAttempt: 3) == 8)
        #expect(policy.backoff(forAttempt: 4) == 16)
        #expect(policy.backoff(forAttempt: 5) == 16)   // capped
        #expect(policy.backoff(forAttempt: 99) == 16)  // stays capped
    }

    // MARK: - Primary inviter

    @Test func primaryInvitesImmediatelyWhenNeverTried() {
        let now = Date()
        #expect(policy.shouldInvite(isPrimaryInviter: true, attempts: 0,
                                    lastInviteAt: nil, firstSeen: now, now: now))
    }

    @Test func primaryWaitsForBackoffBetweenAttempts() {
        let seen = Date(timeIntervalSince1970: 0)
        let last = Date(timeIntervalSince1970: 100)
        // attempts=1 → backoff 2s. 1s later: too soon. 2s later: allowed.
        #expect(!policy.shouldInvite(isPrimaryInviter: true, attempts: 1, lastInviteAt: last,
                                     firstSeen: seen, now: last.addingTimeInterval(1)))
        #expect(policy.shouldInvite(isPrimaryInviter: true, attempts: 1, lastInviteAt: last,
                                    firstSeen: seen, now: last.addingTimeInterval(2)))
    }

    // MARK: - Non-inviter fallback

    @Test func nonInviterStaysQuietBeforeFallbackWindow() {
        let seen = Date(timeIntervalSince1970: 0)
        // 19s after discovery (< 20s window) and never invited → must NOT invite.
        #expect(!policy.shouldInvite(isPrimaryInviter: false, attempts: 0, lastInviteAt: nil,
                                     firstSeen: seen, now: seen.addingTimeInterval(19)))
    }

    @Test func nonInviterStepsInAfterFallbackWindow() {
        let seen = Date(timeIntervalSince1970: 0)
        // 20s after discovery, never invited → fallback fires.
        #expect(policy.shouldInvite(isPrimaryInviter: false, attempts: 0, lastInviteAt: nil,
                                    firstSeen: seen, now: seen.addingTimeInterval(20)))
    }

    @Test func nonInviterStillBacksOffAfterFallback() {
        let seen = Date(timeIntervalSince1970: 0)
        let last = seen.addingTimeInterval(20)   // first fallback invite at t=20
        // attempts=1 → 2s backoff. t=21 too soon; t=22 allowed (and past the window).
        #expect(!policy.shouldInvite(isPrimaryInviter: false, attempts: 1, lastInviteAt: last,
                                     firstSeen: seen, now: seen.addingTimeInterval(21)))
        #expect(policy.shouldInvite(isPrimaryInviter: false, attempts: 1, lastInviteAt: last,
                                    firstSeen: seen, now: seen.addingTimeInterval(22)))
    }
}
