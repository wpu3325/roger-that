import Foundation
import CoreBluetooth
import RogerThatCore

/// Roger That BLE service and characteristic UUIDs.
private let serviceUUID       = CBUUID(string: "6E400001-B5A3-F393-E0A9-E50E24DCCA9E")
private let txCharUUID        = CBUUID(string: "6E400002-B5A3-F393-E0A9-E50E24DCCA9E")
private let rxCharUUID        = CBUUID(string: "6E400003-B5A3-F393-E0A9-E50E24DCCA9E")

/// Maximum BLE ATT payload (practical limit with L2CAP not used).
private let maxPacketSize = 512

/// BLE-based mesh link: acts as both peripheral and central simultaneously.
///
/// Carries PRESENCE and TEXT. Not used for VOICE (Multipeer takes that role).
/// HUMAN: BLE background operation requires bluetooth-central + bluetooth-peripheral background modes
/// in Info.plist and a matching entitlement. See RUN_ON_DEVICE.md.
final class BLEMeshLink: NSObject, Link {
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
                peripheral?.respond(to: pendingReads[central] ?? CBATTRequest(), withResult: .success)
                rxChar.map { peripheralManager?.updateValue(data, for: $0, onSubscribedCentrals: [central]) }
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
    private var peripheral: CBPeripheral?

    private var connectedCentrals: [PeerHandle: CBCentral] = [:]
    private var connectedPeripherals: [PeerHandle: CBPeripheral] = [:]
    private var peripheralTXChars: [PeerHandle: CBCharacteristic] = [:]
    private var pendingReads: [CBCentral: CBATTRequest] = [:]

    private var onReceive: PacketReceiver?
    private var onPeerEvent: PeerEventHandler?

    init(channelIDHash: UInt32) {
        self.channelIDHash = channelIDHash
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
        peripheralManager?.add(service)
        peripheralManager?.startAdvertising([
            CBAdvertisementDataServiceUUIDsKey: [serviceUUID],
            CBAdvertisementDataLocalNameKey: "RogerThat-\(channelIDHash)"
        ])
    }

    func peripheralManager(_ p: CBPeripheralManager, didAdd service: CBService, error: Error?) {}

    func peripheralManager(_ p: CBPeripheralManager, central: CBCentral,
                           didSubscribeTo characteristic: CBCharacteristic) {
        let handle = PeerHandle("central-\(central.identifier)")
        lock.withLock { connectedCentrals[handle] = central }
        lock.withLock { onPeerEvent }?(handle, .connected)
    }

    func peripheralManager(_ p: CBPeripheralManager, central: CBCentral,
                           didUnsubscribeFrom characteristic: CBCharacteristic) {
        let handle = PeerHandle("central-\(central.identifier)")
        lock.withLock { connectedCentrals.removeValue(forKey: handle) }
        lock.withLock { onPeerEvent }?(handle, .disconnected)
    }

    func peripheralManager(_ p: CBPeripheralManager,
                           didReceiveWrite requests: [CBATTRequest]) {
        for req in requests {
            if let data = req.value {
                let sender = PeerHandle("central-\(req.central.identifier)")
                lock.withLock { onReceive }?(data, sender)
            }
        }
        p.respond(to: requests[0], withResult: .success)
    }

    func peripheralManagerDidRestoreState(_ peripheral: CBPeripheralManager, restoreDict: [String: Any]) {
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
        // Only connect to devices advertising our channel (name prefix match).
        if let name = advertisementData[CBAdvertisementDataLocalNameKey] as? String,
           name.hasPrefix("RogerThat-\(channelIDHash)") {
            c.connect(peripheral, options: nil)
        }
    }

    func centralManager(_ c: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.delegate = self
        peripheral.discoverServices([serviceUUID])
        self.peripheral = peripheral
    }

    func centralManager(_ c: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral,
                        error: Error?) {
        let handle = PeerHandle("peripheral-\(peripheral.identifier)")
        lock.withLock {
            connectedPeripherals.removeValue(forKey: handle)
            peripheralTXChars.removeValue(forKey: handle)
        }
        lock.withLock { onPeerEvent }?(handle, .disconnected)
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
                lock.withLock { onPeerEvent }?(handle, .connected)
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
        lock.withLock { onReceive }?(data, handle)
    }
}
