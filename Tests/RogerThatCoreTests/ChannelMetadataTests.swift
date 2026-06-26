import Testing
import Foundation
@testable import RogerThatCore

@Suite("ChannelMetadata")
struct ChannelMetadataTests {

    @Test func codableRoundTrip() throws {
        let original = ChannelMetadata(channelID: "abc-123", name: "Ski Trip",
                                       kind: .password, joinedAt: Date(timeIntervalSince1970: 1_700_000_000))
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ChannelMetadata.self, from: data)
        #expect(decoded == original)
    }

    @Test func listRoundTripPreservesOrder() throws {
        let list = [
            ChannelMetadata(channelID: "1", name: "A", kind: .random, joinedAt: Date(timeIntervalSince1970: 1)),
            ChannelMetadata(channelID: "2", name: "B", kind: .password, joinedAt: Date(timeIntervalSince1970: 2)),
            ChannelMetadata(channelID: "3", name: "C", kind: .random, joinedAt: Date(timeIntervalSince1970: 3)),
        ]
        let data = try JSONEncoder().encode(list)
        let decoded = try JSONDecoder().decode([ChannelMetadata].self, from: data)
        #expect(decoded.map(\.channelID) == ["1", "2", "3"])
        #expect(decoded == list)
    }

    @Test func kindRawValuesAreStable() {
        // These strings are persisted — they must not drift.
        #expect(ChannelMetadata.Kind.random.rawValue == "random")
        #expect(ChannelMetadata.Kind.password.rawValue == "password")
    }

    @Test func identifiableUsesChannelID() {
        let meta = ChannelMetadata(channelID: "xyz", name: "n", kind: .random, joinedAt: Date())
        #expect(meta.id == "xyz")
    }

    @Test func defaultsToNotArchived() {
        let meta = ChannelMetadata(channelID: "x", name: "n", kind: .random, joinedAt: Date())
        #expect(meta.isArchived == false)
    }

    @Test func legacyJSONWithoutIsArchivedDecodesToFalse() throws {
        // Channels saved before `isArchived` existed must still load.
        let legacy = #"{"channelID":"abc","name":"Test","kind":"random","joinedAt":0}"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(ChannelMetadata.self, from: legacy)
        #expect(decoded.isArchived == false)
        #expect(decoded.name == "Test")
    }

    @Test func archivedFlagRoundTrips() throws {
        let original = ChannelMetadata(channelID: "x", name: "Y", kind: .password,
                                       joinedAt: Date(timeIntervalSince1970: 1), isArchived: true)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ChannelMetadata.self, from: data)
        #expect(decoded.isArchived == true)
        #expect(decoded == original)
    }
}
