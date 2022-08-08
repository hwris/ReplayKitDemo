//
//  SYScreenRecorderClient.m
//  SYScreenRecorder
//
//  Created by 苏杨 on 2019/9/7.
//

#import "SYScreenRecorderClient.h"
#import "SYVideoEncoder.h"
#import "SYMessage.h"
#import "SYDataLink.h"

#import <ReplayKit/ReplayKit.h>

@interface UIImage (SYToYUV)

- (CVPixelBufferRef)sy_pixelBufferRGB;

@end

@interface SYScreenRecorderClient ()

@property (nonatomic) SYVideoEncoder *videoEncoder;

@property (nonatomic) CMSampleBufferRef lastVideoFrame;
@property (nonatomic) CGSize videoCaptureSize;

@end

@interface SYScreenRecorderClient (SYVideoEncoderDelegate) <SYVideoEncoderDelegate>

@end

@interface SYScreenRecorderClient (SYDataLinkDelegate) <SYDataLinkDelegate>

@end

@implementation SYScreenRecorderClient {
    id<SYDataLink> _dataLink;
}

+ (instancetype)startByUDPDataLink {
    NSError *error = nil;
    id<SYDataLink> dataLink = [SYTCPDataLink clientWithError:&error];
    return [[self alloc] initWithDataLink:dataLink];
}

- (instancetype)initWithDataLink:(id<SYDataLink>)dataLink {
    if ((self = [super init])) {
        _dataLink = dataLink;
        _dataLink.delegate = self;
    }
    return self;
}

- (void)dealloc {
    if (_lastVideoFrame) {
        CFRelease(_lastVideoFrame);
    }
}

- (SYVideoEncoder *)videoEncoderWithVideoFrame:(CVPixelBufferRef)frame {
    size_t frameWidth = CVPixelBufferGetWidth(frame);
    size_t frameHeight = CVPixelBufferGetHeight(frame);
    
    SYVideoEncoderConfig *config = [SYVideoEncoderConfig new];
    config.videoSize = CGSizeMake(frameWidth, frameHeight);
    config.gop = 1;
    config.fps = 30;
    config.bps = 5000 * 1000;

    SYVideoEncoder *encoder = [[SYVideoEncoder alloc] initWithConfig:config];
    encoder.delegate = self;
    return encoder;
}

- (void)pushVideo:(CMSampleBufferRef)sampleBuffer {
    // 系统回调后存在继续往`sampleBuffer`写数据的情况（系统bug），这里延迟一帧来保证数据尽可能写入完成（暂未找到其他更合适的解决办法）。
    if (self.lastVideoFrame) {
        [self _pushVideo:self.lastVideoFrame];
        CFRelease(self.lastVideoFrame);
    }
    self.lastVideoFrame = (CMSampleBufferRef)CFRetain(sampleBuffer);
}

- (void)_pushVideo:(CMSampleBufferRef)video {
    CVPixelBufferRef frame = CMSampleBufferGetImageBuffer(video);
    CMTime pts = CMSampleBufferGetPresentationTimeStamp(video);
    size_t frameWidth = CVPixelBufferGetWidth(frame);
    size_t frameHeight = CVPixelBufferGetHeight(frame);
    
    if (!self.videoEncoder) {
        self.videoEncoder = [self videoEncoderWithVideoFrame:frame];
    }
    
    self.videoCaptureSize = CGSizeMake(frameWidth, frameHeight);

    int32_t rotation = 0;
    if (@available(iOS 11.0, *)) {
        CGImagePropertyOrientation oritation = ((__bridge NSNumber*)CMGetAttachment(video, (__bridge CFStringRef)RPVideoSampleOrientationKey , NULL)).unsignedIntValue;
        switch (oritation) {
            case kCGImagePropertyOrientationUp:
                rotation = 0;
                break;
            case kCGImagePropertyOrientationDown:
                rotation = 180;
                break;
            case kCGImagePropertyOrientationRight:
                rotation = 270;
                break;
            case kCGImagePropertyOrientationLeft:
                rotation = 90;
                break;
            default:
                break;
        }
    }

    NSLog(@"[SYPTS] capture pts: %f", CMTimeGetSeconds(pts));
    [self.videoEncoder encodeFrame:frame withPts:pts];
}

