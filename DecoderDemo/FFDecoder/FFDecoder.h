//
//  FFDecoder.h
//  DecoderDemo
//
//  Created by yinpan on 2024/6/5.
//

#import <Foundation/Foundation.h>
#import <CoreMedia/CoreMedia.h>

#ifdef __cplusplus
extern "C" {
#endif
    
#include "libavformat/avformat.h"
#include "libavcodec/avcodec.h"
#include "libavutil/avutil.h"
#include "libswscale/swscale.h"
#include "libswresample/swresample.h"
#include "libavutil/opt.h"

#include <libavutil/samplefmt.h>
#include <libavutil/imgutils.h>
#include <libavcodec/avcodec.h>
#include <libavformat/avformat.h>
    
#ifdef __cplusplus
};
#endif

NS_ASSUME_NONNULL_BEGIN

@protocol FFVideoDecoderDelegate <NSObject>

@optional

- (void)getDecodeVideoDataByFFmpeg:(CMSampleBufferRef)sampleBuffer;

@end

typedef NS_ENUM(NSInteger, FFmpegDecodeType) {
    FFmpegDecodeTypeSoftware,
    FFmpegDecodeTypeHardware
};

@interface FFDecoder : NSObject

@property (weak, nonatomic) id<FFVideoDecoderDelegate> delegate;

- (instancetype)initWithFormatContext:(AVFormatContext *)formatContext decodeType:(FFmpegDecodeType)decodeType videoStreamIndex:(int)videoStreamIndex;
- (void)startDecodeVideoDataWithAVPacket:(AVPacket)packet;
- (void)stopDecoder;

+ (enum AVPixelFormat)getHWFormat:(AVCodecContext *)ctx pixFmts:(const enum AVPixelFormat *)pix_fmts;

@end

NS_ASSUME_NONNULL_END
