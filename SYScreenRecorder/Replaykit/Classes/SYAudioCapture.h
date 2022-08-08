//
//  SYAudioCapture.h
//  Pods
//
//  Created by 苏杨 on 2017/3/15.
//
//

#import <Foundation/Foundation.h>

#import <CoreMedia/CoreMedia.h>
#import <AVFoundation/AVFoundation.h>

@protocol SYAudioCaptureDelegate;
@class SYAudioCaptureConfig;

NS_ASSUME_NONNULL_BEGIN

@interface SYAudioCapture : NSObject

@property (readonly) float outputVolume;

@property (nonatomic, weak, nullable) id<SYAudioCaptureDelegate> delegate;

@property(nonatomic, strong, readonly) SYAudioCaptureConfig *config;

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithConfig:(SYAudioCaptureConfig *)config;

/// @see `[AVCaptureSession startRunning]`
- (void)startRunning;
/// @see `[AVCaptureSession stopRunning]`
- (void)stopRunning;

@end

@protocol SYAudioCaptureDelegate <NSObject>

@optional
- (void)audioCapture:(SYAudioCapture *)audioCapture didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer;
- (void)audioCapture:(SYAudioCapture *)audioCapture audioSessionInterruption:(AVAudioSessionInterruptionType)interruptionType;
- (void)audioCapture:(SYAudioCapture *)audioCapture audioRouteDidChanged:(BOOL)isChangeToSpeaker;

@end

@interface SYAudioCaptureConfig : NSObject

/// 录音时是否使用VoiceChat Mode, 默认 `NO`
@property(nonatomic, assign) BOOL isUseVoiceChatMode;

@end

NS_ASSUME_NONNULL_END
