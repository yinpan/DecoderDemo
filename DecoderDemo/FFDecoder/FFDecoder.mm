//
//  FFDecoder.m
//  DecoderDemo
//
//  Created by yinpan on 2024/6/5.
//

#import "FFDecoder.h"
#import "Log-Define.h"

@interface FFDecoder ()
{
    FFmpegDecodeType m_decodeType;
    
    AVFormatContext *m_formatContext;
    AVCodecContext  *m_videoCodecContext;
    AVFrame         *m_videoFrame;
    
    int     m_videoStreamIndex;
    BOOL    m_isFindIDR;
    int64_t m_base_time;
}

@end

@implementation FFDecoder

#pragma mark - C Function

static int DecodeGetAVStreamFPSTimeBase(AVStream *st) {
    CGFloat fps, timebase = 0.0;
    
    if (st->time_base.den && st->time_base.num)
        timebase = av_q2d(st->time_base);
    else if(st->codec->time_base.den && st->codec->time_base.num)
        timebase = av_q2d(st->codec->time_base);
    
    if (st->avg_frame_rate.den && st->avg_frame_rate.num)
        fps = av_q2d(st->avg_frame_rate);
    else if (st->r_frame_rate.den && st->r_frame_rate.num)
        fps = av_q2d(st->r_frame_rate);
    else
        fps = 1.0 / timebase;
    
    return fps;
}

#pragma mark - Lifecycle
- (instancetype)initWithFormatContext:(AVFormatContext *)formatContext decodeType:(FFmpegDecodeType)decodeType videoStreamIndex:(int)videoStreamIndex {
    if (self = [super init]) {
        m_decodeType        = decodeType;
        m_formatContext     = formatContext;
        m_videoStreamIndex  = videoStreamIndex;
        
        m_isFindIDR = NO;
        m_base_time = 0;
        
        [self initDecoder];
    }
    return self;
}

- (void)initDecoder {
    AVStream *videoStream = m_formatContext->streams[m_videoStreamIndex];
    m_videoCodecContext = [self createDecoderWithContext:m_formatContext
                                              decodeType:m_decodeType
                                                  stream:videoStream
                                        videoStreamIndex:m_videoStreamIndex];
    
    if (!m_videoCodecContext) {
        NSLogError(@"create video codec failed");
        return;
    }

    // Get video frame
    m_videoFrame = av_frame_alloc();
    if (!m_videoFrame) {
        NSLogError(@"alloc video frame failed");
        avcodec_close(m_videoCodecContext);
    }

}

#pragma mark - Public
- (void)startDecodeVideoDataWithAVPacket:(AVPacket)packet {
    if (packet.flags == 1 && m_isFindIDR == NO) {
        m_isFindIDR = YES;
        m_base_time =  m_videoFrame->pts;
    }
    
    if (m_isFindIDR == YES) {
        [self startDecodeVideoDataWithAVPacket:packet
                             videoCodecContext:m_videoCodecContext
                                     baseFrame:m_videoFrame
                                      baseTime:m_base_time
                              videoStreamIndex:m_videoStreamIndex];
    }
}

- (void)stopDecoder {
    [self freeAllResources];
}

+ (void)createHwctx:(AVCodecContext *)context
{
    const char *codecName = av_hwdevice_get_type_name(AV_HWDEVICE_TYPE_VIDEOTOOLBOX);
    enum AVHWDeviceType type = av_hwdevice_find_type_by_name(codecName);
    if (type != AV_HWDEVICE_TYPE_VIDEOTOOLBOX) {
        NSLogError(@"Not find hardware codec.");
        return;
    }
    
    AVBufferRef *codec_buf;
    int err = av_hwdevice_ctx_create(&codec_buf, type, NULL, NULL, 0);
    if (err < 0) {
        NSLog(@"[ERROR] Init Hardware Decoder FAILED, Fallback to Software Decoder.");
        return;
    }
    context->hw_device_ctx = av_buffer_ref(codec_buf);
}

// 硬件解码初始化函数
static enum AVPixelFormat hw_pix_fmt = AV_PIX_FMT_VIDEOTOOLBOX;

// 获取硬件解码的像素格式
+ (enum AVPixelFormat)getHWFormat:(AVCodecContext *)ctx pixFmts:(const enum AVPixelFormat *)pix_fmts
{
    for (const enum AVPixelFormat *p = pix_fmts; *p != -1; p++) {
        if (*p == hw_pix_fmt)
            return *p;
    }
    fprintf(stderr, "Failed to get HW surface format.\n");
    return AV_PIX_FMT_NONE;
}

