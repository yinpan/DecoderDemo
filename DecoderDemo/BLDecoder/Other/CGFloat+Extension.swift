//
//  CGFloat+Extension.swift
//  Aries
//
//  Created by yinpan on 2021/11/6.
//

import Foundation

// MARK: - 卡帧
extension CGFloat {
    
    /// 轨道忽略的误差值
    static let trackIgnoreValue: CGFloat = 0.001
    
    /// 匹配对应的卡帧值[四舍五入]
    var matchFrameValue: CGFloat {
        let fpsValue = 30.0
        var value = self * CGFloat(fpsValue)
        value.round(.toNearestOrAwayFromZero)
        return value / CGFloat(fpsValue)
    }
    
    /// 匹配对应的卡帧值[向下取整]
    var floorMatchFrameValue: CGFloat {
        /// 解决误差扩大fps 倍后，当前帧被卡到上一帧的问题，「1.9333333333333331 卡帧后变成1.9 的问题」
        let fps = 30.0
        let roundVal = matchFrameValue(fps: fps)
        if roundVal.isNearlyEqual(self) {
            return roundVal
        }
        let value = floor(self * fps)
        return value / CGFloat(fps)
    }
    
    /// 是否卡帧了
    var isMatchFrame: Bool {
       var matchValue = self.matchFrameValue
        return self.isNearlyEqual(matchValue)
    }
    
    /// 是否是同一帧
    /// - Parameter other: 比较帧
    /// - Returns: 是否相同
    func isSameframe(_ other: CGFloat, _ otherFPS: CGFloat?) -> Bool {
        let fpsValue = 30.0
        var lhs = self * CGFloat(fpsValue)
        lhs.round(.toNearestOrAwayFromZero)
        var rhs = other * CGFloat(fpsValue)
        rhs.round(.toNearestOrAwayFromZero)
        // 有些视频不是每帧都相差 1 / FPS毫秒，所以要根据视频帧率和工程帧率进行计算差值
        if Int(lhs) == Int(rhs) {
            return true
        } else {
            guard let otherFPS = otherFPS, otherFPS != 0 else {
                return false
            }
            
            let diff = CGFloat(fpsValue) / otherFPS
            if Int(rhs) > Int(lhs) && Int(rhs) - Int(lhs) <= Int(diff) {
                return true
            }
        }
        
        return false
    }
    
    func matchFrameValue(_ rule: FloatingPointRoundingRule) -> CGFloat {
        let fpsValue = 30.0
        var value = self * CGFloat(fpsValue)
        value.round(rule)
        return value / CGFloat(fpsValue)
    }

    func matchFrameValue(fps: Int) -> CGFloat {
        var value = self * CGFloat(fps)
        value.round(.toNearestOrAwayFromZero)
        return value / CGFloat(fps)
    }
    
    func floorMatchFrameValue(fps: CGFloat) -> CGFloat {
        /// 解决误差扩大fps 倍后，当前帧被卡到上一帧的问题，「1.9333333333333331 卡帧后变成1.9 的问题」
        let roundVal = matchFrameValue(fps: fps)
        if roundVal.isNearlyEqual(self) {
            return roundVal
        }
        let value = floor(self * fps)
        return value / CGFloat(fps)
    }
    
    func ceilMatchFrameValue(fps: CGFloat) -> CGFloat {
        /// 解决误差扩大fps 倍后，当前帧被卡到下一帧的问题，「1.933333333333334 卡帧后变成1.9666666666666666 的问题」
        let roundVal = matchFrameValue(fps: fps)
        if roundVal.isNearlyEqual(self) {
            return roundVal
        }
        let value = ceil(self * fps)
        return value / CGFloat(fps)
    }

    func matchFrameValue(fps: CGFloat) -> CGFloat {
        var value = self * fps
        value.round(.toNearestOrAwayFromZero)
        return value / CGFloat(fps)
    }
    
    var toFrameTime: String {
        let fpsValue = 30.0
        let tolalFrame = matchFrameValue * CGFloat(fpsValue)
        var sec = Int(tolalFrame) / Int(fpsValue)
        let minute =  sec / 60
        var zhen = tolalFrame.truncatingRemainder(dividingBy: CGFloat(fpsValue))
        sec -= minute * 60
        zhen += 0.000001
        return String(format: "%02d:%02d:%02.0f", arguments: [minute, sec, floor(zhen)])
    }
    
