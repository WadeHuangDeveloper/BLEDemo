//
//  TransferService.swift
//  BLEDemo
//
//  Created by Huei-Der Huang on 2024/5/1.
//

import Foundation
import CoreBluetooth

struct TransferService {
    static let serviceUUID = CBUUID(string: "00000001-0000-0000-0000-000000000000")
    static let characteristicUUID = CBUUID(string: "00000002-0000-0000-0000-000000000000")
}