- (AVCodecContext *)createDecoderWithContext:(AVFormatContext *)formatContext decodeType:(FFmpegDecodeType)decodeType stream:(AVStream *)stream videoStreamIndex:(int)videoStreamIndex {
    
    AVCodecParameters *codecParameters = formatContext->streams[videoStreamIndex]->codecpar;
    AVCodec *codec = NULL;
    
    int ret = av_find_best_stream(formatContext, AVMEDIA_TYPE_VIDEO, -1, -1, &codec, 0);
    if (ret < 0)
    {
        NSLogError(@"av_find_best_stream faliture");
        return NULL;
    }
    
    if (!codec) 
    {
        NSLog(@"Hardware codec not found");
        avformat_close_input(&formatContext);
        return NULL;
    }
    
    AVCodecContext *codecContext = avcodec_alloc_context3(codec);
    if (decodeType == FFmpegDecodeTypeHardware)
    {
        [FFDecoder createHwctx:codecContext];
        codecContext->get_format = get_hw_format;
    }
    else
    {
        // 设置软解码输出的像素格式
        codecContext->pix_fmt = AV_PIX_FMT_YUV420P;  // 示例中设置为 YUV420P
    }
    avcodec_parameters_to_context(codecContext, codecParameters);
    
    if (avcodec_open2(codecContext, codec, NULL) < 0) 
    {
        NSLog(@"Could not open codec");
        avcodec_free_context(&codecContext);
        avformat_close_input(&formatContext);
        return NULL;
    }
    
    return codecContext;
}

