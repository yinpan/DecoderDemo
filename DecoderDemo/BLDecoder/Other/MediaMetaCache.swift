//
//  MediaMetaCache.swift
//  Aries
//
//  Created by liangwei on 2023/3/8.
//  Copyright © 2023 Pinguo. All rights reserved.
//

import Foundation
import AVFoundation

/// 资源基本数据的缓存管理器
class MediaMetaCache {

    /// 缓存池
    private var cache: [String: MediaMeta] = [:]
    
    /// Thread Safe Lock
    private let lock = BLUnfairLock()
    
    /// 单例
    static var shared = MediaMetaCache()
}

// MARK: - Public Methods
extension MediaMetaCache {
    /// 更新资源渲染尺寸
    func updateOutputSize(_ size: CGSize) {
        lock.doLock {
            var newCache: [String: MediaMeta] = [:]
            for (key, meta) in cache {
                var videoWidth = meta.realSize.width
                var videoHeight = meta.realSize.height
                if meta.rotation / 90 % 2 == 1 {
                    videoWidth = meta.realSize.height
                    videoHeight = meta.realSize.width
                }
                
                let newSize = calculateScaledSize(videoWidth, videoHeight, size)
                newCache[key] = MediaMeta(previewSize: newSize,
                                          rotation: meta.rotation,
                                          totalTime: meta.totalTime,
                                          isMirrorX: meta.isMirrorX,
                                          realSize: meta.realSize,
                                          videoAsset: meta.videoAsset,
                                          videoTrack: meta.videoTrack)
            }
            
            self.cache = newCache
        }
    }
    
    /// 根据资源的uri去查找缓存，这里有个特殊逻辑：如果缓存里面没找到就会去构造数据进行缓存
    /// - Parameter uri: 资源在沙盒的uri
    func meta(for uri: String, isVideo: Bool) -> MediaMeta? {
        lock.doLock {
            if let cacheMeta = cache[uri],
               cacheMeta.videoAsset?.isReadable == true {
                return cacheMeta
            }
            
            var cacheMeta: MediaMeta?
            if let meta = createNewMeta(uri, isVideo: isVideo) {
                self.cache[uri] = meta
                cacheMeta = meta
            }
            
            return cacheMeta
        }
    }
    
    /// 缓存数据清理
    func clean() {
        lock.doLock {
            cache.removeAll()
        }
    }
}

// MARK: - Public Methods
extension MediaMetaCache {
    
    /// 根据文件路径创建新的meta信息
    func createNewMeta(_ uri: String, isVideo: Bool) -> MediaMeta? {
        
        guard FileManager.default.fileExists(atPath: uri) else {
            return nil
        }
        
        let url = URL(fileURLWithPath: uri)
        let expectOutputSize = CGSize(width: 1920, height: 1920)
        if isVideo {
            let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
            _ = asset.syncLoadTracks()
            let videoTrack: AVAssetTrack? = asset.tracks(withMediaType: AVMediaType.video).first
            let time = videoTrack?.asset?.duration.seconds ?? 0.0

            let videoWidth = videoTrack?.naturalSize.width ?? 0.0
            let videoHeight = videoTrack?.naturalSize.height ?? 0.0
            let transform = videoTrack?.preferredTransform ?? CGAffineTransform(rotationAngle: 0)
            var isMirrorX: Int32 = 0
            // 从中获取视频的方向
            let radians = Double(atan2(transform.b, transform.a))
            // 将其转换为度
            var degrees = (Int)(ceil((radians * 180.0) / Double.pi))
            // 判断是否有水平翻转
            if transform.tx == videoWidth && transform.a == -1 && transform.d == 1 { // 水平翻转
                isMirrorX = 1
                degrees -= 180
            } else if transform.tx == videoHeight && transform.b == -1 && transform.c == -1 { // 逆时针旋转90度，再水平翻转
                isMirrorX = 1
                degrees = (360 - degrees) % 360
            } else if transform.ty == videoHeight && transform.a == 1 && transform.d == -1 { // 逆时针旋转180度，再水平翻转
                isMirrorX = 1
                degrees += 180
            } else if transform.ty == 0 && transform.b == 1 && transform.c == 1 { // 逆时针旋转270度，再水平翻转
                isMirrorX = 1
                degrees = (360 - degrees)
            }
            
            // 计算当前视频旋转的度数
            if degrees == 0 || degrees == 360 {
                degrees = 0
            } else if degrees < 0 {
                degrees = (degrees % 360) + 360
            } else if degrees > 360 {
                degrees = degrees % 360
            }
            // 计算需要旋转的角度（往顺时针方向旋转纠正）
            switch degrees {
            case 0:
                degrees = 0
            case 90:
                degrees = 90
            case 180:
                degrees = 180
            case 270:
                degrees = 270
            default:
                degrees = 0
            }
            let rotation = Int(degrees)
            var scaledSize = calculateScaledSize(videoWidth, videoHeight, expectOutputSize)
            if rotation % 180 != 0 {
                scaledSize = calculateScaledSize(videoHeight, videoWidth, expectOutputSize)
            }
            
            // 获取是否是HEVC With Alpha视频
            var isHEVCWithAlpha = false
            if !asset.tracks(withMediaCharacteristic: .containsAlphaChannel).isEmpty {
                isHEVCWithAlpha = true
            }
            
            let meta = MediaMeta(previewSize: scaledSize,
                                 rotation: rotation,
                                 totalTime: Float(time),
                                 isMirrorX: isMirrorX,
                                 realSize: CGSize(width: videoWidth, height: videoHeight),
                                 videoAsset: asset,
                                 videoTrack: videoTrack,
                                 isHEVCWithAlpha: isHEVCWithAlpha)
            return meta
        } else {
            let imageSourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
            guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, imageSourceOptions) else {
                return nil
            }
            
            guard let imageHeader = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, imageSourceOptions) as? [CFString: Any] else {
                return nil
            }
            let width = imageHeader[kCGImagePropertyPixelWidth] as? CGFloat ?? 0
            let height = imageHeader[kCGImagePropertyPixelHeight] as? CGFloat ?? 0
            let orientation = 0
            let scaledSize = calculateScaledSize(width, height, expectOutputSize)

