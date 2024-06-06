//
//  AVFormatReader.h
//  DecoderDemo
//
//  Created by yinpan on 2024/6/4.
//

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <UIKit/UIKit.h>

#ifdef __cplusplus
extern "C" {
#endif
    
#include "libavformat/avformat.h"
#include "libavcodec/avcodec.h"
#include "libavutil/avutil.h"
#include "libswscale/swscale.h"
#include "libswresample/swresample.h"
#include "libavutil/opt.h"
    
#ifdef __cplusplus
};
#endif

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, BLVideoEncodeFormat) {
    BLVideoEncodeFormatH264,
    BLVideoEncodeFormatH265,
};

struct BLParseVideoDataInfo {
    uint8_t             *data;
    int                 dataSize;
    uint8_t             *extraData;
    int                 extraDataSize;
    Float64             pts;
    Float64             time_base;
    int                 videoRotate;
    int                 fps;
    CMSampleTimingInfo  timingInfo;
    BLVideoEncodeFormat videoFormat;
    int                 flags;
    AVPacket            *packet;
};

typedef struct BLParseVideoDataInfo BLParseVideoDataInfo;
typedef void (^AVFormatReadPacketBlock)(BLParseVideoDataInfo * _Nullable, BOOL);

@interface AVFormatReader : NSObject

@property (assign) int videoStreamIndex;

@property (assign) int audioStreamIndex;

@property (assign) int videoWidth;

@property (assign) int videoHeight;

@property (assign, nullable) AVFormatContext *formatContext;

@property (nonatomic, assign) int fps;

- (instancetype)initWithPath:(NSString *)path;

- (void)readPacketWithCompletionHandler:(AVFormatReadPacketBlock)handler;

- (void)stopRead;

@end

NS_ASSUME_NONNULL_END
