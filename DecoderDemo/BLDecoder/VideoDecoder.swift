//
//  VideoDecoder.swift
//  Aries
//
//  Created by liangwei on 2023/3/7.
//  Copyright © 2023 Pinguo. All rights reserved.
//

import UIKit
import AVFoundation

/// 视频解码器
class VideoDecoder {
    
    static let device = MTLCreateSystemDefaultDevice()
    
    /// 视频解码相关属性
    private var asset: AVAsset?
    private var videoTrack: AVAssetTrack?
    private(set) var videoOriginalFPS: CGFloat

    private var reader: AVAssetReader?
    private var videoTrackOutput: AVAssetReaderTrackOutput?
    private var outputSetting: [String: Any] = [:]
        
    /// 前一次decode成功的时间戳
    private var latestDecodeTime: Double = 0
    
    /// 当前需要decode的时间戳
    private var currentDecodeTime: Double = -1
    
    /// 标记修改了解码器输出尺寸，下次解码时需要重建解码器
    private var outputSizeChanged: Bool = false
    
    /// 资源时长
    private(set) var assetDuration: Double = 0
    
    private(set) var decodeBuffer: CMSampleBuffer?
    
    private var decodeTexture: MTLTexture?
    
    private var identifier: String
    
    private var uri: String
    
    private var cache = MediaMetaCache()
        
    /// 一帧的时长
    let oneFrameTime: Double
    
