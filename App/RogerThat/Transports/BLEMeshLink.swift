import Foundation
import CoreBluetooth
import RogerThatCore

/// Roger That BLE service and characteristic UUIDs.
private nonisolated(unsafe) let serviceUUID  = CBUUID(string: "6E400001-B5A3-F393-E0A9-E50E24DCCA9E")
private nonisolated(unsafe) let txCharUUID   = CBUUID(string: "6E400002-B5A3-F393-E0A9-E50E24DCCA9E")
private nonisolated(unsafe) let rxCharUUID   = CBUUID(string: "6E400003-B5A3-F393-E0A9-E50E24DCCA9E")

/// Maximum BLE ATT payload (practical limit with L2CAP not used).
private let maxPacketSize = 512

/// BLE-based mesh link: acts as both peripheral and central simultaneously.
///
/// Carries PRESENCE and TEXT. Not used for VOICE (Multipeer takes that role).
/// HUMAN: BLE background operation requires bluetooth-central + bluetooth-peripheral background modes
/// in Info.plist and a matching entitlement. See RUN_ON_DEVICE.md.
final class BLEMeshLink: NSObject, Link, @unchecked Sendable {
    // MARK: - Link protocol

    var peers: [PeerHandle] {
        lock.withLock { Array(connectedCentrals.keys) + Array(connectedPeripherals.keys) }
    }

    func setHandlers(onReceive: @escaping PacketReceiver, onPeerEvent: @escaping PeerEventHandler) {
        lock.withLock {
            self.onReceive = onReceive
            self.onPeerEvent = onPeerEvent
        }
    }

    func send(_ data: Data, to peer: PeerHandle) {
        lock.withLock {
            if let central = connectedCentrals[peer] {
                if let char = rxChar { peripheralManager?.updateValue(data, for: char, onSubscribedCentrals: [central]) }
            } else if let p = connectedPeripherals[peer] {
                if let tx = peripheralTXChars[peer] {
                    p.writeValue(data, for: tx, type: .withoutResponse)
                }
            }
        }
    }

    func broadcast(_ data: Data) {
        for peer in peers { send(data, to: peer) }
    }

    func start() {
        peripheralManager = CBPeripheralManager(delegate: self, queue: bleQueue, options: [
            CBPeripheralManagerOptionRestoreIdentifierKey: "rogerthat-peripheral"
        ])
        centralManager = CBCentralManager(delegate: self, queue: bleQueue, options: [
            CBCentralManagerScanOptionAllowDuplicatesKey: false
        ])
    }

    func stop() {
        peripheralManager?.stopAdvertising()
        peripheralManager?.removeAllServices()
        centralManager?.stopScan()
    }

    // MARK: - Internal

    let channelIDHash: UInt32
    private let lock = NSLock()
    private let bleQueue = DispatchQueue(label: "com.rogerthat.ble", qos: .utility)

    private var peripheralManager: CBPeripheralManager?
    private var centralManager: CBCentralManager?
    private var rxChar: CBMutableCharacteristic?
    /// Strong references to peripherals we are connecting to / connected with.
    /// CoreBluetooth does NOT retain these for us; without this the connection
    /// is silently dropped before it completes.
    private var discoveredPeripherals: [UUID: CBPeripheral] = [:]

    private var connectedCentrals: [PeerHandle: CBCentral] = [:]
    private var connectedPeripherals: [PeerHandle: CBPeripheral] = [:]
    private var peripheralTXChars: [PeerHandle: CBCharacteristic] = [:]
    private var pendingReads: [CBCentral: CBATTRequest] = [:]

    private var onReceive: PacketReceiver?
    private var onPeerEvent: PeerEventHandler?

    init(channelIDHash: UInt32) {
        self.channelIDHash = channelIDHash
    }

    private func emit(_ data: Data, from peer: PeerHandle) {
        lock.withLock { onReceive }?(data, peer)
    }

    private func emit(_ peer: PeerHandle, _ event: PeerEvent) {
        lock.withLock { onPeerEvent }?(peer, event)
    }
}

// MARK: - CBPeripheralManagerDelegate

