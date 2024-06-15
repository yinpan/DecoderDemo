//
//  VTDecoder.m
//  DecoderDemo
//
//  Created by yinpan on 2024/6/4.
//

#import "VTDecoder.h"
#import <VideoToolbox/VideoToolbox.h>
#import <pthread.h>
#import "Log-Define.h"

typedef struct {
    CVPixelBufferRef outputPixelbuffer;
    int              rotate;
    Float64          pts;
    int              fps;
    int              source_index;
} AVDecodeVideoInfo;

typedef struct {
    uint8_t *vps;
    uint8_t *sps;
    
    // H265有前后两个pps
    uint8_t *f_pps;
    uint8_t *r_pps;
    
    int vps_size;
    int sps_size;
    int f_pps_size;
    int r_pps_size;
    
    Float64 last_decode_pts;
} DecoderInfo;

@interface VTDecoder ()
{
    VTDecompressionSessionRef   _decoderSession;
    CMVideoFormatDescriptionRef _decoderFormatDescription;

    DecoderInfo  _decoderInfo;
    pthread_mutex_t _decoder_lock;
    
    uint8_t *_lastExtraData;
    int     _lastExtraDataSize;
    
    BOOL _isFirstFrame;
    dispatch_semaphore_t semaphore;
}

@property (nonatomic, copy) NSString *fileURI;
@property (nonatomic, copy) NSString *key;

@end

@implementation VTDecoder

- (instancetype)initURI:(NSString *)uri key:(NSString *)key
{
    if (self = [super init])
    {
        self.fileURI = uri;
        self.key = key;
        _decoderInfo = {
            .vps = NULL,
            .sps = NULL,
            .f_pps = NULL,
            .r_pps = NULL,
            .vps_size = 0,
            .sps_size = 0,
            .f_pps_size = 0,
            .r_pps_size = 0,
            .last_decode_pts = 0,
        };
        _isFirstFrame = YES;
        semaphore = dispatch_semaphore_create(1); // 创建一个初始值为0的信号量
        pthread_mutex_init(&_decoder_lock, NULL);
    }
    return self;
}

- (CMSampleBufferRef)decodeWithTime:(double)targetTime
{
    return nil;
}

- (void)updateOutuptSize:(CGSize)size
{
    
}

- (void)clear
{
    
}

#pragma mark - Callback
static void VideoDecoderCallback(void *decompressionOutputRefCon, void *sourceFrameRefCon, OSStatus status, VTDecodeInfoFlags infoFlags, CVImageBufferRef pixelBuffer, CMTime presentationTimeStamp, CMTime presentationDuration) {
    
    CFAbsoluteTime beginTime = CFAbsoluteTimeGetCurrent();
    
    AVDecodeVideoInfo *sourceRef = (AVDecodeVideoInfo *)sourceFrameRefCon;
    
    if (pixelBuffer == NULL) {
        NSLogError(@"pixelbuffer is NULL status = %d", status);
        if (sourceRef) {
            free(sourceRef);
        }
        return;
    }
    
    VTDecoder *decoder = (__bridge VTDecoder *)decompressionOutputRefCon;
    
    CMSampleTimingInfo sampleTime = {
        .presentationTimeStamp  = presentationTimeStamp,
        .decodeTimeStamp        = presentationTimeStamp
    };
    
    CMSampleBufferRef samplebuffer = [decoder createSampleBufferFromPixelbuffer:pixelBuffer
                                                                    videoRotate:sourceRef->rotate
                                                                     timingInfo:sampleTime];
    CFAbsoluteTime endTime = CFAbsoluteTimeGetCurrent();
    NSLog(@"🟢 输出解码数据后处理 cost: %.f ms", (endTime - beginTime) * 1000);
    NSLog(@"🟢 退出");
//    dispatch_semaphore_signal(decoder->semaphore);
    
    if (samplebuffer) {
        if ([decoder.delegate respondsToSelector:@selector(getVideoDecodeDataCallback:isFirstFrame:)]) {
            [decoder.delegate getVideoDecodeDataCallback:samplebuffer isFirstFrame:decoder->_isFirstFrame];
            if (decoder->_isFirstFrame) {
                decoder->_isFirstFrame = NO;
            }
        }
        CFRelease(samplebuffer);
    }
    
    if (sourceRef) {
        free(sourceRef);
    }
}

