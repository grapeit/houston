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

  @IBOutlet weak var theOnlyLabel: UILabel!
  @IBOutlet weak var history: UITextView!
  @IBOutlet weak var commandLine: UITextField!
  var timer = Timer()
  var motionManager: CMMotionManager!
  var cnt1 = 0
  var cnt2 = 1
  var manager:CBCentralManager!
  var peripheral:CBPeripheral!
  var characteristic:CBCharacteristic!


  override func viewDidLoad() {
    super.viewDidLoad()
    // Do any additional setup after loading the view, typically from a nib.
    debugPrint("viewDidLoad")
    commandLine.delegate = self;
    motionManager = CMMotionManager()
    motionManager.startAccelerometerUpdates()
    //timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) {_ in self.onTimer() }
    manager = CBCentralManager(delegate: self, queue: nil)
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
      theOnlyLabel.text = String(format: "%ld: x: %.2lf, y: %.2lf, z: %.2f", cnt, a.acceleration.x, a.acceleration.y, a.acceleration.z)
    }
  }

  func textFieldShouldReturn(_ textField: UITextField) -> Bool {
    let str = textField.text
    let data = Data(bytes: Array(str!.utf8))
    if self.characteristic != nil {
      self.history.text.append(">> " + textField.text! + "\n")
      history.scrollRangeToVisible(NSMakeRange(history.text.characters.count - 1, 1))
      self.peripheral.writeValue(data, for: self.characteristic, type: CBCharacteristicWriteType.withoutResponse)
    }
    textField.text = "";
    return false;
  }

  func centralManagerDidUpdateState(_ central: CBCentralManager) {
    print("centralManagerDidUpdateState")
    if central.state == CBManagerState.poweredOn {
      central.scanForPeripherals(withServices: nil, options: nil)
    } else {
      print("Bluetooth not available.")
    }
  }

  func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
    let device = (advertisementData as NSDictionary).object(forKey: CBAdvertisementDataLocalNameKey) as? NSString
    if device?.isEqual(to: "Houston") == true {
      print("centralManager: \(RSSI) \(device) advertisementData: \(advertisementData)")
      self.manager.stopScan()
      self.peripheral = peripheral
      self.peripheral.delegate = self
      print("connecting to \(device)")
      manager.connect(peripheral, options: nil)
    }
  }

  func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
    print("connected to \(peripheral)")
    peripheral.discoverServices(nil)
  }

  func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
    print("peripheral connected: \(peripheral), error: \(error)")
    for service in peripheral.services! {
      let thisService = service as CBService
      print("service: \(thisService)")
      if thisService.uuid == CBUUID(string: "FFE0") {
        print("discovering characteristics")
        peripheral.discoverCharacteristics(nil, for: thisService)
      }
    }
  }

  func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
    print("peripheral characteristics")
    for characteristic in service.characteristics! {
      let thisCharacteristic = characteristic as CBCharacteristic
      print("characteristic: \(thisCharacteristic)")
      if thisCharacteristic.uuid == CBUUID(string: "FFE1") {
        self.characteristic = thisCharacteristic
        self.peripheral.setNotifyValue(true, for: thisCharacteristic)
      }
    }
  }

  func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
    print("characteristic update: \(characteristic) error: \(error)")
    if characteristic.uuid == CBUUID(string: "FFE1") {
      let data = String(data: characteristic.value!, encoding: String.Encoding.utf8)
      print("data: \(data)")
      history.text.append("<< " + data!)
      history.scrollRangeToVisible(NSMakeRange(history.text.characters.count - 1, 1))
    }
  }

  func peripheral(_ peripheral: CBPeripheral, didDiscoverDescriptorsFor characteristic: CBCharacteristic, error: Error?) {
    print("!!!didDiscoverDescriptorsFor")
  }

  func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor descriptor: CBDescriptor, error: Error?) {
    print("!!!didUpdateValueFor")
  }

}
