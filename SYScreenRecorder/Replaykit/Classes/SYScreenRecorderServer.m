//
//  SYScreenRecorderServer.m
//  SYScreenRecorder
//
//  Created by 苏杨 on 2019/9/9.
//

#import "SYScreenRecorderServer.h"
#import "SYAudioCapture.h"
#import "SYDataLink.h"
#import "SYMessage.h"
#import "SYVideoDecoder.h"

@interface SYScreenRecorderServer ()

@property (nonatomic) SYAudioCapture *audioCapture;
@property (nonatomic) float outputVolume;

@property (nonatomic, assign) BOOL hadAddNotificationTag;

@end

@interface SYScreenRecorderServer (SYAudioCaptureDelegate) <SYAudioCaptureDelegate>

@end

@interface SYScreenRecorderServer (SYDataLinkDelegate) <SYDataLinkDelegate>

@end

@interface SYScreenRecorderServer (SYVideoEncoderDelegate) <SYVideoDecoderDelegate>

@end

@implementation SYScreenRecorderServer {
    id<SYDataLink> _dataLink;
    SYVideoDecoder *_videoDecoder;
}

+ (instancetype)startByUDPDataLink{
    NSError *error = nil;
    id<SYDataLink> dataLink = [SYTCPDataLink serverWithError:&error];
    return [[self alloc] initWithDataLink:dataLink];
}

- (instancetype)initWithDataLink:(id<SYDataLink>)dataLink {
    self = [super init];
    if (self) {
        _dataLink = dataLink;
        _dataLink.delegate = self;
        _enableMicAudioCapture = YES;
        
        SYVideoDecoderConfig *config = [SYVideoDecoderConfig new];
        config.pixelBufferPixelFormat = kCVPixelFormatType_420YpCbCr8PlanarFullRange;
        _videoDecoder = [[SYVideoDecoder alloc] initWithConfig:config];
        _videoDecoder.delegate = self;
    }
    return self;
}

- (void)dealloc {
    [_audioCapture removeObserver:self forKeyPath:@"outputVolume" context:NULL];
}

- (void)startAudioCaptureRunning {
    if (!self.enableMicAudioCapture) {
        [self configAudioSession];
        [self addNotification];
        return;
    }
    [self.audioCapture startRunning];
}

- (void)stopAudioCaptureRunning {
    if (!self.enableMicAudioCapture) {
        [self removeNotificationIfNeeded];
        return;
    }
    [self.audioCapture stopRunning];
}

- (void)stopScreenCapture {
    _dataLink = nil;
}

- (void)setLogo:(UIImage *)image origin:(CGPoint)origin {
    CGImageRef cgImage = image.CGImage;
    CGColorSpaceModel colorSpaceModel = CGColorSpaceGetModel(CGImageGetColorSpace(cgImage));
    if (colorSpaceModel != kCGColorSpaceModelRGB) {
        return;
    }
    
    CGImageAlphaInfo alphaInfo = CGImageGetAlphaInfo(cgImage);
    if (alphaInfo != kCGImageAlphaPremultipliedLast && alphaInfo != kCGImageAlphaPremultipliedFirst) {
        return;
    }
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        UIImage *mewImage = image;
        CGImageRef cgImage = image.CGImage;
        size_t width = CGImageGetWidth(cgImage);
        size_t height = CGImageGetHeight(cgImage);
        
        size_t stride = CGImageGetBytesPerRow(cgImage);
        if (width * 4 != stride) {
            CGContextRef bitmapContext = CGBitmapContextCreate(nil,
                                                               width,
                                                               height,
                                                               CGImageGetBitsPerComponent(cgImage),
                                                               width * 4,
                                                               CGImageGetColorSpace(cgImage),
                                                               CGImageGetBitmapInfo(cgImage));
            
            if (bitmapContext) {
                CGContextDrawImage(bitmapContext, CGRectMake(0, 0, width, height), cgImage);
                mewImage = [UIImage imageWithCGImage:CGBitmapContextCreateImage(bitmapContext)];
                CGContextRelease(bitmapContext);
            }
        }
    });
}


#pragma mark -- Private Method

- (void)configAudioSession {
    NSError *error;
    AVAudioSession *audioSession = [AVAudioSession sharedInstance];

    AVAudioSessionCategoryOptions option = AVAudioSessionCategoryOptionMixWithOthers | AVAudioSessionCategoryOptionDefaultToSpeaker | AVAudioSessionCategoryOptionAllowBluetooth;
    if (@available(iOS 10.0, *)) {
        option |= AVAudioSessionCategoryOptionAllowBluetoothA2DP;
    }
    [audioSession setCategory:AVAudioSessionCategoryPlayAndRecord
                  withOptions:option
                        error:&error];
//    [audioSession setMode:AVAudioSessionModeDefault error:&error];
}