#pragma mark - life cycle

- (void)dealloc {
    _delegate = nil;
    [self destoryDecoder];
}

#pragma mark - Public
- (void)startDecodeVideoData:(BLParseVideoDataInfo *)videoInfo
{
    // 等待信号量
//    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
    NSLog(@"🟢 进入");
    CFAbsoluteTime beginTime = CFAbsoluteTimeGetCurrent();
    // get extra data
    if (videoInfo->extraData && videoInfo->extraDataSize) {
        uint8_t *extraData = videoInfo->extraData;
        int     size       = videoInfo->extraDataSize;
        
        BOOL isNeedUpdate = [self isNeedUpdateExtraDataWithNewExtraData:extraData
                                                                newSize:size
                                                               lastData:&_lastExtraData
                                                               lastSize:&_lastExtraDataSize];
        if (isNeedUpdate) {
            NSLogError(@"update extra data");
            [self getNALUInfoWithVideoFormat:videoInfo->videoFormat
                                   extraData:extraData
                               extraDataSize:size
                                 decoderInfo:&_decoderInfo];
        }
    }
    
    // create decoder
    if (!_decoderSession) {
        _decoderSession = [self createDecoderWithVideoInfo:videoInfo
                                              videoDescRef:&_decoderFormatDescription
                                               videoFormat:kCVPixelFormatType_420YpCbCr8BiPlanarFullRange //目前方法内部未使用该传入的字段，不进行格式转换，可以节约约2ms+的耗时
                                                      lock:_decoder_lock
                                                  callback:VideoDecoderCallback
                                               decoderInfo:_decoderInfo];
    }
    
//    pthread_mutex_lock(&_decoder_lock);
    if (!_decoderSession) {
//        pthread_mutex_unlock(&_decoder_lock);
        return;
    }
    
    /*  If open B frame, the code will not be used.
    if(_decoderInfo.last_decode_pts != 0 && videoInfo->pts <= _decoderInfo.last_decode_pts){
        log4cplus_error(kModuleName, "decode timestamp error ! current:%f, last:%f",videoInfo->pts, _decoderInfo.last_decode_pts);
        pthread_mutex_unlock(&_decoder_lock);
        return;
    }
     */
    
    _decoderInfo.last_decode_pts = videoInfo->pts;
    
//    pthread_mutex_unlock(&_decoder_lock);
    
    // start decode
    [self startDecode:videoInfo
              session:_decoderSession
                 lock:_decoder_lock];
    CFAbsoluteTime endTime = CFAbsoluteTimeGetCurrent();
    NSLog(@"🟢 单帧解码数据总耗时 cost: %.f ms", (endTime - beginTime) * 1000);
}

- (void)stopDecoder {
    [self destoryDecoder];
}

#pragma mark - private methods

