//
//  VTDecoder.h
//  DecoderDemo
//
//  Created by yinpan on 2024/6/4.
//

#import <Foundation/Foundation.h>
#import <CoreMedia/CMSampleBuffer.h>
#import "AVFormatReader.h"

NS_ASSUME_NONNULL_BEGIN

@protocol VideoDecoderDelegate <NSObject>

@optional
- (void)getVideoDecodeDataCallback:(CMSampleBufferRef)sampleBuffer isFirstFrame:(BOOL)isFirstFrame;

@end

@interface VTDecoder : NSObject

@property (weak, nonatomic) id<VideoDecoderDelegate> delegate;


/**
    Start / Stop decoder
 */
- (void)startDecodeVideoData:(struct ParseVideoDataInfo *)videoInfo;
- (void)stopDecoder;


/**
    Reset timestamp when you parse a new file (only use the decoder as global var)
 */
- (void)resetTimestamp;

- (instancetype)initURI:(NSString *)uri key:(NSString *)key;

- (CMSampleBufferRef)decodeWithTime:(double)targetTime;

- (void)updateOutuptSize:(CGSize)size;

- (void)clear;


@end

NS_ASSUME_NONNULL_END
