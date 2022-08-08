//
//  SampleHandler.m
//  ReplayKitUpload
//
//  Created by 苏杨 on 2022/7/3.
//


#import "SampleHandler.h"

@import SYScreenRecorder;

@interface SampleHandler (SYScreenRecorderClientDelegate) <SYScreenRecorderClientDelegate>

@end

@implementation SampleHandler {
    SYScreenRecorderClient *_screenRecorder;
}

- (void)broadcastStartedWithSetupInfo:(NSDictionary<NSString *,NSObject *> *)setupInfo {
    // User has requested to start the broadcast. Setup info from the UI extension can be supplied but optional.
    _screenRecorder = [SYScreenRecorderClient startByUDPDataLink];
    _screenRecorder.delegate = self;
}

- (void)broadcastPaused {
    // User has requested to pause the broadcast. Samples will stop being delivered.
}

- (void)broadcastResumed {
    // User has requested to resume the broadcast. Samples delivery will resume.
}

- (void)broadcastFinished {
    // User has requested to finish the broadcast.
}

- (void)processSampleBuffer:(CMSampleBufferRef)sampleBuffer withType:(RPSampleBufferType)sampleBufferType {
    switch (sampleBufferType) {
        case RPSampleBufferTypeVideo:
            // Handle video sample buffer
            [_screenRecorder pushVideo:sampleBuffer];
            break;
        case RPSampleBufferTypeAudioApp:
            // Handle audio sample buffer for app audio
            [_screenRecorder pushAppAudio:sampleBuffer];
            break;
        case RPSampleBufferTypeAudioMic:
            // Handle audio sample buffer for mic audio
            break;
            
        default:
            break;
    }
}

@end

@implementation SampleHandler (SYScreenRecorderClientDelegate)

- (void)screenRecorderClient:(nonnull SYScreenRecorderClient *)client serverDidDisconnectWithError:(nullable NSError *)error {
    NSLog(@"finishBroadcastWithError %@", error);
    [self finishBroadcastWithError:error];
}

@end
