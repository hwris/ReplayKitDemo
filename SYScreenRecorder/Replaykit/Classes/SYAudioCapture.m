//
//  SYAudioCapture.m
//  Pods
//
//  Created by 苏杨 on 2017/3/15.
//
//

#import "SYAudioCapture.h"

@interface SYAudioCapture () <AVCaptureAudioDataOutputSampleBufferDelegate>

@property (nonatomic, strong) AVCaptureSession *audioCaptureSession;
@property (nonatomic) float outputVolume;

@end

@implementation SYAudioCapture

- (instancetype)initWithConfig:(SYAudioCaptureConfig *)config {
    self = [super init];
    if (self) {
        _config = config;
        
        dispatch_queue_t queue = dispatch_queue_create("SYAudioCapture", DISPATCH_QUEUE_SERIAL);
        _audioCaptureSession = [self createAudioCaptureSessionWithDelegate:self queue:queue];
    }
    return self;
}

- (AVCaptureSession *)createAudioCaptureSessionWithDelegate:(id<AVCaptureAudioDataOutputSampleBufferDelegate>)delegate
                                                      queue:(dispatch_queue_t)delegateQueue {
    NSError *error = nil;
    AVCaptureSession * audioCaptureSession = [[AVCaptureSession alloc] init];
    audioCaptureSession.automaticallyConfiguresApplicationAudioSession = NO;
    [audioCaptureSession setSessionPreset:AVCaptureSessionPresetMedium];
    AVCaptureDevice *audioDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeAudio];
    AVCaptureDeviceInput *audioDeviceInput = [AVCaptureDeviceInput deviceInputWithDevice:audioDevice error:&error];
    
    NSAssert(error == nil, @"Failed to alloc audioDeviceInput");
    
    if ([audioCaptureSession canAddInput:audioDeviceInput]){
        [audioCaptureSession addInput:audioDeviceInput];
    } else {
        NSAssert(NO, @"audioDeviceInput can't be added");
    }
    
    AVCaptureAudioDataOutput *audioDataOutput = [[AVCaptureAudioDataOutput alloc] init];
    if ([audioCaptureSession canAddOutput:audioDataOutput]) {
        [audioCaptureSession addOutput:audioDataOutput];
    } else {
        NSAssert(NO, @"audioDataOutput can't be added");
    }
    
    if (delegate && delegateQueue) {
        [audioDataOutput setSampleBufferDelegate:delegate queue:delegateQueue];
    }
    
    return audioCaptureSession;
}

- (void)startRunning {
    [self activeAudioSessionWithVoiceChatMode:self.config.isUseVoiceChatMode];
    [self.audioCaptureSession startRunning];
    [self handleAudioSessionRouteChange];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleAudioSessionRouteChange)
                                                 name:AVAudioSessionRouteChangeNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleAudioSessionInterruption:)
                                                 name:AVAudioSessionInterruptionNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleApplicationDidBecomeActive:)
                                                 name:UIApplicationDidBecomeActiveNotification
                                               object:nil];
    [AVAudioSession.sharedInstance addObserver:self forKeyPath:NSStringFromSelector(@selector(outputVolume)) options:NSKeyValueObservingOptionInitial context:nil];
}

- (void)stopRunning {
    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:AVAudioSessionRouteChangeNotification
                                                  object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:AVAudioSessionInterruptionNotification
                                                  object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:UIApplicationDidBecomeActiveNotification
                                                  object:nil];
    [AVAudioSession.sharedInstance removeObserver:self forKeyPath:NSStringFromSelector(@selector(outputVolume)) context:nil];
    
    [self.audioCaptureSession stopRunning];
    [self deactivationAudioSession];
}

- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary<NSKeyValueChangeKey,id> *)change
                       context:(void *)context {
    if (object == AVAudioSession.sharedInstance &&
        [keyPath isEqualToString:NSStringFromSelector(@selector(outputVolume))]) {
        self.outputVolume = AVAudioSession.sharedInstance.outputVolume;
    }
}

