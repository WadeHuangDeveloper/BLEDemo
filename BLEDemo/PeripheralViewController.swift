//
//  PeripheralViewController.swift
//  BLEDemo
//
//  Created by Huei-Der Huang on 2024/5/1.
//

import UIKit
import CoreBluetooth
import os

class PeripheralViewController: UIViewController {
    var peripheralManager: CBPeripheralManager!
    var transferCharacteristic: CBMutableCharacteristic?
    var dataBuffer: Data = Data()
    var connectedCentral: CBCentral?

    @IBOutlet weak var outputTextView: UITextView!
    @IBOutlet weak var advertisingSwitch: UISwitch!
    
    override func viewDidLoad() {
        super.viewDidLoad()

        initializeProperties()
        setupUI()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        peripheralManager.stopAdvertising()
    }
    
    @IBAction func advertise(_ sender: Any) {
        if advertisingSwitch.isOn {
            os_log("Start advertising")
            peripheralManager.startAdvertising([CBAdvertisementDataServiceUUIDsKey: TransferService.serviceUUID])
        } else {
            os_log("Stop advertising")
            peripheralManager.stopAdvertising()
        }
    }
    
    // MARK: - Methods
    
    private func initializeProperties() {
        peripheralManager = CBPeripheralManager(
            delegate: self,
            queue: nil,
            options: [CBPeripheralManagerOptionShowPowerAlertKey: true])
    }
    
    private func setupUI() {
        outputTextView.text = ""
        outputTextView.isEditable = false
        advertisingSwitch.isOn = false
    }
    
    /*
     * Build the service
     */
    private func setupPeripheral() {
        
        // Create CBMutableCharacteristic.
        let transferCharacteristic = CBMutableCharacteristic(
            type: TransferService.characteristicUUID,
            properties: [.notify, .writeWithoutResponse],
            value: nil,
            permissions: [.readable, .writeable])
        
        // Create a service from the characteristic.
        let transferService = CBMutableService(type: TransferService.serviceUUID, primary: true)
        
        // Add the characteristic to the service.
        transferService.characteristics = [transferCharacteristic]
        
        // And add it to the peripheral manager.
        peripheralManager.add(transferService)
        
        // Save the characteristic to the local.
        self.transferCharacteristic = transferCharacteristic
    }
    
    private func sendData(_ data: Data) {
        guard !data.isEmpty,
              let connectedCentral = connectedCentral,
              let transferCharacteristic = transferCharacteristic else { return }
        
        // Send message to central
        peripheralManager.updateValue(data, for: transferCharacteristic, onSubscribedCentrals: [connectedCentral])
    }
}

extension PeripheralViewController: CBPeripheralManagerDelegate {
    
    /*
     *  Required protocol method.  A full app should take care of all the possible states,
     *  but we're just waiting for to know when the CBPeripheralManager is ready
     *
     *  Starting from iOS 13.0, if the state is CBManagerStateUnauthorized, you
     *  are also required to check for the authorization state of the peripheral to ensure that
     *  your app is allowed to use bluetooth
     */
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        switch peripheral.state {
        case .poweredOn:
            os_log("CBManager is powered on")
            // Setup peripheral with the service and characteristic
            setupPeripheral()
        case .poweredOff:
            os_log("CBManager is powered off")
        case .resetting:
            os_log("CBManager is resetting")
        case .unauthorized:
            os_log("CBManager is unauthorized")
        case .unknown:
            os_log("CBManager is unknown")
        case .unsupported:
            os_log("Bluetooth is not supported on this device")
        @unknown default:
            os_log("Unexpected state occured")
        }
    }
    
    /*
     *  Catch when someone subscribes to our characteristic, then start sending them data
     */
    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didSubscribeTo characteristic: CBCharacteristic) {
        os_log("Central subscribed to characteristic")
        
        // Save central to local
        connectedCentral = central
        
        // Start sending initial message if you want
        let dataToWrite = Data("Hello Central".utf8)
        sendData(dataToWrite)
    }
    
    /*
     *  Recognize when the central unsubscribes
     */
    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didUnsubscribeFrom characteristic: CBCharacteristic) {
        os_log("Central unsubscribed from characteristic")
        
        connectedCentral = nil
    }
    
    /*
     * This callback comes in when the PeripheralManager received write to characteristics
     */
    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        
        for request in requests {
            guard let requestValue = request.value,
                  let dataString = String(data: requestValue, encoding: .utf8) else { continue }
            
            os_log("Received write request of %d bytes: %s", requestValue.count, dataString)
            
            DispatchQueue.main.async {
                self.outputTextView.text = dataString
            }
        }
    }
}