            // MSLog.debug("orientation:\(orientation) size:\(width)x\(height) scaled:\(scaledSize)")
            let meta = MediaMeta(previewSize: scaledSize,
                                 rotation: Int(orientation),
                                 totalTime: 0,
                                 isMirrorX: 0,
                                 realSize: CGSize(width: width, height: height))
            return meta
        }
    }
    
    // 抽取获取FrameSize的方法
    static func getVideoFrameSize(urlPath: String, expectOutputSize: CGSize) -> CGSize {
        guard FileManager.default.fileExists(atPath: urlPath) else {
           print("getVideoFrameSize出错：\(urlPath)路径下文件不存在")
            return .zero
        }
        
        let url = URL(fileURLWithPath: urlPath)
        let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        let videoTrack: AVAssetTrack? = asset.tracks(withMediaType: AVMediaType.video).first
        let time = videoTrack?.asset?.duration.seconds ?? 0.0
        let videoWidth = videoTrack?.naturalSize.width ?? 0.0
        let videoHeight = videoTrack?.naturalSize.height ?? 0.0
        let transform = videoTrack?.preferredTransform ?? CGAffineTransform(rotationAngle: 0)
        var isMirrorX: Int32 = 0
        // 从中获取视频的方向
        let radians = Double(atan2(transform.b, transform.a))
        // 将其转换为度
        var degrees = (Int)(ceil((radians * 180.0) / Double.pi))
        // 判断是否有水平翻转
        if transform.tx == videoWidth && transform.a == -1 && transform.d == 1 { // 水平翻转
            isMirrorX = 1
            degrees -= 180
        } else if transform.tx == videoHeight && transform.b == -1 && transform.c == -1 { // 逆时针旋转90度，再水平翻转
            isMirrorX = 1
            degrees = (360 - degrees) % 360
        } else if transform.ty == videoHeight && transform.a == 1 && transform.d == -1 { // 逆时针旋转180度，再水平翻转
            isMirrorX = 1
            degrees += 180
        } else if transform.ty == 0 && transform.b == 1 && transform.c == 1 { // 逆时针旋转270度，再水平翻转
            isMirrorX = 1
            degrees = (360 - degrees)
        }
        
        // 计算当前视频旋转的度数
        if degrees == 0 || degrees == 360 {
            degrees = 0
        } else if degrees < 0 {
            degrees = (degrees % 360) + 360
        } else if degrees > 360 {
            degrees = degrees % 360
        }
        // 计算需要旋转的角度（往顺时针方向旋转纠正）
        switch degrees {
        case 0:
            degrees = 0
        case 90:
            degrees = 90
        case 180:
            degrees = 180
        case 270:
            degrees = 270
        default:
            degrees = 0
        }
        let rotation = Int(degrees)
        var scaledSize = calculateScaledSize(videoWidth, videoHeight, expectOutputSize)
        if rotation % 180 != 0 {
            scaledSize = calculateScaledSize(videoHeight, videoWidth, expectOutputSize)
        }
        return scaledSize
    }
}
