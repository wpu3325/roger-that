import Foundation
import SwiftUI
import RogerThatCore

/// Observable state for the entire app. Lives on the main actor.
@MainActor
final class AppState: ObservableObject {

    // MARK: - Published state

    @Published var session: SessionManager?
    @Published var channel: Channel?
    @Published var members: [Member] = []
    @Published var messages: [ChatMessage] = []
    @Published var floorState: FloorState = .idle

    // MARK: - Dependencies (set up on join)

    private(set) var pttController: PushToTalkController?
    private var bleLink: BLEMeshLink?
    private var voiceLink: MultipeerVoiceLink?
    private var audioEngine: AudioEngineIO?

    /// This device's persistent random ID.
    let localID: UInt32 = {
        let key = "rogerthat.deviceID"
        if let stored = UserDefaults.standard.object(forKey: key) as? UInt32 { return stored }
        let id = UInt32.random(in: .min ... .max)
        UserDefaults.standard.set(id, forKey: key)
        return id
    }()

    // MARK: - Channel lifecycle

    func join(channel: Channel, displayName: String) {
        let ble = BLEMeshLink(channelIDHash: channel.channelIDHash)
        let voice = MultipeerVoiceLink(channelIDHash: channel.channelIDHash)
        let mgr = SessionManager(
            channel: channel,
            localID: localID,
            displayName: displayName,
            link: ble
        )

        mgr.setMessageHandler { [weak self] msg in
            guard let self else { return }
            Task { @MainActor in
                let name = self.members.first(where: { $0.id == msg.packet.senderID })?.displayName
                    ?? "Peer"
                if msg.packet.type == .text,
                   let text = String(data: msg.plaintext, encoding: .utf8) {
                    self.messages.append(ChatMessage(
                        senderName: name,
                        text: text,
                        timestamp: Date(),
                        isLocal: false
                    ))
                }
            }
        }

        let ptt = PushToTalkController(
            localID: localID,
            voiceLink: voice,
            audioEngine: AudioEngineIO()
        )

        ptt.onFloorStateChange = { [weak self] state in
            Task { @MainActor in self?.floorState = state }
        }

        self.bleLink = ble
        self.voiceLink = voice
        self.session = mgr
        self.channel = channel
        self.pttController = ptt

        ble.start()
        mgr.start()

        // Poll presence/roster on a timer.
        scheduleRosterRefresh(mgr: mgr)
    }

    func leaveChannel() {
        session?.stop()
        bleLink?.stop()
        pttController?.stopTalking()
        session = nil
        channel = nil
        members = []
        messages = []
        floorState = .idle
        pttController = nil
        bleLink = nil
        voiceLink = nil
        rosterTimer?.cancel()
        rosterTimer = nil
    }

    func sendText(_ text: String) {
        guard let session else { return }
        session.sendText(text)
        messages.append(ChatMessage(
            senderName: "You",
            text: text,
            timestamp: Date(),
            isLocal: true
        ))
    }

    // MARK: - Roster refresh

    private var rosterTimer: DispatchSourceTimer?

    private func scheduleRosterRefresh(mgr: SessionManager) {
        let t = DispatchSource.makeTimerSource(queue: .main)
        t.schedule(deadline: .now(), repeating: 5)
        t.setEventHandler { [weak self, weak mgr] in
            guard let self, let mgr else { return }
            Task { @MainActor in
                self.members = mgr.activeMembers
                self.floorState = mgr.floorState
            }
        }
        t.resume()
        rosterTimer = t
    }
}
