import Foundation
import AVFoundation
import CoreBluetooth
import MultipeerConnectivity
import UserNotifications

/// Triggers the iOS permission prompts during onboarding, one at a time, after we've
/// explained *why* each is needed (the explanation-first pattern). Each `request…` method
/// fires the real system prompt and resolves once the user has responded (or, for Local
/// Network — which has no decision callback — after a short grace period).
@MainActor
final class PermissionPrimer: NSObject, ObservableObject {

    // MARK: - Bluetooth

    private var central: CBCentralManager?
    private var bluetoothContinuation: CheckedContinuation<Void, Never>?

    /// Instantiating a `CBCentralManager` surfaces the system Bluetooth prompt on first use.
    func requestBluetooth() async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            bluetoothContinuation = cont
            central = CBCentralManager(delegate: self, queue: .main)
            // Safety net: resolve even if the state callback never lands.
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
                self?.resolveBluetooth()
            }
        }
    }

    private func resolveBluetooth() {
        bluetoothContinuation?.resume()
        bluetoothContinuation = nil
        central = nil   // a fresh manager is created for real use by BLEMeshLink
    }

    // MARK: - Microphone

    func requestMicrophone() async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            AVAudioApplication.requestRecordPermission { _ in cont.resume() }
        }
    }

    // MARK: - Notifications

    func requestNotifications() async {
        _ = try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge])
    }

    // MARK: - Camera

    func requestCamera() async {
        _ = await AVCaptureDevice.requestAccess(for: .video)
    }

    // MARK: - Local Network (Wi-Fi / device discovery)

    private var primerAdvertiser: MCNearbyServiceAdvertiser?
    private var primerBrowser: MCNearbyServiceBrowser?

    /// There is no direct API to request Local Network access — the prompt only appears when
    /// an app actually uses Bonjour. So we briefly start a throwaway Multipeer advertiser +
    /// browser (matching our Info.plist Bonjour service) to surface it, then tear it down.
    /// The decision has no callback, so we proceed after a short grace period regardless.
    func requestLocalNetwork() async {
        let peer = MCPeerID(displayName: "RT-primer")
        let advertiser = MCNearbyServiceAdvertiser(peer: peer, discoveryInfo: nil,
                                                   serviceType: "rogerthat-v1")
        let browser = MCNearbyServiceBrowser(peer: peer, serviceType: "rogerthat-v1")
        primerAdvertiser = advertiser
        primerBrowser = browser
        advertiser.startAdvertisingPeer()
        browser.startBrowsingForPeers()

        try? await Task.sleep(nanoseconds: 2_500_000_000)

        advertiser.stopAdvertisingPeer()
        browser.stopBrowsingForPeers()
        primerAdvertiser = nil
        primerBrowser = nil
    }
}

// MARK: - CBCentralManagerDelegate

extension PermissionPrimer: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        // First state callback means the user has answered the prompt (or it was already set).
        Task { @MainActor in self.resolveBluetooth() }
    }
}