extension BLEMeshLink: CBPeripheralManagerDelegate {
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        guard peripheral.state == .poweredOn else { return }
        setupPeripheral()
    }

    private func setupPeripheral() {
        let rx = CBMutableCharacteristic(
            type: rxCharUUID,
            properties: [.notify, .write, .writeWithoutResponse],
            value: nil,
            permissions: [.readable, .writeable]
        )
        let service = CBMutableService(type: serviceUUID, primary: true)
        service.characteristics = [rx]
        rxChar = rx
        peripheralManager?.removeAllServices()
        peripheralManager?.add(service)
        // Advertising is started in didAdd, once the service is actually registered —
        // otherwise a central can connect and find an empty service (no characteristic
        // to subscribe to), so presence never flows.
    }

    func peripheralManager(_ p: CBPeripheralManager, didAdd service: CBService, error: Error?) {
        guard error == nil else { return }
        p.startAdvertising([
            CBAdvertisementDataServiceUUIDsKey: [serviceUUID],
            CBAdvertisementDataLocalNameKey: "RogerThat-\(channelIDHash)"
        ])
    }

    func peripheralManager(_ p: CBPeripheralManager, central: CBCentral,
                           didSubscribeTo characteristic: CBCharacteristic) {
        let handle = PeerHandle("central-\(central.identifier)")
        lock.withLock { connectedCentrals[handle] = central }
        emit(handle, .connected)
    }

    func peripheralManager(_ p: CBPeripheralManager, central: CBCentral,
                           didUnsubscribeFrom characteristic: CBCharacteristic) {
        let handle = PeerHandle("central-\(central.identifier)")
        lock.withLock { connectedCentrals[handle] = nil }
        emit(handle, .disconnected)
    }

    func peripheralManager(_ p: CBPeripheralManager,
                           didReceiveWrite requests: [CBATTRequest]) {
        for req in requests {
            if let data = req.value {
                let sender = PeerHandle("central-\(req.central.identifier)")
                emit(data, from: sender)
            }
        }
        p.respond(to: requests[0], withResult: .success)
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, willRestoreState dict: [String: Any]) {
        // Re-advertise after background restoration.
        if peripheral.state == .poweredOn { setupPeripheral() }
    }
}

// MARK: - CBCentralManagerDelegate

extension BLEMeshLink: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        guard central.state == .poweredOn else { return }
        central.scanForPeripherals(withServices: [serviceUUID], options: nil)
    }

    func centralManager(_ c: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi: NSNumber) {
        // Any peripheral advertising our service UUID is a RogerThat node. We do NOT
        // gate on the advertised local name — iOS frequently drops it from the 31-byte
        // advertisement packet, which previously blocked discovery entirely. Channel
        // isolation is enforced at the packet layer (channelIDHash + body encryption).
        let id = peripheral.identifier
        let alreadyKnown: Bool = lock.withLock {
            if discoveredPeripherals[id] != nil { return true }
            discoveredPeripherals[id] = peripheral   // retain before connecting
            return false
        }
        guard !alreadyKnown else { return }
        peripheral.delegate = self
        c.connect(peripheral, options: nil)
    }

    func centralManager(_ c: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.delegate = self
        peripheral.discoverServices([serviceUUID])
    }

    func centralManager(_ c: CBCentralManager, didFailToConnect peripheral: CBPeripheral,
                        error: Error?) {
        lock.withLock { discoveredPeripherals[peripheral.identifier] = nil }
        c.scanForPeripherals(withServices: [serviceUUID], options: nil)
    }

    func centralManager(_ c: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral,
                        error: Error?) {
        let handle = PeerHandle("peripheral-\(peripheral.identifier)")
        lock.withLock {
            connectedPeripherals.removeValue(forKey: handle)
            peripheralTXChars.removeValue(forKey: handle)
            discoveredPeripherals[peripheral.identifier] = nil
        }
        emit(handle, .disconnected)
        // Re-scan after disconnect.
        c.scanForPeripherals(withServices: [serviceUUID], options: nil)
    }
}

// MARK: - CBPeripheralDelegate

extension BLEMeshLink: CBPeripheralDelegate {
    func peripheral(_ p: CBPeripheral, didDiscoverServices error: Error?) {
        p.services?.filter { $0.uuid == serviceUUID }.forEach {
            p.discoverCharacteristics([txCharUUID, rxCharUUID], for: $0)
        }
    }

    func peripheral(_ p: CBPeripheral, didDiscoverCharacteristicsFor service: CBService,
                    error: Error?) {
        let handle = PeerHandle("peripheral-\(p.identifier)")
        for ch in service.characteristics ?? [] {
            if ch.uuid == txCharUUID {
                lock.withLock { peripheralTXChars[handle] = ch }
                lock.withLock { connectedPeripherals[handle] = p }
                emit(handle, .connected)
            }
            if ch.uuid == rxCharUUID {
                p.setNotifyValue(true, for: ch)
            }
        }
    }

    func peripheral(_ p: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic,
                    error: Error?) {
        guard let data = characteristic.value else { return }
        let handle = PeerHandle("peripheral-\(p.identifier)")
        emit(data, from: handle)
    }
}