#pragma mark Create / Destory decoder
- (VTDecompressionSessionRef)createDecoderWithVideoInfo:(BLParseVideoDataInfo *)videoInfo videoDescRef:(CMVideoFormatDescriptionRef *)videoDescRef videoFormat:(OSType)videoFormat lock:(pthread_mutex_t)lock callback:(VTDecompressionOutputCallback)callback decoderInfo:(DecoderInfo)decoderInfo {
//    pthread_mutex_lock(&lock);
    
    OSStatus status;
    if (videoInfo->videoFormat == BLVideoEncodeFormatH264) {
        const uint8_t *const parameterSetPointers[2] = {decoderInfo.sps, decoderInfo.f_pps};
        const size_t parameterSetSizes[2] = {static_cast<size_t>(decoderInfo.sps_size), static_cast<size_t>(decoderInfo.f_pps_size)};
        status = CMVideoFormatDescriptionCreateFromH264ParameterSets(kCFAllocatorDefault,
                                                                     2,
                                                                     parameterSetPointers,
                                                                     parameterSetSizes,
                                                                     4,
                                                                     videoDescRef);
    }else if (videoInfo->videoFormat == BLVideoEncodeFormatH265) {
        if (decoderInfo.r_pps_size == 0) {
            const uint8_t *const parameterSetPointers[3] = {decoderInfo.vps, decoderInfo.sps, decoderInfo.f_pps};
            const size_t parameterSetSizes[3] = {static_cast<size_t>(decoderInfo.vps_size), static_cast<size_t>(decoderInfo.sps_size), static_cast<size_t>(decoderInfo.f_pps_size)};
            if (@available(iOS 11.0, *)) {
                status = CMVideoFormatDescriptionCreateFromHEVCParameterSets(kCFAllocatorDefault,
                                                                             3,
                                                                             parameterSetPointers,
                                                                             parameterSetSizes,
                                                                             4,
                                                                             NULL,
                                                                             videoDescRef);
            } else {
                status = -1;
                NSLogError(@"System version is too low!");
            }
        } else {
            const uint8_t *const parameterSetPointers[4] = {decoderInfo.vps, decoderInfo.sps, decoderInfo.f_pps, decoderInfo.r_pps};
            const size_t parameterSetSizes[4] = {static_cast<size_t>(decoderInfo.vps_size), static_cast<size_t>(decoderInfo.sps_size), static_cast<size_t>(decoderInfo.f_pps_size), static_cast<size_t>(decoderInfo.r_pps_size)};
            if (@available(iOS 11.0, *)) {
                status = CMVideoFormatDescriptionCreateFromHEVCParameterSets(kCFAllocatorDefault,
                                                                             4,
                                                                             parameterSetPointers,
                                                                             parameterSetSizes,
                                                                             4,
                                                                             NULL,
                                                                             videoDescRef);
            } else {
                status = -1;
                NSLogError(@"System version is too low!");
            }
        }
    }else {
        status = -1;
    }
    
    if (status != noErr) {
        NSLogError(@"NALU header error !");
//        pthread_mutex_unlock(&lock);
        [self destoryDecoder];
        return NULL;
    }
    
    uint32_t pixelFormatType = videoFormat;
    const void *keys[]       = {kCVPixelBufferPixelFormatTypeKey};
    const void *values[]     = {CFNumberCreate(NULL, kCFNumberSInt32Type, &pixelFormatType)};
    CFDictionaryRef attrs    = CFDictionaryCreate(NULL, keys, values, 1, NULL, NULL);
    
//    NSNumber *pixelFormat = @(kCVPixelFormatType_32BGRA);
//    NSNumber *metalCompatibility = @YES;
//
//    NSDictionary *pixelBufferAttributes = @{
//        (__bridge id)kCVPixelBufferPixelFormatTypeKey: pixelFormat,
//        (__bridge id)kCVPixelBufferMetalCompatibilityKey: metalCompatibility
//    };
//
//    // 创建 CFDictionaryRef
//    CFDictionaryRef attrs = (__bridge CFDictionaryRef)pixelBufferAttributes;
    
//    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
//                kCVPixelBufferWidthKey as String: videoWidth,
//                kCVPixelBufferHeightKey as String: videoHeight,
//                kCVPixelBufferMetalCompatibilityKey as String: true // 提供 Metal 兼容性
    
    VTDecompressionOutputCallbackRecord callBackRecord;
    callBackRecord.decompressionOutputCallback = callback;
    callBackRecord.decompressionOutputRefCon   = (__bridge void *)self;
    
    VTDecompressionSessionRef session;
    status = VTDecompressionSessionCreate(kCFAllocatorDefault,
                                          *videoDescRef,
                                          NULL,
                                          NULL, // attrs,
                                          &callBackRecord,
                                          &session);
    
    CFRelease(attrs);
//    pthread_mutex_unlock(&lock);
    if (status != noErr) {
        NSLogError(@"Create decoder failed");
        [self destoryDecoder];
        return NULL;
    }
    
    return session;
}