- (void)startDecodeVideoDataWithAVPacket:(AVPacket)packet
                       videoCodecContext:(AVCodecContext *)codecCtx
                               baseFrame:(AVFrame *)videoFrame
                                baseTime:(int64_t)baseTime
                        videoStreamIndex:(int)videoStreamIndex
{
    
    Float64 current_timestamp = [self getCurrentTimestamp];
    AVStream *videoStream = m_formatContext->streams[videoStreamIndex];
    int fps = DecodeGetAVStreamFPSTimeBase(videoStream);

//    // 计算 BGRA 格式的缓冲区大小
//    int bgraBufferSize = av_image_get_buffer_size(AV_PIX_FMT_BGRA, codecCtx->width, codecCtx->height, 1);
//    uint8_t *bgraBuffer = (uint8_t *)av_malloc(bgraBufferSize);
//    if (!bgraBuffer) {
//        NSLogError(@"Error allocating BGRA buffer\n");
//        return;
//    }
//
//    // 创建 SwsContext 对象，用于像素格式转换
//    av_image_fill_arrays(bgraFrame->data, bgraFrame->linesize, bgraBuffer, AV_PIX_FMT_BGRA, codecCtx->width, codecCtx->height, 1);
//
//    if (!swsCtx) {
//        NSLogError(@"Error creating sws context\n");
//        return;
//    }
    
    CMVideoFormatDescriptionRef videoInfo = NULL;
    CMVideoFormatDescriptionCreate(kCFAllocatorDefault,
                                   kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
                                   codecCtx->width,
                                   codecCtx->height,
                                   NULL,
                                   &videoInfo);
    
    // Create CMVideoFormatDescription
    CFAbsoluteTime begin = CFAbsoluteTimeGetCurrent();
    avcodec_send_packet(codecCtx, &packet);
    while (0 == avcodec_receive_frame(codecCtx, videoFrame))
    {
        CFAbsoluteTime end = CFAbsoluteTimeGetCurrent();
        NSLogDebug(@"🤖 avcodec_send_packet cost: %.3lf ms", (end - begin) * 1000);
        begin = CFAbsoluteTimeGetCurrent();
        // 将解码后的帧转换为 BGRA 格式
//        sws_scale(swsCtx, videoFrame->data, videoFrame->linesize, 0, codecCtx->height, bgraFrame->data, bgraFrame->linesize);
        
        /**
         data 数组
         data 数组中的每个指针指向帧数据的一个平面。具体有多少个平面以及它们的含义取决于像素格式。例如，对于常见的 YUV420P 格式：

         data[0]: 指向 Y 平面（亮度）。
         data[1]: 指向 U 平面（色度，蓝色差分）。
         data[2]: 指向 V 平面（色度，红色差分）。
         其他的像素格式可能有不同的平面布局。例如，对于 RGB 格式，通常只有一个平面，所有颜色数据都在一起。
         
         当 VideoToolBox 解码时，返回的是 data[3] 才有值。格式为：videotoolbox_vld
         data[2]: 指向 V 平面（色度，红色差分）。
         */
        
        // 获取 AVFrame 的像素格式
        
        enum AVPixelFormat pix_fmt = (enum AVPixelFormat)videoFrame->format;
        
        // 将像素格式转换为字符串
        const char *pix_fmt_name = av_get_pix_fmt_name(pix_fmt);
        
        // 打印像素格式
        if (pix_fmt_name) {
            NSLogDebug(@"Pixel format: %s\n", pix_fmt_name);
        } else {
            NSLogDebug(@"Unknown pixel format: %d\n", pix_fmt);
        }
        
        CMSampleBufferRef sampleBufferRef = NULL;
        if (pix_fmt == AV_PIX_FMT_VIDEOTOOLBOX)
        {
            CVPixelBufferRef pixelBuffer = (CVPixelBufferRef)videoFrame->data[3];
            CMTime presentationTimeStamp = kCMTimeInvalid;
            int64_t originPTS = videoFrame->pts;
            int64_t newPTS    = originPTS - baseTime;
            presentationTimeStamp = CMTimeMakeWithSeconds(current_timestamp + newPTS * av_q2d(videoStream->time_base), fps);
            
            sampleBufferRef = [self convertCVImageBufferRefToCMSampleBufferRef:(CVPixelBufferRef)pixelBuffer
                                                                       withPresentationTimeStamp:presentationTimeStamp];
            if (sampleBufferRef) 
            {
                if ([self.delegate respondsToSelector:@selector(getDecodeVideoDataByFFmpeg:)]) {
                    [self.delegate getDecodeVideoDataByFFmpeg:sampleBufferRef];
                }
                CFRelease(sampleBufferRef);
            }
        }
        else
        {
            CVPixelBufferRef pixelBuffer = [self pixelBufferFromAVFrame:videoFrame];
            if (pixelBuffer)
            {
                sampleBufferRef = [self sampleBufferFromPixelBuffer:pixelBuffer videoInfo:videoInfo];
            }
            if (sampleBufferRef) 
            {
                if ([self.delegate respondsToSelector:@selector(getDecodeVideoDataByFFmpeg:)]) {
                    [self.delegate getDecodeVideoDataByFFmpeg:sampleBufferRef];
                }
                CFRelease(sampleBufferRef);
            }
            if (pixelBuffer) 
            {
                CFRelease(pixelBuffer);
            }
        }
    }
    if (videoInfo) 
    {
        CFRelease(videoInfo);
    }
}

- (void)freeAllResources {
    if (m_videoCodecContext) {
        avcodec_send_packet(m_videoCodecContext, NULL);
        avcodec_flush_buffers(m_videoCodecContext);
        
        if (m_videoCodecContext->hw_device_ctx) {
            av_buffer_unref(&m_videoCodecContext->hw_device_ctx);
            m_videoCodecContext->hw_device_ctx = NULL;
        }
        avcodec_close(m_videoCodecContext);
        m_videoCodecContext = NULL;
    }
    
//    if (m_swsCtx) {
//        sws_freeContext(m_swsCtx);
//        m_swsCtx = NULL;
//    }
    
    if (m_videoFrame) {
        // av_frame_free(m_videoFrame);
        av_free(m_videoFrame);
        m_videoFrame = NULL;
    }
//    
//    if (m_bgraFrame) {
//        // av_frame_free(m_bgraFrame);
//        av_free(m_bgraFrame);
//        m_bgraFrame = NULL;
//    }
    
//    if (m_bgraBuffer) {
//        av_free(m_bgraBuffer);
//        m_bgraBuffer = NULL;
//    }
//    
}

