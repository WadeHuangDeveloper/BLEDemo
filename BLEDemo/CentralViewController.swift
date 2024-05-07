//
//  CentralViewController.swift
//  BLEDemo
//
//  Created by Huei-Der Huang on 2024/5/1.
//

import UIKit
import CoreBluetooth
import os

class CentralViewController: UIViewController {
    
    var centralManager: CBCentralManager!
    var discoveredPeripheral: CBPeripheral?
    var transferCharacteristic: CBCharacteristic?
    var dataBuffer: Data = Data()

    @IBOutlet weak var outputTextView: UITextView!
    @IBOutlet weak var scanSwitch: UISwitch!
    
    override func viewDidLoad() {
        super.viewDidLoad()

        // Do any additional setup after loading the view.
        initializeProperties()
        setupUI()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        centralManager.stopScan()
        dataBuffer.removeAll()
    }
    
    @IBAction func scan(_ sender: Any) {
        if scanSwitch.isOn {
            os_log("Start scanning..")
            centralManager.scanForPeripherals(withServices: nil)
        } else {
            os_log("Stop scanning..")
            centralManager.stopScan()
        }
    }
    
    // MARK: - Methods
    
    private func initializeProperties() {
        centralManager = CBCentralManager(
            delegate: self,
            queue: nil,
            options: nil)
        discoveredPeripheral = nil
        transferCharacteristic = nil
        dataBuffer = Data()
    }
    
    private func setupUI() {
        outputTextView.text = ""
        outputTextView.isEditable = false
        scanSwitch.isOn = false
    }
    
    /*
     * We will first check if we are already connected to our counterpart
     * Otherwise, scan for peripherals - specifically for our service's 128bit CBUUID
     */
    private func retrievePeripheral() {
        let connectedPeripherals = centralManager.retrieveConnectedPeripherals(withServices: [TransferService.serviceUUID])
        
        if let lastConnectedPeripheral = connectedPeripherals.last {
            os_log("Connecting to peripheral %@", lastConnectedPeripheral)
            centralManager.connect(lastConnectedPeripheral, options: nil)
        } else {
            // Scan for new peripherals
            centralManager.scanForPeripherals(withServices: [TransferService.serviceUUID], options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        }
    }
    
    /*
     *  Call this when something goes wrong
     */
    private func cleanup() {
        // Don't do anything if connecting
        guard let discoveredPeripheral = discoveredPeripheral,
              discoveredPeripheral.state == .connected else { return }
        
        for service in (discoveredPeripheral.services ?? [] as [CBService]) {
            for characteristic in (service.characteristics ?? [] as [CBCharacteristic]) {
                if characteristic.uuid == TransferService.characteristicUUID && characteristic.isNotifying {
                    // It is notifying, so unsubstribe
                    discoveredPeripheral.setNotifyValue(false, for: characteristic)
                    
                    // Connecting but unsubstribe, so disconnect
                    centralManager.cancelPeripheralConnection(discoveredPeripheral)
                }
            }
        }
    }
    
    private func writeData(_ data: Data) {
        guard !data.isEmpty,
              let discoveredPeripheral = discoveredPeripheral,
              discoveredPeripheral.state == .connected,
              let transferCharacteristic = transferCharacteristic else { return }
        
        discoveredPeripheral.writeValue(data, for: transferCharacteristic, type: .withoutResponse)
    }
    
    private func readData(_ data: Data) {
        guard let dataString = String(data: data, encoding: .utf8) else { return }
        
        os_log("Read %d bytes: %s", data.count, dataString)
        
        // Custom protocol defines that the end of package is a byte '0xFF'.
        if data == Data([0xFF]) {
            parseDataBuffer()
        } else {
            dataBuffer.append(data)
        }
    }
    
    private func parseDataBuffer() {
        guard let message = String(data: dataBuffer, encoding: .utf8) else { return }
        
        // Get completed messages and update UI on main thread
        DispatchQueue.main.async {
            self.outputTextView.text = "\(message)\n"
        }
    }
}

extension CentralViewController: CBCentralManagerDelegate {
    
