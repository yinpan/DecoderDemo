//
//  PMPerfMonitor.swift
//  Demo
//
//  Created by yinpan on 2023/8/26.
//

import Foundation
import Combine

protocol PMPerfMonitorDelegate: AnyObject {
    
    func perfMonitor(_ perfMonitor: PMPerfMonitor, perfDataDidChanged perfData: PMPerfData)

    func fpsValueDidChanged(_ FPSValue: Int)
    
}

/// 性能统计
@objcMembers
class PMPerfMonitor: NSObject {
    
    static let shared = PMPerfMonitor()
    
    /// 最小的采样间隔，为 0.01 秒
    static let minimumFlushTimeInterval: CGFloat = 0.01
    
    /// 采样的默认间隔时间，为0.1秒
    static let defaultFlushTimeInterval: CGFloat = 0.1
    
    static let logTag = "🍓性能日志"

    private var flushTimer: DispatchSourceTimer?
    private var flushQueue: DispatchQueue?
    
    private lazy var fpsTrace = PMFPSTrace()
    
    /// 是否支持GPU指标监控
    static let isSupportGPUMonitor: Bool = {
        return NSClassFromString("GPUUtilization") != nil
    }()
    
    /// 更新数据的间隔时间，默认为半秒
    private(set) var flushIntevalInSeconds: DispatchTimeInterval = .nanoseconds(Int(NSEC_PER_SEC) / 2)
    
    @Published private(set) var isRecording: Bool = false
    
    private var delegates = NSHashTable<AnyObject>.weakObjects()
    
    /// 是否启用
    @objc var enable: Bool = false
    
    /// 设置采样的间隔
    func set(sampleInterval: Double) {
        setFlushInteval(seconds: sampleInterval)
        // 重启定时器
        stop()
        startIfNeeded()
    }
    
    override init() {
        super.init()
        setFlushInteval(seconds: Self.defaultFlushTimeInterval)
    }
    
    private func setFlushInteval(seconds: Double) {
        let timeInterval = max(Self.minimumFlushTimeInterval, seconds)
        let nanoseconds = timeInterval * Double(NSEC_PER_SEC)
        flushIntevalInSeconds = .nanoseconds(Int(nanoseconds))
    }
    
    func startIfNeeded() {
        guard enable else { return }
        start()
    }
    
    func start() {
        guard flushTimer == nil else { return }
        let flushQueue = DispatchQueue(label: "com.blurrr.perfMonitor", qos: .userInitiated)
        self.flushQueue = flushQueue
        flushTimer = DispatchSource.makeTimerSource(queue: flushQueue)

        flushTimer?.schedule(deadline: .now(), repeating: flushIntevalInSeconds)
        flushTimer?.setEventHandler(handler: { [weak self] in
            self?.flushTimerFired()
        })
        flushTimer?.resume()
        
        fpsTrace.start()
        fpsTrace.addDelegate(self)
    }

    func stop() {
        fpsTrace.stop()
        fpsTrace.removeDelegate(self)
        
        flushTimer?.cancel()
        flushTimer = nil
        flushQueue = nil
    }

    func flushTimerFired() {
        
        let cpu = PMAppStat.cpuUsedByAllThreads
        let memoryFootprint = PMAppStat.memory
        let memoryDeviceUsed = PMAppStat.memoryDeviceUsed
        let fps = fpsTrace.fpsValue
        var gpu: Float?
//        #if DEBUG
        gpu = GPUUtilization.gpuUsage
//        #endif
        
//        if let GPUUtilization = NSClassFromString("GPUUtilization") as? NSObject.Type {
//            let gpuUsageSelector = NSSelectorFromString("gpuUsage")
//            if GPUUtilization.responds(to: gpuUsageSelector) {
//                gpu = GPUUtilization.perform(gpuUsageSelector)?.takeUnretainedValue() as? Float
//            }
//        }
        
        let data = PMPerfData(memory: memoryFootprint, cpuUsedByAllThreads: cpu, gpuUsage: gpu, fps: fps, memoryDeviceUsed: memoryDeviceUsed)
        objc_sync_enter(self)
        delegates.allObjects
            .compactMap { $0 as? PMPerfMonitorDelegate }
            .forEach { $0.perfMonitor(self, perfDataDidChanged: data) }
        objc_sync_exit(self)
    }
    
}

extension PMPerfMonitor {
    
    func startRecordData() {
        self.isRecording = true
        print("[\(Self.logTag)][启动]: 开始性能监控记录")
        setFlushInteval(seconds: Self.defaultFlushTimeInterval)
    }
    
    func stopRecordData() {
        self.isRecording = false
        print("[\(Self.logTag)][停止]: 停止性能监控记录")
        setFlushInteval(seconds: Self.defaultFlushTimeInterval)
    }
    
}

extension PMPerfMonitor: PMFPSTraceDelegate {
    
    func fpsValueDidChanged(_ FPSValue: Int) {
        objc_sync_enter(self)
        delegates.allObjects
            .compactMap { $0 as? PMPerfMonitorDelegate }
            .forEach { $0.fpsValueDidChanged(FPSValue) }
        objc_sync_exit(self)
    }
    
}

extension PMPerfMonitor {
    
    func addDelegate(_ delegate: PMPerfMonitorDelegate) {
        objc_sync_enter(self)
        delegates.add(delegate)
        objc_sync_exit(self)
    }

    func removeDelegate(_ delegate: PMPerfMonitorDelegate) {
        objc_sync_enter(self)
        guard delegates.contains(delegate) else {
            return
        }
        delegates.remove(delegate)
        objc_sync_exit(self)
    }

}
