//
//  PMPerfData.swift
//  Demo
//
//  Created by yinpan on 2023/8/28.
//

import Foundation

struct PMPerfData: CustomStringConvertible {
    
    /// 内存占用数，单位为字节
    let memory: Int64
    
    /// CPU的使用率
    let cpuUsedByAllThreads: Double
    
    /// GPU占用情况，单位为%
    let gpuUsage: Float?
    
    /// 帧率
    let fps: Int
    
    /// 当前设备占用的内存
    let memoryDeviceUsed: Int64

    /// 当前设备的物理内存
    static let physicalMemory: Int64 = PMAppStat.physicalMemory
    
    var description: String {
        let memory = String(format: "%.0fM", Double(memory) / 1024.0 / 1024.0)
        let cpu = String(format: "%.0f%%", cpuUsedByAllThreads * 100)
        let deviceMemory = String(format: "%.0fM", Double(memoryDeviceUsed) / 1024.0 / 1024.0)
        let physicalMemory = String(format: "%.0fM", Double(PMPerfData.physicalMemory) / 1024.0 / 1024.0)
        let memoryRatio = String(format: "%.1f%%", Double(memoryDeviceUsed) / Double(PMPerfData.physicalMemory) * 100)
        var gpu: String = ""
        if let gpuUsage = gpuUsage {
            gpu = String(format: "%.0f%%", gpuUsage)
        }
        return "FPS: \(fps) | Memory: \(memory) | CPU: \(cpu) | GPU: \(gpu) | 内存占比: \(memoryRatio) | 内存占用： \(deviceMemory)/\(physicalMemory)"
    }
    
    func printLog(tag: String, label: String) {
        if label.isEmpty {
            print("[\(tag)]: \(self.description)")
        } else {
            print("[\(tag)][\(label)]: \(self.description)")
        }
    }
    
}
