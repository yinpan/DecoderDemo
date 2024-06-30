//
//  ViewController.swift
//  DecoderDemo
//
//  Created by yinpan on 2024/6/4.
//

import UIKit

enum DecoderType: Int, CustomStringConvertible {
    
    case VideoToolBox
    case FFmpegHardware
    case FFmpegSoftware
    case AVFoundation
    
    var description: String {
        switch self {
        case .VideoToolBox: return "VideoToolBox"
        case .FFmpegHardware: return "FFmpegHardware"
        case .FFmpegSoftware: return "FFmpegSoftware"
        case .AVFoundation: return "AVFoundation"
        }
    }
}

class ViewController: UIViewController {
    
    @IBOutlet weak var imageView: UIImageView!
    
    @IBOutlet weak var previewView: MetalYUVView!
    
    @IBOutlet weak var segmentControl: UISegmentedControl!
    
    @IBOutlet weak var formatSegmentControl: UISegmentedControl!
    
    private var decoderType: DecoderType = .VideoToolBox
    
    private var encodeFormat: BLVideoEncodeFormat = .H264
    
    private var formatReader: AVFormatReader?

    private var vt_decoder: VTDecoder?
    
    private var ff_decoder: FFDecoder?
    
    private var bl_decoder: VideoDecoder?
    
    override func viewDidLoad() {
        super.viewDidLoad()
    }
    @IBAction func encodeFormatDidChanged(_ sender: UISegmentedControl) {
        if sender.selectedSegmentIndex == 0 {
            self.encodeFormat = .H264
        } else {
            self.encodeFormat = .H265
        }
    }
    
    @IBAction func decodeTypeDidChanged(_ sender: UISegmentedControl) {
        self.decoderType = DecoderType(rawValue: sender.selectedSegmentIndex) ?? .VideoToolBox
    }
    
    @IBAction func playButtonClicked(_ sender: UIButton) {
        stopDecoder()
        reloadVideo()
    }
    
    @IBAction func stopPlayButtonClicked(_ sender: UIButton) {
        stopDecoder()
    }
    
    private func getVideoPath() -> String? {
        let isH264 = formatSegmentControl.selectedSegmentIndex == 0
        let fileName = if isH264 {
            "number_h264.MP4"
//            "testh264.MP4"
//            "sample_1920x1080_h264.mp4"
//            "sample_cartoon_h264.mp4"
//            "sample_1280x720_李子柒.mp4"
//            "number_h264_no_b.MP4"
//            "ReplaceVideoMaterial.mov"
        } else {
//            "sample_cartoon_h265.mp4"
            "sample_1920x1080_h265.mp4"
        }
        return Bundle.main.path(forResource: fileName, ofType: nil)
    }
    
    private func reloadVideo() {
        
        if decoderType == .AVFoundation {
            guard let filePath = getVideoPath() else {
                return
            }
            var beginTime = CFAbsoluteTimeGetCurrent()
            self.bl_decoder = VideoDecoder(uri: filePath, key: filePath)
            // 实例解码器
            self.bl_decoder?.createNewReader(0)
            let end = CFAbsoluteTimeGetCurrent()
            print("🦁 [\(self.decoderType)] 创建解码器耗时 cost: \((end - beginTime) * 1000) ms")
            DispatchQueue.global(qos: .userInteractive).async {
                var time: CGFloat = 0
                beginTime = CFAbsoluteTimeGetCurrent()
                while let buffer = self.bl_decoder?.decode(time) {
                    let end = CFAbsoluteTimeGetCurrent()
                    print("🦁🦁 [\(self.decoderType)] decode frame total cost: \((end - beginTime) * 1000) ms")
                    DispatchQueue.main.async {
                        self.previewView.display(sampleBuffer: buffer)
                    }
                    time += 1.0 / (self.bl_decoder?.videoOriginalFPS ?? 30.0)
//                    Thread.sleep(forTimeInterval: 0.02)
                    beginTime = CFAbsoluteTimeGetCurrent()
                }
            }
        } else {
            reloadCustomVideo()
        }
        
    }
    
