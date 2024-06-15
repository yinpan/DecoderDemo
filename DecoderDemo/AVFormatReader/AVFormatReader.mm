//
//  AVFormatReader.m
//  DecoderDemo
//
//  Created by yinpan on 2024/6/4.
//

#import "AVFormatReader.h"
#import "Log-Define.h"

@interface AVFormatReader ()
{
    dispatch_queue_t _readQueue;
}

@property (nonatomic, copy) NSString *filePath;

@property (nonatomic, assign, nullable) AVBitStreamFilterContext *bitFilterContext;

@property (nonatomic, assign) BOOL isCanceled;


@end

@implementation AVFormatReader

- (instancetype)initWithPath:(NSString *)path
{
    self = [super init];
    if (self) {
        self.filePath = path;
        _readQueue = dispatch_queue_create("AVFormatReader", DISPATCH_QUEUE_SERIAL);
        [self prepareWithPath:path];
        
    }
    return self;
}

- (void)prepareWithPath:(NSString *)path {
    
    self.formatContext = [self createFormatContextWithFilePath:path];
    
    if (self.formatContext == NULL)
    {
        NSLogError(@"create format context failed.");
        return;
    }
    
    // Get video stream index
    self.videoStreamIndex = [self getAVStreamIndexWithFormatContext:self.formatContext isVideoStream:YES];
    
    // Get video stream
    AVStream *videoStream = self.formatContext->streams[self.videoStreamIndex];
    self.videoWidth  = videoStream->codecpar->width;
    self.videoHeight = videoStream->codecpar->height;
    self.fps = [AVFormatReader getAVStreamFPSTimeBase:videoStream];
    NSLogInfo(@"video index:%d, width:%d, height:%d, fps:%d", self.videoStreamIndex, self.videoWidth, self.videoHeight, self.fps);
    
    BOOL isSupport = [self isSupportVideoStream:videoStream];
    if (!isSupport) {
        NSLogError(@"Not support the video stream");
        return;
    }
    
    // Get audio stream index
    self.audioStreamIndex = [self getAVStreamIndexWithFormatContext:self.formatContext isVideoStream:NO];
    
}

- (BOOL)isSupportVideoStream:(AVStream *)stream {
    
    if (stream->codecpar->codec_type == AVMEDIA_TYPE_VIDEO)
    {   // Video
        AVCodecID codecID = stream->codecpar->codec_id;
        NSLogInfo(@"Current video codec format is %s", avcodec_find_decoder(codecID)->name);
        // 目前只支持H264、H265(HEVC iOS11)编码格式的视频文件
        if (codecID == AV_CODEC_ID_H264)
        {
            return YES;
        }
        if (codecID == AV_CODEC_ID_HEVC && [[UIDevice currentDevice].systemVersion floatValue] >= 11.0)
        {
            return YES;
        }
        NSLogError(@"Not suuport the codec");
        return NO;
    }
    else
    {
        return NO;
    }
    
}

- (AVFormatContext *)createFormatContextWithFilePath:(NSString *)filePath {
    
    if (filePath == nil)
    {
        NSLogError(@"file path is NULL");
        return NULL;
    }
    
    AVFormatContext  *formatContext = NULL;
    AVDictionary     *opts          = NULL;
    
    av_dict_set(&opts, "timeout", "1000000", 0);//设置超时1秒
    
    formatContext = avformat_alloc_context();
    BOOL isSuccess = avformat_open_input(&formatContext, [filePath cStringUsingEncoding:NSUTF8StringEncoding], NULL, &opts) < 0 ? NO : YES;
    av_dict_free(&opts);
    if (!isSuccess) 
    {
        if (formatContext)
        {
            avformat_free_context(formatContext);
        }
        return NULL;
    }
    
    if (avformat_find_stream_info(formatContext, NULL) < 0) {
        avformat_close_input(&formatContext);
        return NULL;
    }
    
    return formatContext;
}

- (int)getAVStreamIndexWithFormatContext:(AVFormatContext *)formatContext isVideoStream:(BOOL)isVideoStream 
{
    int avStreamIndex = -1;
    for (int i = 0; i < formatContext->nb_streams; i++)
    {
        if ((isVideoStream ? AVMEDIA_TYPE_VIDEO : AVMEDIA_TYPE_AUDIO) == formatContext->streams[i]->codecpar->codec_type) {
            avStreamIndex = i;
        }
    }
    if (avStreamIndex == -1)
    {
        NSLogError(@"Not find video stream");
        return NULL;
    }
    else
    {
        return avStreamIndex;
    }
}

+ (int)getAVStreamFPSTimeBase:(AVStream *)stream
{
    CGFloat fps, timebase = 0.0;
    if (stream->time_base.den && stream->time_base.num)
        timebase = av_q2d(stream->time_base);
    else if(stream->codec->time_base.den && stream->codec->time_base.num)
        timebase = av_q2d(stream->codec->time_base);
    
    if (stream->avg_frame_rate.den && stream->avg_frame_rate.num)
        fps = av_q2d(stream->avg_frame_rate);
    else if (stream->r_frame_rate.den && stream->r_frame_rate.num)
        fps = av_q2d(stream->r_frame_rate);
    else
        fps = 1.0 / timebase;
    
    return fps;
}

