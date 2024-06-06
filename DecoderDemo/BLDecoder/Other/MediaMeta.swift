//
//  MediaMeta.swift
//  Aries
//
//  Created by liangwei on 2023/3/8.
//  Copyright © 2023 Pinguo. All rights reserved.
//

import Foundation
import AVFoundation

/// 素材资源基础数据
struct MediaMeta {
    let previewSize: CGSize
    let rotation: Int
    let totalTime: Float
    let isMirrorX: Int32
    let realSize: CGSize
    
    // 视频资源相关属性
    var videoAsset: AVAsset?
    var videoTrack: AVAssetTrack?

    // 标记是否是HEVC With Alpha视频
    var isHEVCWithAlpha = false
    
    var isVideo: Bool {
        return totalTime > 0
    }
}