    /*
     *  centralManagerDidUpdateState is a required protocol method.
     *  Usually, you'd check for other states to make sure the current device supports LE, is powered on, etc.
     *  In this instance, we're just using it to wait for CBCentralManagerStatePoweredOn, which indicates
     *  the Central is ready to be used.
     */
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            os_log("CBManager is powered on")
            // Retrieve peripheral or scan for peripherals
            retrievePeripheral()
        case .poweredOff:
            os_log("CBManager is powered ooff")
        case .resetting:
            os_log("CBManager is resetting")
        case .unauthorized:
            os_log("CBManager is unauthorized")
        case .unknown:
            os_log("CBManager state is unknown")
        case .unsupported:
            os_log("Bluetooth is not supported on this device")
        @unknown default:
            os_log("Unexpected state occured")
        }
    }
    
    /*
     *  This callback comes whenever a peripheral that is advertising the transfer serviceUUID is discovered.
     *  We check the RSSI, to make sure it's close enough that we're interested in it, and if it is,
     *  we start the connection process
     */
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        // Reject if the signal strength is too low to attempt data transfer.
        guard RSSI.intValue >= -50 else {
            os_log("Discovered periperal is not in expected range, at %d", RSSI.intValue)
            return
        }
        
        os_log("Discovered %s at %d", String(describing: peripheral.name), RSSI.intValue)
        
        // Never seen this before
        if discoveredPeripheral == nil {
            // And finally, connect to the peripheral.
            os_log("Connecting to perhiperal %@", peripheral)
            centralManager.connect(peripheral, options: nil)
        }
    }
    
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        os_log("Failed to connect to %@. %s", peripheral, String(describing: error))
        cleanup()
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        os_log("Peripheral Connected")
        
        // Save a local copy of the peripheral
        discoveredPeripheral = peripheral
        
        // Stop scanning
        centralManager.stopScan()
        os_log("Scanning stopped")
        
        // Make sure we get the discovery callbacks
        peripheral.delegate = self
        
        // Search only for services that match our UUID
        peripheral.discoverServices([TransferService.serviceUUID])
    }
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        os_log("Perhiperal Disconnected")
        
        discoveredPeripheral = nil
    }
}

extension CentralViewController: CBPeripheralDelegate {
    /*
     *  The peripheral letting us know when services have been invalidated.
     */
    func peripheral(_ peripheral: CBPeripheral, didModifyServices invalidatedServices: [CBService]) {
        for service in invalidatedServices where service.uuid == TransferService.serviceUUID {
            os_log("Transfer service is invalidated - rediscover services")
            peripheral.discoverServices([TransferService.serviceUUID])
        }
    }
    
    /*
     *  The Transfer Service was discovered
     */
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error = error {
            os_log("Error discovering services: %s", error.localizedDescription)
            cleanup()
            return
        }
        
        // Discover the characteristic we want...
        // Loop through the newly filled peripheral.services array, just in case there's more than one.
        guard let peripheralServices = peripheral.services else { return }
        for service in  peripheralServices {
            peripheral.discoverCharacteristics([TransferService.characteristicUUID], for: service)
        }
    }
    
    /*
     *  The Transfer characteristic was discovered.
     *  Once this has been found, we want to subscribe to it, which lets the peripheral know we want the data it contains
     */
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error = error {
            os_log("Error discovering characteristics: %s", error.localizedDescription)
            cleanup()
            return
        }
        
        // Again, we loop through the array, just in case and check if it's the right one
        guard let serviceCharacteristics = service.characteristics else { return }
        for characteristic in serviceCharacteristics where characteristic.uuid == TransferService.characteristicUUID {
            // If it is, subscribe to it
            os_log("Transfer characteristic found")
            transferCharacteristic = characteristic
            peripheral.setNotifyValue(true, for: characteristic)
        }
    }
    
    /*
     *   This callback lets us know more data has arrived via notification on the characteristic
     */
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            os_log("Error discovering characteristics: %s", error.localizedDescription)
            cleanup()
            return
        }
        
        guard let data = characteristic.value else { return }
        
        // Maybe peripheral would send data by multiple callbacks, so handling by a buffer and parsing data in buffer
        readData(data)
    }
    
    /*
     *  The peripheral letting us know whether our subscribe/unsubscribe happened or not
     */
    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            os_log("Error changing notification state: %s", error.localizedDescription)
            return
        }
        
        // Exit if it's not the transfer characteristic
        guard characteristic.uuid == TransferService.characteristicUUID else { return }
        
        if characteristic.isNotifying {
            // Notification has started
            os_log("Notification began on %@", characteristic)
            // Send messages to peripheral
            let dataToWrite = Data("Hello peripheral".utf8)
            writeData(dataToWrite)
        } else {
            // Notification has stopped, so disconnect from the peripheral
            os_log("Notification stopped on %@. Disconnecting", characteristic)
            cleanup()
        }
    }
}
