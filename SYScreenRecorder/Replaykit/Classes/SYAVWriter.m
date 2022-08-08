//
//  SYAVRecorder.m
//  SYAVRecorder
//
//  Created by 苏杨 on 2016/11/19.
//  Copyright © 2016年 suyang. All rights reserved.
//

#import "SYAVWriter.h"

#import <AVFoundation/AVFoundation.h>
#import <MediaPlayer/MediaPlayer.h>

#define SYRecordModelInfoLog(fmt, ...) do{ NSLog((@"[RecordSession] " fmt), ##__VA_ARGS__); }while(0)

@interface SYAVWriter ()
@property (nonatomic, strong) SYAVWriterConfig   *config;
@property (nonatomic, strong) dispatch_queue_t  writerQueue;

@property (nonatomic, assign) CMTime baseTime;
@property (nonatomic, strong) AVAssetWriter *mediaWriter;
@property (nonatomic, strong) AVAssetWriterInput *videoWriterInput;
@property (nonatomic, strong) AVAssetWriterInput *audioWriterInput;
@property (nonatomic, strong) AVAssetWriterInputPixelBufferAdaptor *bufferAdaptor;
@end

@implementation SYAVWriter {
    // 用来避免输入时间戳乱序
    CMTime _preVideoPTS;
    CVPixelBufferRef _preVideoFrame;
    BOOL _isWriting;
}

