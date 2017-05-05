//
//  ViewController.swift
//  Houston
//
//  Created by Aleksandr Vinogradov on 2/4/17.
//  Copyright © 2017 Accel. All rights reserved.
//

import UIKit
import CoreMotion
import CoreBluetooth

class ViewController: UIViewController, UITextFieldDelegate, CBCentralManagerDelegate, CBPeripheralDelegate {

  let deviceName = "Houston"
  let serviceId = CBUUID(string: "FFE0")
  let characteristicId = CBUUID(string: "FFE1")

  @IBOutlet weak var titleLabel: UILabel!
  @IBOutlet weak var history: UITextView!
  @IBOutlet weak var commandLine: UITextField!
  @IBOutlet weak var status: UILabel!

  var timer = Timer()
  var motionManager: CMMotionManager!
  var cnt1 = 0
  var cnt2 = 1
  var manager: CBCentralManager!
  var peripheral: CBPeripheral!
  var characteristic: CBCharacteristic!
  var lastDataTimestamp: TimeInterval = 0


  override func viewDidLoad() {
    super.viewDidLoad()
    // Do any additional setup after loading the view, typically from a nib.
    debugPrint("viewDidLoad")
    commandLine.delegate = self;
    motionManager = CMMotionManager()
    motionManager.startAccelerometerUpdates()
    //timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) {_ in self.onTimer() }
    manager = CBCentralManager(delegate: self, queue: nil)
    self.history.layoutManager.allowsNonContiguousLayout = false
  }

  override func didReceiveMemoryWarning() {
    super.didReceiveMemoryWarning()
    // Dispose of any resources that can be recreated.
    debugPrint("didReceiveMemoryWarning")
  }

  func onTimer() {
    let cnt = cnt1 + cnt2;
    cnt1 = cnt2;
    cnt2 = cnt;
    if let a = motionManager.accelerometerData {
      titleLabel.text = String(format: "%ld: x: %.2lf, y: %.2lf, z: %.2f", cnt, a.acceleration.x, a.acceleration.y, a.acceleration.z)
    }
  }

  func dataIn(_ data: String) {
    if data.characters.first == "\n" {
      lastDataTimestamp = 0
    }
    let rows = data.components(separatedBy: "\n")
    var first = true
    for r in rows {
      if r.isEmpty || r.characters.first == "\0" {
        continue;
      }
      if !first || NSDate.timeIntervalSinceReferenceDate - lastDataTimestamp >= 1 {
        history.text.append("<< ")
      }
      history.text.append(r)
      first = false
    }
    let last = data.characters.last
    if last == "\n" || last == "\r\n" {
      lastDataTimestamp = 0
    } else {
      lastDataTimestamp = NSDate.timeIntervalSinceReferenceDate
    }
    scrollHistory()
  }

  func dataOut(_ data: String) {
    history.text.append(">> " + data + "\n")
    lastDataTimestamp = 0
    scrollHistory()
  }

  func scrollHistory() {
    history.scrollRangeToVisible(NSMakeRange(history.text.characters.count - 1, 0))
  }

  func textFieldShouldReturn(_ textField: UITextField) -> Bool {
    let str = textField.text
    let data = Data(bytes: Array(str!.utf8))
    if self.characteristic != nil {
      self.peripheral.writeValue(data, for: self.characteristic, type: CBCharacteristicWriteType.withoutResponse)
      dataOut(textField.text!)
    }
    textField.text = "";
    return false;
  }

  func onConnectionFailed(_ error: String) {
    self.status.text = "Connection failed: " + error
    self.characteristic = nil
    self.peripheral = nil
    Timer.scheduledTimer(withTimeInterval: 2, repeats: false) {_ in
      if (self.manager.state == CBManagerState.poweredOn) {
        self.status.text = "Searching for device"
        self.manager.scanForPeripherals(withServices: [self.serviceId], options: nil)
      }
    }
  }

  func centralManagerDidUpdateState(_ central: CBCentralManager) {
    print("centralManagerDidUpdateState")
    if central.state == CBManagerState.poweredOn {
      central.scanForPeripherals(withServices: [serviceId], options: nil)
      self.status.text = "Searching for device"
    } else {
      self.characteristic = nil
      self.peripheral = nil
      self.status.text = "Bluetooth is not available"
    }
  }

  func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
    let device = (advertisementData as NSDictionary).object(forKey: CBAdvertisementDataLocalNameKey) as? NSString
    if device?.isEqual(to: deviceName) == true {
      self.manager.stopScan()
      self.peripheral = peripheral
      self.peripheral.delegate = self
      self.status.text = "Connecting (state 1 of 3)"
      manager.connect(peripheral, options: nil)
    }
  }

  func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
    print("connected to \(peripheral)")
    self.status.text = "Connecting (stage 2 of 3)"
    peripheral.discoverServices([serviceId])
  }

  func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
    onConnectionFailed("Failed to connect")
  }

  func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
    onConnectionFailed("Device disconnected")
  }

  func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
    var good = false
    for service in peripheral.services! {
      print("service: \(service)")
      if service.uuid == serviceId {
        print("discovering characteristics")
        peripheral.discoverCharacteristics(nil, for: service)
        good = true
      }
    }
    if (good) {
      self.status.text = "Connecting (stage 3 of 3)"
    } else {
      onConnectionFailed("Requred service is not found")
    }
  }

  func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
    print("peripheral characteristics")
    var good = false
    for characteristic in service.characteristics! {
      print("characteristic: \(characteristic)")
      if characteristic.uuid == characteristicId {
        self.characteristic = characteristic
        self.peripheral.setNotifyValue(true, for: characteristic)
        good = true
      }
    }
    if (good) {
      self.status.text = "Connected";
    } else {
      onConnectionFailed("Required characteristic is not found")
    }
  }

  func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
    if characteristic.uuid == characteristicId {
      let data = String(data: characteristic.value!, encoding: String.Encoding.utf8)
      dataIn(data!)
    }
  }
}