#pragma mark - Other
- (CMSampleBufferRef)convertCVImageBufferRefToCMSampleBufferRef:(CVImageBufferRef)pixelBuffer withPresentationTimeStamp:(CMTime)presentationTimeStamp
{
    CVPixelBufferLockBaseAddress(pixelBuffer, 0);
    CMSampleBufferRef newSampleBuffer = NULL;
    OSStatus res = 0;
    
    CMSampleTimingInfo timingInfo;
    timingInfo.duration              = kCMTimeInvalid;
    timingInfo.decodeTimeStamp       = presentationTimeStamp;
    timingInfo.presentationTimeStamp = presentationTimeStamp;
    
    CMVideoFormatDescriptionRef videoInfo = NULL;
    res = CMVideoFormatDescriptionCreateForImageBuffer(NULL, pixelBuffer, &videoInfo);
    if (res != 0) {
        NSLogError(@"Create video format description failed!");
        CVPixelBufferUnlockBaseAddress(pixelBuffer, 0);
        return NULL;
    }
    
    res = CMSampleBufferCreateForImageBuffer(kCFAllocatorDefault,
                                             pixelBuffer,
                                             true,
                                             NULL,
                                             NULL,
                                             videoInfo,
                                             &timingInfo, &newSampleBuffer);
    
    CFRelease(videoInfo);
    if (res != 0) {
        NSLogError(@"Create sample buffer failed!");
        CVPixelBufferUnlockBaseAddress(pixelBuffer, 0);
        return NULL;
        
    }
    
    CVPixelBufferUnlockBaseAddress(pixelBuffer, 0);
    return newSampleBuffer;
}

- (CVPixelBufferRef)pixelBufferFromAVFrame:(AVFrame *)frame 
{
    NSDictionary *pixelBufferAttributes = @{
        (id)kCVPixelBufferIOSurfacePropertiesKey: @{}
    };

    CVPixelBufferRef pixelBuffer = NULL;
    CVReturn status = CVPixelBufferCreate(kCFAllocatorDefault,
                                          frame->width,
                                          frame->height,
                                          kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
                                          (__bridge CFDictionaryRef)pixelBufferAttributes,
                                          &pixelBuffer);

    if (status != kCVReturnSuccess) {
        NSLog(@"Unable to create CVPixelBuffer.");
        return NULL;
    }

    CVPixelBufferLockBaseAddress(pixelBuffer, 0);

    // Copy Y plane
    uint8_t *yPlane = (uint8_t *)CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0);
    for (int i = 0; i < frame->height; i++) {
        memcpy(yPlane + i * CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0),
               frame->data[0] + i * frame->linesize[0],
               frame->width);
    }

    // Copy UV plane
    uint8_t *uvPlane = (uint8_t *)CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 1);
    for (int i = 0; i < frame->height / 2; i++) {
        memcpy(uvPlane + i * CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 1),
               frame->data[1] + i * frame->linesize[1],
               frame->width);
    }

    CVPixelBufferUnlockBaseAddress(pixelBuffer, 0);
    return pixelBuffer;
}

- (CMSampleBufferRef)sampleBufferFromPixelBuffer:(CVPixelBufferRef)pixelBuffer videoInfo:(CMVideoFormatDescriptionRef)videoInfo
{
    CMSampleBufferRef sampleBuffer = NULL;
    CMTime timestamp = CMTimeMake(1, 30);  // Example timestamp, you should set this to the actual frame timestamp
    CMSampleTimingInfo timingInfo = { timestamp, kCMTimeInvalid, kCMTimeInvalid };
    OSStatus status = CMSampleBufferCreateForImageBuffer(kCFAllocatorDefault,
                                                         pixelBuffer,
                                                         true,
                                                         NULL,
                                                         NULL,
                                                         videoInfo,
                                                         &timingInfo,
                                                         &sampleBuffer);
    if (status != noErr) {
        NSLog(@"Unable to create CMSampleBuffer.");
        return NULL;
    }
    return sampleBuffer;
}

- (Float64)getCurrentTimestamp {
    CMClockRef hostClockRef = CMClockGetHostTimeClock();
    CMTime hostTime = CMClockGetTime(hostClockRef);
    return CMTimeGetSeconds(hostTime);
}

// 获取硬件解码的像素格式
static enum AVPixelFormat get_hw_format(AVCodecContext *ctx, const enum AVPixelFormat *pix_fmts) {
    for (const enum AVPixelFormat *p = pix_fmts; *p != -1; p++) {
        if (*p == hw_pix_fmt)
            return *p;
    }
    fprintf(stderr, "Failed to get HW surface format.\n");
    return AV_PIX_FMT_NONE;
}


@end

