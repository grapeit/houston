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
  let maxLines = 100

  @IBOutlet weak var history: UITextView!
  @IBOutlet weak var commandLine: UITextField!
  @IBOutlet weak var status: UILabel!
  @IBOutlet weak var bottomConstraint: NSLayoutConstraint!
    
  var motionManager: CMMotionManager!
  var manager: CBCentralManager!
  var peripheral: CBPeripheral!
  var characteristic: CBCharacteristic!
  var lastDataTimestamp: TimeInterval = 0
  var lines = 0
  var initialBottomConstraint: CGFloat?

  override func viewDidLoad() {
    super.viewDidLoad()
    // Do any additional setup after loading the view, typically from a nib.
    commandLine.delegate = self
    motionManager = CMMotionManager()
    motionManager.startAccelerometerUpdates()
    manager = CBCentralManager(delegate: self, queue: nil)
    self.history.layoutManager.allowsNonContiguousLayout = false
    
    NotificationCenter.default.addObserver(self, selector: #selector(ViewController.keyboardWillShow(_:)), name:NSNotification.Name.UIKeyboardWillShow, object: nil)
    NotificationCenter.default.addObserver(self, selector: #selector(ViewController.keyboardWillHide(_:)), name:NSNotification.Name.UIKeyboardWillHide, object: nil)
  }

  override func didReceiveMemoryWarning() {
    super.didReceiveMemoryWarning()
    // Dispose of any resources that can be recreated.
    print("didReceiveMemoryWarning")
  }
  
  @objc func keyboardWillShow(_ sender: NSNotification) {
    adjustForKeyboard(userInfo: sender.userInfo!, show: true)
  }
  
  @objc func keyboardWillHide(_ sender: NSNotification) {
    adjustForKeyboard(userInfo: sender.userInfo!, show: false)
  }
  
  private func adjustForKeyboard(userInfo: [AnyHashable : Any], show: Bool) {
    let height = (userInfo[UIKeyboardFrameEndUserInfoKey] as! NSValue).cgRectValue.height
    let duration = (userInfo[UIKeyboardAnimationDurationUserInfoKey] as! NSNumber).doubleValue
    if initialBottomConstraint == nil {
      initialBottomConstraint = bottomConstraint.constant
    }
    UIView.animate(withDuration: duration) {
      self.bottomConstraint.constant = show ? height : self.initialBottomConstraint!
      self.view?.layoutIfNeeded()
    }
  }

  func dataIn(_ data: String) {
    if data.starts(with: "\n") {
      lastDataTimestamp = 0
    }
    let rows = data.components(separatedBy: "\n")
    var first = true
    for r in rows {
      if r.isEmpty || r.starts(with: "\0") {
        continue
      }
      if !first || NSDate.timeIntervalSinceReferenceDate - lastDataTimestamp >= 1 {
        history.text.append("<< ")
      }
      history.text.append(r)
      first = false
    }
    let last = data.suffix(1)
    if last == "\n" || last == "\r\n" {
      lastDataTimestamp = 0
    } else {
      lastDataTimestamp = NSDate.timeIntervalSinceReferenceDate
    }
    onNewLine()
  }

  func dataOut(_ data: String, succeed: Bool) {
    history.text.append((succeed ? ">> " : "x> ") + data + "\n")
    lastDataTimestamp = 0
    onNewLine()
  }

  func onNewLine() {
    lines += 1
    while lines > maxLines {
      if let n = history.text.range(of: "\n") {
        history.text.removeSubrange(history.text.startIndex..<n.upperBound)
        lines -= 1
      } else {
        break
      }
    }
    history.scrollRangeToVisible(NSMakeRange(history.text.count - 3, 0))
  }

  func textFieldShouldReturn(_ textField: UITextField) -> Bool {
    let str = textField.text
    let data = Data(bytes: Array(str!.utf8))
    var succeed = false
    if self.characteristic != nil {
      self.peripheral.writeValue(data, for: self.characteristic, type: CBCharacteristicWriteType.withoutResponse)
      succeed = true
    }
    dataOut(textField.text!, succeed: succeed)
    textField.text = ""
    return false
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
      self.status.text = "Connected"
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
