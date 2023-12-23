//
//  TransferService.swift
//  BLEDemo
//
//  Created by WadeGigatms on 2023/12/22.
//

import Foundation
import CoreBluetooth

struct TransferService {
    static let serviceUUID = CBUUID(string: "00000001-0000-0000-0000-000000000000")
    static let characteristicUUID = CBUUID(string: "00000002-0000-0000-0000-000000000000")
}
