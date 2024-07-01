//
//  PMPerfSupport.swift
//  Demo
//
//  Created by yinpan on 2023/8/28.
//

import UIKit

@objcMembers
class PMPerfSupport: NSObject, PMPerfMonitorDelegate {
    
    static let shared = PMPerfSupport()
    
    private var exportBeginTime: CFAbsoluteTime = CFAbsoluteTimeGetCurrent()
    
    override init() {
        super.init()
    }
    
    func perfMonitor(_ perfMonitor: PMPerfMonitor, perfDataDidChanged perfData: PMPerfData) {
        guard perfMonitor.isRecording else {
            return
        }
        perfData.printLog(tag: PMPerfMonitor.logTag, label: "")
    }

    func fpsValueDidChanged(_ FPSValue: Int) {
        
    }

    func setupPerfDelegate(isSubscribe: Bool) {
        if isSubscribe {
            PMPerfMonitor.shared.addDelegate(self)
        } else {
            PMPerfMonitor.shared.removeDelegate(self)
        }
    }
    
    func startIfNeeded() {
        PMPerfMonitor.shared.enable = true
        PMPerfMonitor.shared.start()
        PMPerfMonitor.shared.startRecordData()
        
        setupPerfDelegate(isSubscribe: true)
    }
    
    func disableMonitor() {
        PMPerfMonitor.shared.enable = false
        PMPerfMonitor.shared.stop()
        PMPerfMonitor.shared.stopRecordData()
        
        setupPerfDelegate(isSubscribe: false)
    }

}