    lazy var textureCache: CVMetalTextureCache? = {
        var cache: CVMetalTextureCache?
        CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, Self.device!, nil, &cache)
        return cache
    }()
    
    /// 解码输出尺寸
    var outputSize: CGSize = .zero
    
    var meta: MediaMeta? {
        return cache.meta(for: uri, isVideo: true)
    }
    
    // MARK: Initialized Method
    required init(uri: String, key: String) {
        self.uri = uri
        identifier = key
        oneFrameTime = 1.0 / CGFloat(30)
        if let meta = cache.meta(for: uri, isVideo: true) {
            asset = meta.videoAsset
            videoTrack = meta.videoTrack
            let nominalFrameRate = CGFloat(videoTrack?.nominalFrameRate ?? 0)
            if nominalFrameRate > 0 {
                /// 某些视频nominalFrameRate读出来视频帧率29.99998不准确，decode方法中使用videoOriginalFPS向下卡帧导致0.03333333333333被卡成第0帧，导致解码画面和视频画面不一致
                videoOriginalFPS = nominalFrameRate.precised(3)
            }
            else {
                videoOriginalFPS = CGFloat(30)
            }

            if let track = videoTrack {
                assetDuration = track.timeRange.duration.seconds
            }
        }
        else {
            videoOriginalFPS = CGFloat(30)
        }
        outputSize = meta?.realSize ?? .zero
    }
    
    
    deinit {
        clear()
        print("🤖 VideoDecoder deinit.")
    }
    
    func updateOutputSize(_ size: CGSize) {
        guard !size.equalTo(outputSize) else {
            return
        }
        
        decodeTexture = nil
        outputSize = size
        outputSizeChanged = true
    }

    /// 解码指定位置的帧数据封装成MTLTexture进行返回
    /// - Parameter targetTime: 待解码位置
    /// - Returns: 指定位置的帧数据纹理信息
    func decode(_ targetTime: Double) -> CMSampleBuffer? {
        let targetTime: CGFloat = targetTime
        guard !outputSize.equalTo(.zero) else {
            return nil
        }
        
        // 在动态帧率的情况下，产生的蒙版视频平均帧率和视频有误差，向下卡帧可以避免绝大部分的误差情况
        let correctTime = targetTime > 0.0 ? targetTime.floorMatchFrameValue(fps: videoOriginalFPS) : 0.0
        
        objc_sync_enter(self)
        let startTime = CFAbsoluteTimeGetCurrent()
        defer {
            objc_sync_exit(self)
            let endTime = CFAbsoluteTimeGetCurrent()
            print("🦁 VideoDecoder decode cost: \((endTime - startTime) * 1000)ms")
        }
        
        // 是否是在往前(往右)滑动 - 倒着滑动
        let isForward = latestDecodeTime > correctTime
        // 如果和上次已解码时间相等，则直接返回上次的纹理
        if latestDecodeTime == correctTime, let curTexture = decodeTexture {
            return decodeBuffer
        }
        /* 以下几种情况需要重新构造解码器
           1. -1: 表示第一次进入解码
           2. isForward: 表示倒放需要重新开始解码
           3. outputSizeChanged: 表示预览尺寸被修改
           4. 是否被系统中断
           5. 异常下解码器没创建
           6. 待解码位置和当前视频真实解码位置超过2s */
        var interuptBySys: Bool = false
        if let error = self.reader?.error as? NSError, error.code == -11847 {
            interuptBySys = true
        }
        
        if latestDecodeTime == -1 ||
            isForward ||
            outputSizeChanged ||
            interuptBySys ||
            reader?.status == .failed ||
            (correctTime - latestDecodeTime) >= 2.0 {
            // 创建时，向前多设置一帧
            var startTime = (correctTime - oneFrameTime) > 0 ? (correctTime - oneFrameTime) : 0.0
            if self.assetDuration - targetTime < 0.5 {
                startTime = (startTime - 0.5) > 0 ? (startTime - 0.5) : 0.0
            }
            
            createNewReader(startTime)
            self.decodeBuffer = nil
            outputSizeChanged = false
        }
        
        guard let track = videoTrack else {
            return nil
        }
        
        latestDecodeTime = correctTime
        // 是否使用相同帧
        var useSameBuffer: Bool = false
        if let curBuffer = decodeBuffer {
            let curSampleTime: CMTime = CMSampleBufferGetOutputPresentationTimeStamp(curBuffer)
            if CMTIME_IS_INVALID(curSampleTime) {
                useSameBuffer = false
            }
            // 如果当前buffer时间大于目标时间，或者是当前是最后一帧，并且当前buffer的时间和目前相差不超过1帧，就使用当前帧
            if isMatchFrame(targetTime: correctTime, decodeTime: curSampleTime) {
                useSameBuffer = true
            }
        }
        
        if useSameBuffer {
            return decodeBuffer
        }

        guard let reader = self.reader, let output = self.videoTrackOutput else {
            return nil
        }
        
        while reader.status == .reading && track.nominalFrameRate > 0 {
            let beginTime = CFAbsoluteTimeGetCurrent()
            guard let buffer = output.copyNextSampleBuffer() else {
                break
            }
            let endTime = CFAbsoluteTimeGetCurrent()
            print("🦁🟢 AVAssetReader copyNextSampleBuffer cost: \((endTime - beginTime) * 1000) ms")
            let curSampleTime = CMSampleBufferGetOutputPresentationTimeStamp(buffer)
            if CMTIME_IS_INVALID(curSampleTime) {
                continue
            }
            
            // 找到了目标时间对应的帧
            if isMatchFrame(targetTime: correctTime, decodeTime: curSampleTime) {
                let time = CMTimeGetSeconds(curSampleTime)
                currentDecodeTime = time
                decodeBuffer = buffer
                return buffer
            }
        }
        
        return nil
    }
    
    /// 清理资源
    func clear() {
        // asset?.cancelLoading()
        decodeBuffer = nil
        decodeTexture = nil
        // TODO: MTLTextureCache实际使用中可能需要释放
        reader?.cancelReading()
        reader = nil
        videoTrack = nil
        videoTrackOutput = nil
    }
}

// MARK: - Private Methods
extension VideoDecoder {
    
