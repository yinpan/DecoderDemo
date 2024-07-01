//
//  PMFPSTrace.swift
//  Demo
//
//  Created by yinpan on 2023/8/24.
//

import Foundation
import UIKit

// MARK: - PMFPSTraceDelegate

protocol PMFPSTraceDelegate: AnyObject {
    
    func fpsValueDidChanged(_ FPSValue: Int)
    
}

// MARK: - PMFPSTrace

class PMFPSTrace {
    
    static let shared = PMFPSTrace()

    private(set) var isRunning = false
    private(set) var fpsValue = 0
    private var displayLink: CADisplayLink?
    private var fpsTickCount: UInt = 0
    private var fpsTickLastTime: TimeInterval = 0
    private var delegates = NSHashTable<AnyObject>.weakObjects()

    init() {}

    func addDelegate(_ delegate: PMFPSTraceDelegate) {
        delegates.add(delegate)
    }

    func removeDelegate(_ delegate: PMFPSTraceDelegate) {
        delegates.remove(delegate)
    }

    func start() {
        displayLink?.invalidate()
        displayLink = CADisplayLink(target: WeakProxy(target: self), selector: #selector(WeakProxy.proxyTickFPS(_:)))
        displayLink?.add(to: .main, forMode: .common)
        isRunning = true
    }

    func stop() {
        displayLink?.invalidate()
        displayLink = nil
        isRunning = false
    }

    @objc private func tickFPS(_ link: CADisplayLink) {
        if fpsTickLastTime < .ulpOfOne {
            fpsTickLastTime = link.timestamp
            return
        }

        fpsTickCount += 1
        let delta = link.timestamp - fpsTickLastTime
        if delta < 1 {
            return
        }

        fpsTickLastTime = link.timestamp
        let fps = TimeInterval(fpsTickCount) / delta
        fpsTickCount = 0
        let newFPS = Int(round(fps))

        if fpsValue != newFPS {
            delegates.allObjects
                .compactMap { $0 as? PMFPSTraceDelegate }
                .forEach { $0.fpsValueDidChanged(newFPS) }
        }
        fpsValue = newFPS
    }
}

// MARK: - Helper
extension PMFPSTrace {
    
    fileprivate class WeakProxy {
        
        weak var target: PMFPSTrace?

        init(target: PMFPSTrace) {
            self.target = target
        }

        @objc func proxyTickFPS(_ link: CADisplayLink) {
            target?.tickFPS(link)
        }
    }

}