    var formatTime: String {
        guard !isNaN else { return "00:00" }
        // 设置当前显示的时间
        let showTime = Int(self) // 向下取整
        if showTime < 60 * 60 {
            let minute = showTime / 60
            let second = truncatingRemainder(dividingBy: 60)
            return String(format: "%02d:%02.0f", minute, second)
        } else {
            let hour = showTime / (60 * 60)
            let minute = (showTime - hour * 60 * 60) / 60
            let second = showTime % 60
            return String(format: "%02d:%02d:%02d", hour, minute, second)
        }
    }
    
    /// 转换为指定帧率下的帧索引
    /// - Parameter fps: 指定的帧率，默认为当前工程的帧率
    /// - Returns: 帧索引
    func toFrameIndex(fps: CGFloat = 30) -> Int {
        var value = self * fps
        value.round(.toNearestOrAwayFromZero)
        let index = Int(value)
        return index
    }
    
    /// 是否是有效的速率值，用于判断变速值是否有效
    var isValidRateValue: Bool {
        if self.isNaN {
            return false
        }
        return self > 0
    }
    
    var isNonNan: Bool { return !isNaN }

    /// 是否是无穷数或者不是数字
    var isInfiniteOrNaN: Bool {
        return isNaN || isInfinite
    }
}

extension CGFloat {
    
    var roundNear: CGFloat {
        let newValue = self
        let divisor = powf(10.0, Float(6))
        let divisorDuration = roundf(Float(newValue) * divisor) / divisor
        return CGFloat(divisorDuration)
    }
    
    var cardFrame: CGFloat {
        let newValue = self
        let fpsValue = 30.0
        let divisor = powf(10.0, Float(6))
        let divisorDuration = roundf(Float(newValue) * divisor) / divisor
        let singleFrameDuration = 1 / Float(fpsValue)
        let frameSeconds = roundf(divisorDuration * Float(fpsValue)) * singleFrameDuration
        return CGFloat(frameSeconds)
    }
}

// MARK: - 判断两个浮点数是否相对
extension FloatingPoint {
    
    func isNearlyEqual(_ value: Self) -> Bool {
        return abs(self - value) <= .ulpOfOne * 10
    }
    
    /// 判断是否大于或等于浮点数
    /// - Returns: 是否否大于或等于
    func isGreaterOrEqual(_ value: Self) -> Bool {
        return self > value || isNearlyEqual(value)
    }
    
    /// 判断是否大于浮点数
    /// - Returns: 是否大于
    func isGreater(_ value: Self) -> Bool {
        guard !isNearlyEqual(value) else {
            return false
        }
        return self > value
    }

    /// 判断是否小于或等于浮点数
    /// - Returns: 是否否大于或等于
    func isLessOrEqual(_ value: Self) -> Bool {
        return self < value || isNearlyEqual(value)
    }
    
    /// 判断是否小于浮点数
    /// - Returns: 是否小于
    func isLess(_ value: Self) -> Bool {
        guard !isNearlyEqual(value) else {
            return false
        }
        return self < value
    }
    
}

/// 判断两个浮点数是否相对
/// - Returns: 是否相等
func isNearlyEqual<T: FloatingPoint>(_ lhs: T, _ rhs: T) -> Bool {
    return lhs.isNearlyEqual(rhs)
}

// MARK: - 根据指定的进度进行比较
extension CGFloat {
    
    static func equal(_ lhs: CGFloat, _ rhs: CGFloat, precise value: Int? = nil) -> Bool {
        guard let value = value else {
            return abs(lhs - rhs) <= .ulpOfOne
        }
        return lhs.precised(value) == rhs.precised(value)
    }
    
    func precised(_ value: Int = 1) -> Double {
        let offset = pow(10, Double(value))
        return (self * offset).rounded() / offset
    }
    
    static func compare(_ lhs: CGFloat, by condition: (CGFloat, CGFloat) -> Bool, _ rhs: CGFloat, precise value: Int) -> Bool {
        return condition(lhs.precised(value), rhs.precised(value))
    }
    
}

extension Double {
    
    static func equal(_ lhs: Double, _ rhs: Double, precise value: Int? = nil) -> Bool {
        guard let value = value else {
            return abs(lhs - rhs) <= .ulpOfOne
        }
        return lhs.precised(value) == rhs.precised(value)
    }
    
    func precised(_ value: Int = 1) -> Double {
        let offset = pow(10, Double(value))
        return (self * offset).rounded() / offset
    }
    
    static func compare(_ lhs: Double, by condition: (Double, Double) -> Bool, _ rhs: Double, precise value: Int) -> Bool {
        return condition(lhs.precised(value), rhs.precised(value))
    }
}

extension CGFloat {
    
    // 四舍五入
    func roundTo(places: Int) -> CGFloat {
        let divisor = pow(10.0, CGFloat(places))
        return (self * divisor).rounded() / divisor
    }

}