- (void)freeAllResources 
{
    NSLogInfo(@"Free all resources!");
    if (self.formatContext)
    {
        avformat_close_input(&self->_formatContext);
        self.formatContext = NULL;
    }
    
    if (self.bitFilterContext)
    {
        av_bitstream_filter_close(self.bitFilterContext);
        self.bitFilterContext = NULL;
    }
}

- (void)stopRead
{
    self.isCanceled = YES;
}

//- (void)startParseWithCompletionHandler:(void (^)(BOOL isVideoFrame, BOOL isFinish, struct BLParseVideoDataInfo *videoInfo))handler {
//    [self startParseWithFormatContext:self.formatContext
//                     videoStreamIndex:self.videoStreamIndex
//                     audioStreamIndex:self.audioStreamIndex
//                    completionHandler:handler];
//}

- (void)readPacketWithCompletionHandler:(AVFormatReadPacketBlock)handler {
    
    self.isCanceled = NO;
    int fps = [AVFormatReader getAVStreamFPSTimeBase:self.formatContext->streams[self.videoStreamIndex]];
    dispatch_async(_readQueue, ^{
        
        AVPacket   packet;
        AVRational time_base = self.formatContext->streams[self.videoStreamIndex]->time_base;
        
        while (!self.isCanceled) {
            av_init_packet(&packet);
            if (!self.formatContext)
            {
                break;
            }
            
            CFAbsoluteTime begin = CFAbsoluteTimeGetCurrent();
            int size = av_read_frame(self.formatContext, &packet);
            CFAbsoluteTime end = CFAbsoluteTimeGetCurrent();
            NSLogDebug(@"🦁🤖 av_read_frame cost: %.3lf ms", (end - begin) * 1000);
            if (size < 0 || packet.size < 0)
            {
                BLParseVideoDataInfo *dataPtr = nil;
                handler(dataPtr, YES);
                NSLogInfo(@"Read finish");
                break;
            }
            
            if (packet.stream_index == self.videoStreamIndex) 
            {
                BLParseVideoDataInfo videoInfo = {0};
                
                // get the rotation angle of video
                AVDictionaryEntry *tag = NULL;
                tag = av_dict_get(self.formatContext->streams[self.videoStreamIndex]->metadata, "rotate", tag, 0);
                if (tag != NULL)
                {
                    int rotate = [[NSString stringWithFormat:@"%s",tag->value] intValue];
                    switch (rotate) {
                        case 90:
                            videoInfo.videoRotate = 90;
                            break;
                        case 180:
                            videoInfo.videoRotate = 180;
                            break;
                        case 270:
                            videoInfo.videoRotate = 270;
                            break;
                        default:
                            videoInfo.videoRotate = 0;
                            break;
                    }
                }
                
                if (videoInfo.videoRotate != 0)
                {
                    NSLogError(@"Not support the angle");
                    break;
                }
                
                int video_size = packet.size;
                uint8_t *video_data = (uint8_t *)malloc(video_size);
                memcpy(video_data, packet.data, video_size);
                
                static char filter_name[32];
                if (self.formatContext->streams[self.videoStreamIndex]->codecpar->codec_id == AV_CODEC_ID_H264)
                {
                    strncpy(filter_name, "h264_mp4toannexb", 32);
                    videoInfo.videoFormat = BLVideoEncodeFormatH264;
                }
                else if (self.formatContext->streams[self.videoStreamIndex]->codecpar->codec_id == AV_CODEC_ID_HEVC)
                {
                    strncpy(filter_name, "hevc_mp4toannexb", 32);
                    videoInfo.videoFormat = BLVideoEncodeFormatH265;
                }
                else
                {
                    break;
                }
                
                AVPacket new_packet = packet;
                if (self.bitFilterContext == NULL)
                {
                    self.bitFilterContext = av_bitstream_filter_init(filter_name);
                }
                av_bitstream_filter_filter(self.bitFilterContext, self.formatContext->streams[self.videoStreamIndex]->codec, NULL, &new_packet.data, &new_packet.size, packet.data, packet.size, 0);
                
                //NSLogInfo(@"extra data : %s , size : %d",__func__,formatContext->streams[videoStreamIndex]->codec->extradata,formatContext->streams[videoStreamIndex]->codec->extradata_size);
                
                CMSampleTimingInfo timingInfo;
                timingInfo.presentationTimeStamp = CMTimeMake(packet.pts, time_base.den);
                timingInfo.decodeTimeStamp       = CMTimeMake(packet.dts, time_base.den);

                videoInfo.data          = video_data;
                videoInfo.dataSize      = video_size;
                videoInfo.extraDataSize = self.formatContext->streams[self.videoStreamIndex]->codec->extradata_size;
                videoInfo.extraData     = (uint8_t *)malloc(videoInfo.extraDataSize);
                videoInfo.timingInfo    = timingInfo;
                videoInfo.pts           = packet.pts * av_q2d(self.formatContext->streams[self.videoStreamIndex]->time_base);
                videoInfo.fps           = fps;
                videoInfo.flags         = packet.flags;
                videoInfo.packet        = &packet;
                
                memcpy(videoInfo.extraData, self.formatContext->streams[self.videoStreamIndex]->codec->extradata, videoInfo.extraDataSize);
                av_free(new_packet.data);
                
                // send videoInfo
                if (handler) 
                {
                    handler(&videoInfo, NO);
                }
                
                free(videoInfo.extraData);
                free(videoInfo.data);
            }
            
            av_packet_unref(&packet);
        }
        
        [self freeAllResources];
    });
}


@end