- (void)destoryDecoder {
    pthread_mutex_lock(&_decoder_lock);
    
    if (_decoderInfo.vps) {
        free(_decoderInfo.vps);
        _decoderInfo.vps_size = 0;
        _decoderInfo.vps = NULL;
    }
    
    if (_decoderInfo.sps) {
        free(_decoderInfo.sps);
        _decoderInfo.sps_size = 0;
        _decoderInfo.sps = NULL;
    }
    
    if (_decoderInfo.f_pps) {
        free(_decoderInfo.f_pps);
        _decoderInfo.f_pps_size = 0;
        _decoderInfo.f_pps = NULL;
    }
    
    if (_decoderInfo.r_pps) {
        free(_decoderInfo.r_pps);
        _decoderInfo.r_pps_size = 0;
        _decoderInfo.r_pps = NULL;
    }
    
    if (_lastExtraData) {
        free(_lastExtraData);
        _lastExtraDataSize = 0;
        _lastExtraData = NULL;
    }
    
    if (_decoderFormatDescription) {
        CFRelease(_decoderFormatDescription);
        _decoderFormatDescription = NULL;
    }
    
    if (_decoderSession) {
        VTDecompressionSessionWaitForAsynchronousFrames(_decoderSession);
        VTDecompressionSessionInvalidate(_decoderSession);
        NSLogInfo(@"Retain count is %ld", CFGetRetainCount(_decoderSession));
//        CFRelease(_decoderSession);
        _decoderSession = NULL;
    }
    
    pthread_mutex_unlock(&_decoder_lock);
}


- (BOOL)isNeedUpdateExtraDataWithNewExtraData:(uint8_t *)newData newSize:(int)newSize lastData:(uint8_t **)lastData lastSize:(int *)lastSize {
    BOOL isNeedUpdate = NO;
    if (*lastSize == 0) {
        isNeedUpdate = YES;
    }else {
        if (*lastSize != newSize) {
            isNeedUpdate = YES;
        }else {
            if (memcmp(newData, *lastData, newSize) != 0) {
                isNeedUpdate = YES;
            }
        }
    }
    
    if (isNeedUpdate) {
        [self destoryDecoder];
        
        *lastData = (uint8_t *)malloc(newSize);
        memcpy(*lastData, newData, newSize);
        *lastSize = newSize;
    }
    
    return isNeedUpdate;
}

#pragma mark Parse NALU Header
- (void)copyDataWithOriginDataRef:(uint8_t **)originDataRef newData:(uint8_t *)newData size:(int)size {
    if (*originDataRef) {
        free(*originDataRef);
        *originDataRef = NULL;
    }
    *originDataRef = (uint8_t *)malloc(size);
    memcpy(*originDataRef, newData, size);
}