    /// 根据需要重新创建AVAssetReader
    func createNewReader(_ startTime: Double) {
        let beginTime = CFAbsoluteTimeGetCurrent()
        defer {
            let end = CFAbsoluteTimeGetCurrent()
            print("🦁 createNewMeta 创建解码器耗时 cost: \((end - beginTime) * 1000) ms")
        }
        resetEnv()
        guard let asset = asset else {
            return
        }
        
        do {
            try reader = AVAssetReader(asset: asset)
            var bufferWidth = outputSize.width
            var bufferHeight = outputSize.height
            if let meta = self.meta, meta.rotation % 180 != 0 {
                bufferWidth = outputSize.height
                bufferHeight = outputSize.width
            }

            let outputOptions: [String: Any] = [
                kCVPixelBufferOpenGLESCompatibilityKey as String: true,
                kCVPixelBufferIOSurfacePropertiesKey as String: [:],
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
//                kCVPixelBufferWidthKey as String: Int(bufferWidth),
//                kCVPixelBufferHeightKey as String: Int(bufferHeight)
            ]
            self.outputSetting = outputOptions

            // 默认使用视频轨道默认的时间基，保证后续PTS使用的时候时间基一致
            let timescale = videoTrack?.naturalTimeScale ?? asset.duration.timescale
            let pos = CMTimeMakeWithSeconds(startTime, preferredTimescale: timescale)
            let duration = CMTime.positiveInfinity
            self.reader?.timeRange = CMTimeRangeMake(start: pos, duration: duration)

            if let track = videoTrack {
                let output = AVAssetReaderTrackOutput(track: track, outputSettings: outputSetting)
                output.alwaysCopiesSampleData = false
                videoTrackOutput = output
                if reader?.canAdd(output) == true {
                    reader?.add(output)
                }
            }
            
            if reader?.startReading() == false {
                if let error = reader?.error {
                    print("🦁 startReading error = \(error)")
                } else {
                    print("🦁 startReading error = Nil")
                }
            }
            
        } catch {
            let frameRate = videoTrack?.nominalFrameRate ?? 0
            let isReadable = self.asset?.isReadable ?? false
            print("🦁 createNewReader error = \(error.localizedDescription) - frameRate = \(frameRate) - isReadable = \(isReadable)")
        }
    }
    
    func resetEnv() {
        self.reader?.cancelReading()
        self.videoTrackOutput = nil
        self.reader = nil
        
        /*if self.videoTrack?.nominalFrameRate == 0,
           let meta = MediaMetaCache.shared.createNewMeta(self.uri, isVideo: true) {
            self.asset = meta.videoAsset
            self.videoTrack = meta.videoTrack
        }*/
        if self.asset?.isReadable == false,
           let meta = cache.createNewMeta(self.uri, isVideo: true) {
            self.asset = meta.videoAsset
            self.videoTrack = meta.videoTrack
        }
    }
    
    // 计算当前目标时间和解码时间是否匹配
    func isMatchFrame(targetTime: Double, decodeTime: CMTime) -> Bool {
        
        // ------------ 【兜底的方案】（v1.5.00以前的匹配规则）------------

        // 如果相等，直接匹配成功
        if CGFloat.equal(targetTime, decodeTime.seconds, precise: 5) {
            return true
        }
        
        let time = CMTimeGetSeconds(decodeTime)
        let decodeMatch = Double.compare(targetTime, by: >, time, precise: 5)
        let diff = Double.compare(abs(targetTime - time), by: <, self.oneFrameTime, precise: 5)
        if decodeMatch, diff {
            return true
        }
        
        // 找到了目标时间对应的帧
        let offsetTime2 = abs(targetTime - time) <= (self.oneFrameTime)
        let isLastFrame = (self.assetDuration - targetTime) <= (self.oneFrameTime)
        return isLastFrame && offsetTime2
    }

}

extension AVAsset {
    
    @discardableResult
    func syncLoadTracks() -> NSError? {
        let beginTime = CFAbsoluteTimeGetCurrent()
        defer {
            let end = CFAbsoluteTimeGetCurrent()
            print("🦁 syncLoadTracks cost: \((end - beginTime) * 1000) ms")
        }
        let trackKey = "tracks"
        let sema = DispatchSemaphore(value: 0)
        var error: NSError?
        self.loadValuesAsynchronously(forKeys: [trackKey]) {
            let status = self.statusOfValue(forKey: trackKey, error: &error)
            if status == .loaded || status == .cancelled || status == .failed {
                sema.signal()
            }
        }
        sema.wait()
        if let error = error {
            print("syncLoadTracks \(error) \(self)")
            if let url = (self as? AVURLAsset)?.url.relativePath {
                let fileExists = FileManager.default.fileExists(atPath: url)
                print("syncLoadTracks fileExists:\(fileExists), \(url)")
            }
        }
        return error
    }
    
}