- (void)activeAudioSessionWithVoiceChatMode:(BOOL)isVoiceChatMode {
    NSError *error;
    AVAudioSession *audioSession = [AVAudioSession sharedInstance];
    
    AVAudioSessionCategoryOptions option = AVAudioSessionCategoryOptionMixWithOthers | AVAudioSessionCategoryOptionDefaultToSpeaker | AVAudioSessionCategoryOptionAllowBluetooth;
    if (@available(iOS 10.0, *)) {
        option |= AVAudioSessionCategoryOptionAllowBluetoothA2DP;
    }
    [audioSession setCategory:AVAudioSessionCategoryPlayAndRecord
                  withOptions:option
                        error:&error];
    [audioSession setMode:isVoiceChatMode ? AVAudioSessionModeVoiceChat : AVAudioSessionModeDefault error:&error];
    
    [audioSession setPreferredSampleRate:44100 error:&error];
    [audioSession setPreferredInputNumberOfChannels:1 error:&error];
    [audioSession setPreferredOutputNumberOfChannels:1 error:&error];
    
    [audioSession setActive:YES error:&error];
}

- (void)deactivationAudioSession{
    NSError *error;
    AVAudioSession *audioSession = [AVAudioSession sharedInstance];
    [audioSession setActive:NO
                withOptions:AVAudioSessionSetActiveOptionNotifyOthersOnDeactivation
                      error:&error];
}

- (void)handleAudioSessionRouteChange {
    AVAudioSessionRouteDescription *route = [[AVAudioSession sharedInstance] currentRoute];
    BOOL isSpeaker = NO;
    for (AVAudioSessionPortDescription* desc in route.outputs) {
        isSpeaker = isSpeaker || [desc.portType isEqualToString:AVAudioSessionPortBuiltInSpeaker];
    }
    [self.delegate audioCapture:self audioRouteDidChanged:isSpeaker];
}

- (void)handleAudioSessionInterruption:(NSNotification *)notification {
    if ([notification.name isEqualToString:AVAudioSessionInterruptionNotification]) {
        NSDictionary *userInfo = notification.userInfo;
        AVAudioSessionInterruptionType reason = [userInfo[AVAudioSessionInterruptionTypeKey] integerValue];
        if ([self.delegate respondsToSelector:@selector(audioCapture:audioSessionInterruption:)]) {
            [self.delegate audioCapture:self audioSessionInterruption:reason];
        }
    }
}

- (void)handleApplicationDidBecomeActive:(NSNotification *)notification {
    if (!self.audioCaptureSession.running) {
        [self stopRunning];
        [self startRunning];
    }
}

#pragma mark - AVCaptureAudioDataOutputSampleBufferDelegate

- (void)captureOutput:(AVCaptureOutput *)captureOutput didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection {
    int32_t timescale = 1000000;
    CMTime pts = CMTimeMake(CACurrentMediaTime() * timescale, timescale);
    
    CMSampleBufferRef newSampleBuffer = [self adjustTime:sampleBuffer by:pts];
    
    if ([self.delegate respondsToSelector:@selector(audioCapture:didOutputSampleBuffer:)]) {
        [self.delegate audioCapture:self didOutputSampleBuffer:newSampleBuffer];
    }
    
    CFRelease(newSampleBuffer);
}

- (CMSampleBufferRef)adjustTime:(CMSampleBufferRef)sampleBuffer by:(CMTime)time {
    CMItemCount count;
    CMSampleBufferGetSampleTimingInfoArray(sampleBuffer, 0, nil, &count);
    CMSampleTimingInfo *pInfo = malloc(sizeof(CMSampleTimingInfo) * count);
    CMSampleBufferGetSampleTimingInfoArray(sampleBuffer, count, pInfo, &count);
    for (CMItemCount i = 0; i < count; i++) {
        pInfo[i].presentationTimeStamp = time;
    }
    
    CMSampleBufferRef newSampleBuffer;
    CMSampleBufferCreateCopyWithNewTiming(nil, sampleBuffer, count, pInfo, &newSampleBuffer);
    
    free(pInfo);
    
    return newSampleBuffer;
}

@end

@implementation SYAudioCaptureConfig


@end