- (void)addNotification {
    [self removeNotificationIfNeeded];
    self.hadAddNotificationTag = YES;
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleAudioSessionInterruption:)
                                                 name:AVAudioSessionInterruptionNotification
                                               object:nil];
}

- (void)removeNotificationIfNeeded {
    if (self.hadAddNotificationTag) {
        [[NSNotificationCenter defaultCenter] removeObserver:self name:AVAudioSessionInterruptionNotification object:nil];
    }
}

- (void)handleAudioSessionInterruption:(NSNotification *)notification {
    if ([notification.name isEqualToString:AVAudioSessionInterruptionNotification]) {
        if ([self.delegate respondsToSelector:@selector(screenRecorderServer:audioSessionInterruption:)]) {
            NSDictionary *userInfo = notification.userInfo;
            AVAudioSessionInterruptionType reason = [userInfo[AVAudioSessionInterruptionTypeKey] integerValue];
            [self.delegate screenRecorderServer:self audioSessionInterruption:reason];
        }
    }
}

- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary<NSKeyValueChangeKey,id> *)change
                       context:(void *)context {
    if (object == _audioCapture && [keyPath isEqualToString:@"outputVolume"]) {
        self.outputVolume = _audioCapture.outputVolume;
    }
}

#pragma mark -- Getter Method

- (SYAudioCapture *)audioCapture {
    if (!_audioCapture) {
        SYAudioCaptureConfig *audioCaptureConfig = [[SYAudioCaptureConfig alloc] init];
        _audioCapture = [[SYAudioCapture alloc] initWithConfig:audioCaptureConfig];
        _audioCapture.delegate = self;
        [_audioCapture addObserver:self forKeyPath:@"outputVolume" options:NSKeyValueObservingOptionInitial context:NULL];
    }
    return _audioCapture;
}

@end

@implementation SYScreenRecorderServer (SYAudioCaptureDelegate)

- (void)audioCapture:(SYAudioCapture *)audioCapture didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer {
    [self.delegate screenRecorderServer:self
                               didOutputMicAudio:sampleBuffer];
}

- (void)audioCapture:(SYAudioCapture *)audioCapture audioSessionInterruption:(AVAudioSessionInterruptionType)interruptionType {
    [self.delegate screenRecorderServer:self audioSessionInterruption:interruptionType];
}

- (void)audioCapture:(SYAudioCapture *)audioCapture audioRouteDidChanged:(BOOL)isChangeToSpeaker {
}

@end

@implementation SYScreenRecorderServer (SYDataLinkDelegate)

- (void)dataLink:(id<SYDataLink>)dataLink
  didReceiveData:data
     withMessage:(SYMessage)msg {
    switch (msg.tag) {
        case SYMessageTypeVideoMetaData:
            [self didReceiveVideoMetaData:data];
            break;
        case SYMessageTypeVideoFrame:
            [self didReceiveVideoFrameData:data];
            break;
        case SYMessageTypeAudoeFrame:
            [self didReceiveAppAudioData:data];
        default:
            break;
    }
}

- (void)dataLink:(nonnull id<SYDataLink>)dataLink didDisconnectWithError:(nullable NSError *)err {
    [_delegate screenRecorderServer:self clientDidDisconnectWithError:err];
}

- (void)didReceiveVideoMetaData:(NSData *)data {
    [_videoDecoder decodeFrame:data withType:SYMessageTypeVideoMetaData];
}

- (void)didReceiveVideoFrameData:(NSData *)data {
    [_videoDecoder decodeFrame:data withType:SYMessageTypeVideoFrame];
}

- (void)didReceiveAppAudioData:(NSData *)data {
    
}

@end

@implementation SYScreenRecorderServer (SYVideoEncoderDelegate)

- (void)videoDecoder:(SYVideoDecoder *)videoDecoder
didOutputPixelBuffer:(CVPixelBufferRef)pixelBuffer
presentationTimeStamp:(CMTime)presentationTimeStamp {
    [self.delegate screenRecorderServer:self didOutputVideoFrame:pixelBuffer pts:presentationTimeStamp];
}

- (void)videoDecoder:(SYVideoDecoder *)videoDecoder decodeError:(NSError *)error {
    
}

@end