- (void)getNALUInfoWithVideoFormat:(BLVideoEncodeFormat)videoFormat extraData:(uint8_t *)extraData extraDataSize:(int)extraDataSize decoderInfo:(DecoderInfo *)decoderInfo {

    uint8_t *data = extraData;
    int      size = extraDataSize;
    
    int startCodeVPSIndex  = 0;
    int startCodeSPSIndex  = 0;
    int startCodeFPPSIndex = 0;
    int startCodeRPPSIndex = 0;
    int nalu_type = 0;
    
    for (int i = 0; i < size; i ++) {
        if (i >= 3) {
            if (data[i] == 0x01 && data[i - 1] == 0x00 && data[i - 2] == 0x00 && data[i - 3] == 0x00) {
                if (videoFormat == BLVideoEncodeFormatH264) {
                    if (startCodeSPSIndex == 0) {
                        startCodeSPSIndex = i;
                    }
                    if (i > startCodeSPSIndex) {
                        startCodeFPPSIndex = i;
                    }
                }else if (videoFormat == BLVideoEncodeFormatH265) {
                    if (startCodeVPSIndex == 0) {
                        startCodeVPSIndex = i;
                        continue;
                    }
                    if (i > startCodeVPSIndex && startCodeSPSIndex == 0) {
                        startCodeSPSIndex = i;
                        continue;
                    }
                    if (i > startCodeSPSIndex && startCodeFPPSIndex == 0) {
                        startCodeFPPSIndex = i;
                        continue;
                    }
                    if (i > startCodeFPPSIndex && startCodeRPPSIndex == 0) {
                        startCodeRPPSIndex = i;
                    }
                }
            }
        }
    }
    
    int spsSize = startCodeFPPSIndex - startCodeSPSIndex - 4;
    decoderInfo->sps_size = spsSize;
    
    if (videoFormat == BLVideoEncodeFormatH264) {
        int f_ppsSize = size - (startCodeFPPSIndex + 1);
        decoderInfo->f_pps_size = f_ppsSize;
        
        nalu_type = ((uint8_t)data[startCodeSPSIndex + 1] & 0x1F);
        if (nalu_type == 0x07) {
            uint8_t *sps = &data[startCodeSPSIndex + 1];
            [self copyDataWithOriginDataRef:&decoderInfo->sps newData:sps size:spsSize];
        }
        
        nalu_type = ((uint8_t)data[startCodeFPPSIndex + 1] & 0x1F);
        if (nalu_type == 0x08) {
            uint8_t *pps = &data[startCodeFPPSIndex + 1];
            [self copyDataWithOriginDataRef:&decoderInfo->f_pps newData:pps size:f_ppsSize];
        }
    } else {
        int vpsSize = startCodeSPSIndex - startCodeVPSIndex - 4;
        decoderInfo->vps_size = vpsSize;
        
        int f_ppsSize = startCodeRPPSIndex - startCodeFPPSIndex - 4;
        decoderInfo->f_pps_size = f_ppsSize;
        
        nalu_type = ((uint8_t) data[startCodeVPSIndex + 1] & 0x4F);
        if (nalu_type == 0x40) {
            uint8_t *vps = &data[startCodeVPSIndex + 1];
            [self copyDataWithOriginDataRef:&decoderInfo->vps newData:vps size:vpsSize];
        }
        
        nalu_type = ((uint8_t) data[startCodeSPSIndex + 1] & 0x4F);
        if (nalu_type == 0x42) {
            uint8_t *sps = &data[startCodeSPSIndex + 1];
            [self copyDataWithOriginDataRef:&decoderInfo->sps newData:sps size:spsSize];
        }
        
        nalu_type = ((uint8_t) data[startCodeFPPSIndex + 1] & 0x4F);
        if (nalu_type == 0x44) {
            uint8_t *pps = &data[startCodeFPPSIndex + 1];
            [self copyDataWithOriginDataRef:&decoderInfo->f_pps newData:pps size:f_ppsSize];
        }
        
        if (startCodeRPPSIndex == 0) {
            return;
        }
        
        int r_ppsSize = size - (startCodeRPPSIndex + 1);
        decoderInfo->r_pps_size = r_ppsSize;
        
        nalu_type = ((uint8_t) data[startCodeRPPSIndex + 1] & 0x4F);
        if (nalu_type == 0x44) {
            uint8_t *pps = &data[startCodeRPPSIndex + 1];
            [self copyDataWithOriginDataRef:&decoderInfo->r_pps newData:pps size:r_ppsSize];
        }
    }
}