- (void)pushAppAudio:(CMSampleBufferRef)appAudio {
    CMFormatDescriptionRef formatDesc = CMSampleBufferGetFormatDescription(appAudio);
    const AudioStreamBasicDescription *asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc);
    
    CMBlockBufferRef dataBuffer = CMSampleBufferGetDataBuffer(appAudio);
    size_t totalDataLength = CMBlockBufferGetDataLength(dataBuffer);
    if (totalDataLength <= 0) {
        return;
    }
    
    NSMutableData *data = [NSMutableData dataWithCapacity:sizeof(SYAppAudioFrameMessage) + totalDataLength];
    SYAppAudioFrameMessage msg = {
        .pts = CMSampleBufferGetPresentationTimeStamp(appAudio),
        .asbd = *asbd,
        .frameLength = (uint32_t)totalDataLength
    };
    
    [data appendBytes:&msg length:sizeof(SYAppAudioFrameMessage)];
    NSUInteger curLength = data.length;
    [data increaseLengthBy:totalDataLength];
    char *dataPointer = NULL;
    CMBlockBufferAccessDataBytes(dataBuffer, 0, totalDataLength, data.mutableBytes + curLength, &dataPointer);
    
    [_dataLink sendData:data withType:SYMessageTypeAudoeFrame];
}

- (void)setVideoCaptureSize:(CGSize)videoCaptureSize {
    if (fabs(videoCaptureSize.width - _videoCaptureSize.width) > 1.00 ||
        fabs(videoCaptureSize.height - _videoCaptureSize.height) > 1.0) {
        _videoCaptureSize = videoCaptureSize;
    }
}

@end

@implementation SYScreenRecorderClient (SYVideoEncoderDelegate)

- (void)videoEncoder:(SYVideoEncoder *)videoEncoder
        didOutputSps:(NSData *)sps
              andPps:(NSData *)pps {
    NSMutableData *data = [NSMutableData dataWithCapacity:sizeof(SYVideoMetaDataMessage) + sps.length + pps.length];
    SYVideoMetaDataMessage msg = {
        .spsLength = (uint32_t)sps.length,
        .ppsLength = (uint32_t)pps.length
    };
    [data appendBytes:&msg length:sizeof(SYVideoMetaDataMessage)];
    [data appendData:sps];
    [data appendData:pps];
    
    [_dataLink sendData:data withType:SYMessageTypeVideoMetaData];
}

- (void)videoEncoder:(SYVideoEncoder *)videoEncoder
didOutputEncodedFrame:(NSData *)frame
                 pts:(CMTime)pts
            keyFrame:(BOOL)isKeyFrame {
    NSLog(@"[SYPTS] after encode: %f", CMTimeGetSeconds(pts));
    NSMutableData *data = [NSMutableData dataWithCapacity:sizeof(SYVideoFrameMessage) + frame.length];
    SYVideoFrameMessage msg = {
        .pts = pts,
        .isKeyFrame = isKeyFrame,
        .frameLength = (uint32_t)frame.length
    };
    [data appendBytes:&msg length:sizeof(SYVideoFrameMessage)];
    [data appendData:frame];
    
    [_dataLink sendData:data withType:SYMessageTypeVideoFrame];
}

@end

@implementation SYScreenRecorderClient (SYDataLinkDelegate)

- (void)dataLink:(id<SYDataLink>)dataLink
  didReceiveData:(NSData *)data
     withMessage:(SYMessage)msg {
    
}


- (void)dataLink:(nonnull id<SYDataLink>)dataLink didDisconnectWithError:(nullable NSError *)err {
    [_delegate screenRecorderClient:self serverDidDisconnectWithError:err];
}

@end
