//
//  MetalYUVView.swift
//  DecoderDemo
//
//  Created by yinpan on 2024/6/5.
//

import MetalKit
import CoreVideo

class MetalYUVView: MTKView {
    
    private var commandQueue: MTLCommandQueue!
    private var planarPipelineState: MTLRenderPipelineState!
    private var BiPlanarPipelineState: MTLRenderPipelineState!
    private var yTexture: MTLTexture?
    private var uTexture: MTLTexture?
    private var vTexture: MTLTexture?

    required init(coder: NSCoder) {
        super.init(coder: coder)
        self.device = MTLCreateSystemDefaultDevice()
        self.commandQueue = self.device?.makeCommandQueue()
        self.setupPipeline()
    }

    override init(frame frameRect: CGRect, device: MTLDevice?) {
        super.init(frame: frameRect, device: device)
        self.device = device
        self.commandQueue = self.device?.makeCommandQueue()
        self.setupPipeline()
    }

    private func setupPipeline() {
        guard let device = self.device else { return }
        
        let defaultLibrary = device.makeDefaultLibrary()
        let vertexFunction = defaultLibrary?.makeFunction(name: "yuvVertexShader")
        let fragmentFunction = defaultLibrary?.makeFunction(name: "BiYuvFragmentShader")
        
        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        pipelineDescriptor.colorAttachments[0].pixelFormat = self.colorPixelFormat
        
        do {
            planarPipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
        } catch {
            print("Error occurred when creating render pipeline state: \(error)")
        }
        
        let BipipelineDescriptor = MTLRenderPipelineDescriptor()
        BipipelineDescriptor.vertexFunction = vertexFunction
        BipipelineDescriptor.fragmentFunction = defaultLibrary?.makeFunction(name: "yuvFragmentShader")
        BipipelineDescriptor.colorAttachments[0].pixelFormat = self.colorPixelFormat
        
        do {
            BiPlanarPipelineState = try device.makeRenderPipelineState(descriptor: BipipelineDescriptor)
        } catch {
            print("Error occurred when creating render pipeline state: \(error)")
        }
        
    }
    
    func display(sampleBuffer: CMSampleBuffer) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }
        display(pixelBuffer: pixelBuffer)
    }

    func display(pixelBuffer: CVPixelBuffer) {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let pixelFormat = CVPixelBufferGetPixelFormatType(pixelBuffer)
        
        if pixelFormat == kCVPixelFormatType_420YpCbCr8Planar {
            // Planar YUV (I420)
            let yData = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0)!
            let uData = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 1)!
            let vData = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 2)!
            let yBytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)
            let uBytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 1)
            let vBytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 2)
            setupTextures(yData: yData, uData: uData, vData: vData, yBytesPerRow: yBytesPerRow, uBytesPerRow: uBytesPerRow, vBytesPerRow: vBytesPerRow, width: width, height: height)
        } else if pixelFormat == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange || pixelFormat == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange {
            // Bi-Planar YUV (NV12, NV21)
            let yData = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0)!
            let uvData = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 1)!
            let yBytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)
            let uvBytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 1)
            setupTextures(yData: yData, uvData: uvData, yBytesPerRow: yBytesPerRow, uvBytesPerRow: uvBytesPerRow, width: width, height: height)
        }
        
        CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly)
        
        self.draw()
    }

    private func setupTextures(yData: UnsafeRawPointer, uData: UnsafeRawPointer, vData: UnsafeRawPointer, yBytesPerRow: Int, uBytesPerRow: Int, vBytesPerRow: Int, width: Int, height: Int) {
        guard let device = self.device else { return }

        // Create Y texture
        let yTextureDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .r8Unorm, width: width, height: height, mipmapped: false)
        yTexture = device.makeTexture(descriptor: yTextureDescriptor)
        yTexture?.replace(region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0, withBytes: yData, bytesPerRow: yBytesPerRow)
        
        // Create U and V textures
        let uvTextureDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .r8Unorm, width: width / 2, height: height / 2, mipmapped: false)
        uTexture = device.makeTexture(descriptor: uvTextureDescriptor)
        vTexture = device.makeTexture(descriptor: uvTextureDescriptor)
        
        uTexture?.replace(region: MTLRegionMake2D(0, 0, width / 2, height / 2), mipmapLevel: 0, withBytes: uData, bytesPerRow: uBytesPerRow)
        vTexture?.replace(region: MTLRegionMake2D(0, 0, width / 2, height / 2), mipmapLevel: 0, withBytes: vData, bytesPerRow: vBytesPerRow)
    }

    private func setupTextures(yData: UnsafeRawPointer, uvData: UnsafeRawPointer, yBytesPerRow: Int, uvBytesPerRow: Int, width: Int, height: Int) {
        guard let device = self.device else { return }

        // Create Y texture
        let yTextureDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .r8Unorm, width: width, height: height, mipmapped: false)
        yTexture = device.makeTexture(descriptor: yTextureDescriptor)
        yTexture?.replace(region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0, withBytes: yData, bytesPerRow: yBytesPerRow)
        
        // Create UV texture
        let uvTextureDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rg8Unorm, width: width / 2, height: height / 2, mipmapped: false)
        uTexture = device.makeTexture(descriptor: uvTextureDescriptor)
        uTexture?.replace(region: MTLRegionMake2D(0, 0, width / 2, height / 2), mipmapLevel: 0, withBytes: uvData, bytesPerRow: uvBytesPerRow)
        
        vTexture = nil
    }

    override func draw(_ rect: CGRect) {
        super.draw(rect)
        render()
    }

    private func render() {

        guard let drawable = currentDrawable,
              let yTexture = yTexture,
              let uTexture = uTexture,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let renderPassDescriptor = currentRenderPassDescriptor,
              let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else { return }
        
        if let pipelineState = planarPipelineState, let vTexture {
            renderEncoder.setRenderPipelineState(pipelineState)
            
            // Set the textures
            renderEncoder.setFragmentTexture(yTexture, index: 0)
            renderEncoder.setFragmentTexture(uTexture, index: 1)
            renderEncoder.setFragmentTexture(vTexture, index: 2)
            
            // Draw a fullscreen quad
            renderEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
            
            renderEncoder.endEncoding()
            commandBuffer.present(drawable)
            commandBuffer.commit()
        } else if let pipelineState = BiPlanarPipelineState, vTexture == nil {
            renderEncoder.setRenderPipelineState(pipelineState)
            
            // Set the textures
            renderEncoder.setFragmentTexture(yTexture, index: 0)
            renderEncoder.setFragmentTexture(uTexture, index: 1)
            
            
            // Draw a fullscreen quad
            renderEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
            
            renderEncoder.endEncoding()
            commandBuffer.present(drawable)
            commandBuffer.commit()
        }
       
    }
}