#pragma mark Decode
- (void)startDecode:(BLParseVideoDataInfo *)videoInfo session:(VTDecompressionSessionRef)session lock:(pthread_mutex_t)lock {
//    pthread_mutex_lock(&lock);
    uint8_t *data  = videoInfo->data;
    int     size   = videoInfo->dataSize;
    int     rotate = videoInfo->videoRotate;
    CMSampleTimingInfo timingInfo = videoInfo->timingInfo;
    
    uint8_t *tempData = (uint8_t *)malloc(size);
    memcpy(tempData, data, size);
    
    AVDecodeVideoInfo *sourceRef = (AVDecodeVideoInfo *)malloc(sizeof(BLParseVideoDataInfo));
    sourceRef->outputPixelbuffer  = NULL;
    sourceRef->rotate             = rotate;
    sourceRef->pts                = videoInfo->pts;
    sourceRef->fps                = videoInfo->fps;
    
    CMBlockBufferRef blockBuffer;
    OSStatus status = CMBlockBufferCreateWithMemoryBlock(kCFAllocatorDefault,
                                                         (void *)tempData,
                                                         size,
                                                         kCFAllocatorNull,
                                                         NULL,
                                                         0,
                                                         size,
                                                         0,
                                                         &blockBuffer);
    
    if (status == kCMBlockBufferNoErr) {
        CMSampleBufferRef sampleBuffer = NULL;
        const size_t sampleSizeArray[] = { static_cast<size_t>(size) };
        
        status = CMSampleBufferCreateReady(kCFAllocatorDefault,
                                           blockBuffer,
                                           _decoderFormatDescription,
                                           1,
                                           1,
                                           &timingInfo,
                                           1,
                                           sampleSizeArray,
                                           &sampleBuffer);
        
        if (status == kCMBlockBufferNoErr && sampleBuffer) {
            // 这里不设置为异步解码回调，即不设置kVTDecodeFrame_EnableAsynchronousDecompression
            
            VTDecodeFrameFlags flags   = 0; //kVTDecodeFrame_EnableAsynchronousDecompression;
            VTDecodeInfoFlags  flagOut = 0;
            OSStatus decodeStatus      = VTDecompressionSessionDecodeFrame(session,
                                                                           sampleBuffer,
                                                                           flags,
                                                                           sourceRef,
                                                                           &flagOut);
            if(decodeStatus == kVTInvalidSessionErr) {
//                pthread_mutex_unlock(&lock);
                [self destoryDecoder];
                if (blockBuffer)
                    CFRelease(blockBuffer);
                free(tempData);
                tempData = NULL;
                CFRelease(sampleBuffer);
                return;
            }
            CFRelease(sampleBuffer);
        }
    }
    
    if (blockBuffer) {
        CFRelease(blockBuffer);
    }
    
    free(tempData);
    tempData = NULL;
//    pthread_mutex_unlock(&lock);
}

#pragma mark - Other
- (CMSampleBufferRef)createSampleBufferFromPixelbuffer:(CVImageBufferRef)pixelBuffer videoRotate:(int)videoRotate timingInfo:(CMSampleTimingInfo)timingInfo {
    if (!pixelBuffer) {
        return NULL;
    }
    
    CVPixelBufferRef final_pixelbuffer = pixelBuffer;
    CMSampleBufferRef samplebuffer = NULL;
    CMVideoFormatDescriptionRef videoInfo = NULL;
    OSStatus status = CMVideoFormatDescriptionCreateForImageBuffer(kCFAllocatorDefault, final_pixelbuffer, &videoInfo);
    status = CMSampleBufferCreateForImageBuffer(kCFAllocatorDefault, final_pixelbuffer, true, NULL, NULL, videoInfo, &timingInfo, &samplebuffer);
    
    if (videoInfo != NULL) {
        CFRelease(videoInfo);
    }
    
    if (samplebuffer == NULL || status != noErr) {
        return NULL;
    }
    
    return samplebuffer;
}

- (void)resetTimestamp {
    _decoderInfo.last_decode_pts = 0;
}


@end