    private func reloadCustomVideo() {
        
        func prepareDecoder(filePath: String, format: AVFormatReader?) -> Bool {
            guard let format, let formatContext = format.formatContext else {
                return false
            }
            switch decoderType {
            case .VideoToolBox:
                self.vt_decoder = VTDecoder(uri: filePath, key: filePath)
                self.vt_decoder?.delegate = self
            case .FFmpegHardware:
                self.ff_decoder = FFDecoder(formatContext: formatContext, decodeType: .hardware, videoStreamIndex: format.videoStreamIndex)
                self.ff_decoder?.delegate = self
            case .FFmpegSoftware:
                self.ff_decoder = FFDecoder(formatContext: formatContext, decodeType: .software, videoStreamIndex: format.videoStreamIndex)
                self.ff_decoder?.delegate = self
            case .AVFoundation:
                // 实例解码器
                self.bl_decoder?.createNewReader(0)
            }
            return true
        }
        
        weak var weakSelf = self
        func decompressFrame(data: UnsafeMutablePointer<BLParseVideoDataInfo>) {
            guard let self = weakSelf else { return }
            let pts = data.pointee.timingInfo.presentationTimeStamp
            let ptsTime = self.formatTime(time: pts.seconds)
            
            let dts = data.pointee.timingInfo.decodeTimeStamp
            let dtsTime = self.formatTime(time: dts.seconds)
            
            print("🤖💼 解析数据包[\(ptsTime)]。dts：\(data.pointee.packet.pointee.dts), pts: \(data.pointee.packet.pointee.pts) pos: \(data.pointee.packet.pointee.pos), size: \(data.pointee.packet.pointee.size), end: \(data.pointee.packet.pointee.pos + Int64(data.pointee.packet.pointee.size))")
            let interval: TimeInterval = 1.0 / 15.0
            
            switch self.decoderType {
            case .VideoToolBox:
                self.vt_decoder?.startDecodeVideoData(OpaquePointer(data))
            case .FFmpegHardware, .FFmpegSoftware:
                self.ff_decoder?.startDecodeVideoData(with: data.pointee.packet.pointee)
            case .AVFoundation:
                break
            }
            
//            Thread.sleep(forTimeInterval: interval)
        }
        
        guard let filePath = getVideoPath() else {
            return
        }
        var beginTime = CFAbsoluteTimeGetCurrent()
        self.formatReader = AVFormatReader(path: filePath)
        var end = CFAbsoluteTimeGetCurrent()
        print("🦁 [\(self.decoderType)] 环节 - 创建Reader - 读取轨道信息 cost: \((end - beginTime) * 1000) ms")
        let beginTime1 = CFAbsoluteTimeGetCurrent()
        guard prepareDecoder(filePath: filePath, format: self.formatReader) else {
            return
        }
        end = CFAbsoluteTimeGetCurrent()
        print("🦁 [\(self.decoderType)] 环节 - 创建解码器 cost: \((end - beginTime1) * 1000) ms")
        print("🦁 [\(self.decoderType)] 创建解码器总耗时 cost: \((end - beginTime) * 1000) ms")
        beginTime = CFAbsoluteTimeGetCurrent()
        formatReader?.readPacket { [weak self] data, isFinish in
            guard !isFinish, let self else { return }
            guard let data = data else { return }
            let b1 = CFAbsoluteTimeGetCurrent()
            decompressFrame(data: data)
            let end = CFAbsoluteTimeGetCurrent()
            print("🦁 [\(self.decoderType)] decode packet cost: \((end - b1) * 1000) ms")
            print("🦁🦁 [\(self.decoderType)] decode frame total cost: \((end - beginTime) * 1000) ms")
//            Thread.sleep(forTimeInterval: 0.02)
            beginTime = CFAbsoluteTimeGetCurrent()
        }
    }
    
    private func formatTime(time: Double) -> String {
        guard !time.isNaN else { return "Nan" }
        // 设置当前显示的时间
        let showTime = Int(time) // 向下取整
        if showTime < 60 * 60 {
            let minute = showTime / 60
            let second = time.truncatingRemainder(dividingBy: 60)
            return String(format: "%02d:%02.2f", minute, second)
        } else {
            let hour = showTime / (60 * 60)
            let minute = (showTime - hour * 60 * 60) / 60
            let second = time.truncatingRemainder(dividingBy: 60)
            return String(format: "%02d:%02d:%02d", hour, minute, second)
        }
    }

    private func stopDecoder() {
        formatReader?.stopRead()
        ff_decoder?.stop()
        vt_decoder?.stop()
        bl_decoder = nil
    }
}

extension ViewController: VideoDecoderDelegate, FFVideoDecoderDelegate {
    
    func getVideoDecodeDataCallback(_ sampleBuffer: CMSampleBuffer, isFirstFrame: Bool) {
//        print("🦁 VTDecode Finish.")
        DispatchQueue.main.async {
            self.previewView.display(sampleBuffer: sampleBuffer)
        }
    }
    
    func getDecodeVideoData(byFFmpeg sampleBuffer: CMSampleBuffer) {
        print("🦁 ffmpeg Finish.")
        DispatchQueue.main.async {
            self.previewView.display(sampleBuffer: sampleBuffer)
        }
    }
    
}