- (instancetype)initWithConfig:(SYAVWriterConfig *)config {
    self = [super init];
    if (self) {
        _config = config;
//        if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad) {
//            _config.videoEncodeParams.videoSize = _config.isLandscape ? CGSizeMake(1280, 720) : CGSizeMake(720, 1280);
//        }
        _writerQueue = dispatch_queue_create("com.sy.videoWriterSerialQueue", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

- (void)startWritingWtihVideoSize:(CGSize)videoSize {
    [self setupMediaWriterWithVideoSize:videoSize];
    [self.mediaWriter startWriting];
    [self.mediaWriter startSessionAtSourceTime:kCMTimeZero];
}

- (void)startWriting {
    dispatch_async(_writerQueue, ^{
        self->_isWriting = YES;
    });
}

- (void)stopWriting {
    dispatch_async(_writerQueue, ^{
        self->_isWriting = NO;
        if (self -> _preVideoFrame) {
            self->_preVideoPTS = kCMTimeInvalid;
            CVPixelBufferRelease(self->_preVideoFrame);
        }
        
        void (^stopWritingNotification)(NSError *) = ^(NSError *error){
            SYRecordModelInfoLog("stop with error %@", error);
            [self destroyMediaWriter];
        };
        
        if (self.mediaWriter.status == AVAssetWriterStatusWriting) {
            [self.videoWriterInput markAsFinished];
            [self.audioWriterInput markAsFinished];
            
            [self.mediaWriter finishWritingWithCompletionHandler:^{
                dispatch_async(self.writerQueue, ^{
                    if (self.mediaWriter.status != AVAssetWriterStatusCompleted) {
                        [[NSFileManager defaultManager] removeItemAtPath:[self.mediaWriter outputURL].path error:NULL];
                    }
                    NSAssert(!self.mediaWriter.error, self.mediaWriter.error.description);
                    stopWritingNotification(self.mediaWriter.error);
                });
            }];
        } else {
            [[NSFileManager defaultManager] removeItemAtPath:[self.mediaWriter outputURL].path error:NULL];
            stopWritingNotification(self.mediaWriter.error);
        }
    });
}

- (void)writeVideoBuffer:(CVPixelBufferRef)buffer presentationTimeStamp:(CMTime)presentationTimeStamp {
    if (!buffer) {return;}

    CVPixelBufferRetain(buffer);
    dispatch_async(_writerQueue, ^{
        if (!self->_isWriting) {
            CVPixelBufferRelease(buffer);
            return;
        }
        
        if (self->_isWriting && !self.mediaWriter) {
            size_t frameWidth = CVPixelBufferGetWidth(buffer);
            size_t frameHeight = CVPixelBufferGetHeight(buffer);
            [self startWritingWtihVideoSize:CGSizeMake(frameWidth, frameHeight)];
        }
        
        while (self.mediaWriter.status == AVAssetWriterStatusWriting && !self.videoWriterInput.readyForMoreMediaData) {
           usleep(5000);
        }

        if (self.mediaWriter.status == AVAssetWriterStatusWriting && self.videoWriterInput.readyForMoreMediaData) {
            if (!self.baseTime.value) {
                self.baseTime = presentationTimeStamp;
            }
            
            if (!self -> _preVideoFrame) {
                self->_preVideoPTS = presentationTimeStamp;
                self->_preVideoFrame = buffer;
                return;
            }
            
            CMTime targetPTS = presentationTimeStamp;
            CVPixelBufferRef targetVideoFrame = buffer;
            if (CMTimeCompare(self->_preVideoPTS, presentationTimeStamp) == -1) {
                targetPTS = self->_preVideoPTS;
                targetVideoFrame = self -> _preVideoFrame;
                
                self -> _preVideoPTS = presentationTimeStamp;
                self -> _preVideoFrame = buffer;
            }
            
            CMTime pts = CMTimeSubtract(targetPTS, self.baseTime);
            NSLog(@"[SYPTS] Write: %f", CMTimeGetSeconds(targetPTS));
            [self.bufferAdaptor appendPixelBuffer:targetVideoFrame withPresentationTime:pts];
            
            CVPixelBufferRelease(targetVideoFrame);
        } else {
            CVPixelBufferRelease(buffer);
        }
    });
}

- (void)writeAudioBuffer:(CMSampleBufferRef)sampleBuffer {
    if (!sampleBuffer) { return; }

    CFRetain(sampleBuffer);
    dispatch_async(_writerQueue, ^{
        if (!self->_isWriting) {
            return;
        };
        
        while (self.mediaWriter.status == AVAssetWriterStatusWriting && !self.audioWriterInput.readyForMoreMediaData) {
            usleep(5000);
        }

        if (self.mediaWriter.status == AVAssetWriterStatusWriting && self.audioWriterInput.readyForMoreMediaData) {
            if (!self.baseTime.value) {
                self.baseTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer);
            }

            CMSampleBufferRef newSampleBuffer = [self adjustTime:sampleBuffer by:self.baseTime];
            if (newSampleBuffer) {
                [self.audioWriterInput appendSampleBuffer:newSampleBuffer];
                CFRelease(newSampleBuffer);
            }
        }

        CFRelease(sampleBuffer);
    });
}

- (CMSampleBufferRef)adjustTime:(CMSampleBufferRef)sampleBuffer by:(CMTime)offset {
    CMItemCount count;
    CMSampleBufferGetSampleTimingInfoArray(sampleBuffer, 0, nil, &count);
    CMSampleTimingInfo *pInfo = malloc(sizeof(CMSampleTimingInfo) * count);
    CMSampleBufferGetSampleTimingInfoArray(sampleBuffer, count, pInfo, &count);
    for (CMItemCount i = 0; i < count; i++) {
        pInfo[i].decodeTimeStamp = CMTimeSubtract(pInfo[i].decodeTimeStamp, offset);
        pInfo[i].presentationTimeStamp = CMTimeSubtract(pInfo[i].presentationTimeStamp, offset);
    }
    CMSampleBufferRef newSampleBuffer;
    CMSampleBufferCreateCopyWithNewTiming(nil, sampleBuffer, count, pInfo, &newSampleBuffer);
    free(pInfo);
    return newSampleBuffer;
}


#pragma mark - Writer

- (void)setupMediaWriterWithVideoSize:(CGSize)videoSize {
    _baseTime = kCMTimeZero;
    
    // media writer
    NSError *error;
    _mediaWriter = [AVAssetWriter assetWriterWithURL:self.config.ouputPath
                                            fileType:AVFileTypeMPEG4
                                               error:&error];
    
    NSAssert(!error, @"");
    _mediaWriter.shouldOptimizeForNetworkUse = YES;
    
    // add video writer
    NSNumber *videoAverageBitRate = @(self.config.videoBitRate);
    NSDictionary *videoWriteSetting = @{AVVideoCodecKey                : AVVideoCodecH264,
                                        AVVideoWidthKey                : @(videoSize.width),
                                        AVVideoHeightKey               : @(videoSize.height),
                                        AVVideoCompressionPropertiesKey: @{AVVideoAverageBitRateKey: videoAverageBitRate,
                                                                           AVVideoMaxKeyFrameIntervalDurationKey: @(self.config.maxKeyFrameInterval),
                                                                           AVVideoMaxKeyFrameIntervalKey : @(self.config.maxKeyFrameInterval * self.config.fps),
                                                                           AVVideoExpectedSourceFrameRateKey : @(self.config.fps),
                                                                           AVVideoProfileLevelKey : AVVideoProfileLevelH264High41}};
    _videoWriterInput = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeVideo outputSettings:videoWriteSetting];
    _videoWriterInput.expectsMediaDataInRealTime = YES;
//    if (_config.isLandscape) {
//        _videoWriterInput.transform = CGAffineTransformMakeRotation(-M_PI_2);
//    }
    
    if ([_mediaWriter canAddInput:_videoWriterInput]) {
        [_mediaWriter addInput:_videoWriterInput];
    }
    
    // add audio input
    AudioChannelLayout acl;
    bzero(&acl, sizeof(acl));
    acl.mChannelLayoutTag = kAudioChannelLayoutTag_Stereo;
    NSData *aclData = [NSData dataWithBytes:&acl length:sizeof(acl)];
    NSDictionary *audioOutputSettings = @{AVFormatIDKey         : @(kAudioFormatMPEG4AAC),
                                          AVNumberOfChannelsKey : @(2),
                                          AVSampleRateKey       : @(44100.0f),
                                          AVEncoderBitRateKey   : @(64000),
                                          AVChannelLayoutKey    : aclData};
    
    if (![_mediaWriter canApplyOutputSettings:audioOutputSettings forMediaType:AVMediaTypeAudio]) {
        NSAssert(NO, @"AVAssetWriter couldn't apply audioOutputSettings");
    }
    _audioWriterInput = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeAudio outputSettings:audioOutputSettings];
    _audioWriterInput.expectsMediaDataInRealTime = YES;
    if (![_mediaWriter canAddInput:_audioWriterInput]) {
        NSAssert(NO, @"AVAssetWriter couldn't add audio input");
    }
    
    [_mediaWriter addInput:_audioWriterInput];
    
    // bufferAdaptor
    NSDictionary *pixelBufferSetting = @{(id)kCVPixelBufferPixelFormatTypeKey:@(self.config.pixelBufferPixelFormat),
                                         (id)kCVPixelBufferWidthKey:@(videoSize.width),
                                         (id)kCVPixelBufferHeightKey:@(videoSize.height),
                                         (id)kCVPixelBufferBytesPerRowAlignmentKey:@(16),
                                         (id)kCVPixelBufferPlaneAlignmentKey:@(16)};
    _bufferAdaptor = [AVAssetWriterInputPixelBufferAdaptor assetWriterInputPixelBufferAdaptorWithAssetWriterInput:_videoWriterInput sourcePixelBufferAttributes:pixelBufferSetting];
}

- (void)destroyMediaWriter {
    _baseTime = kCMTimeZero;
    _audioWriterInput = nil;
    _videoWriterInput = nil;
    _bufferAdaptor = nil;
    _mediaWriter = nil;
}

@end

@implementation SYAVWriterConfig

@end
