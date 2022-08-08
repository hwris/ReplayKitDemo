//
//  SYScreenRecorderServer.h
//  SYScreenRecorder
//
//  Created by 苏杨 on 2019/9/9.
//

#import "SYMessage.h"

#import <CoreMedia/CoreMedia.h>
#import <AVFoundation/AVFoundation.h>

@protocol SYScreenRecorderServerDelegate;
@protocol SYDataLink;

NS_ASSUME_NONNULL_BEGIN

@interface SYScreenRecorderServer : NSObject

@property (nonatomic, weak) id<SYScreenRecorderServerDelegate> delegate;
@property (nonatomic, assign) BOOL enableMicAudioCapture;   //是否开启mic采集，默认是YES
@property (readonly) float outputVolume;

- (instancetype)initWithDataLink:(id<SYDataLink>)dataLink;

- (void)startAudioCaptureRunning;
- (void)stopAudioCaptureRunning;

- (void)stopScreenCapture;

- (void)setLogo:(nullable UIImage *)image origin:(CGPoint)origin;

+ (instancetype)startByUDPDataLink;

@end

@protocol SYScreenRecorderServerDelegate <NSObject>

- (void)screenRecorderServer:(SYScreenRecorderServer *)server
         didOutputVideoFrame:(CVPixelBufferRef)videoFrame
                         pts:(CMTime)pts;
- (void)screenRecorderServer:(SYScreenRecorderServer *)server
           didOutputMicAudio:(CMSampleBufferRef)micAudio;
- (void)screenRecorderServer:(SYScreenRecorderServer *)server
           didOutputAppAudio:(CMSampleBufferRef)appAudio;
- (void)screenRecorderServer:(SYScreenRecorderServer *)server
    audioSessionInterruption:(AVAudioSessionInterruptionType)interruptionType;
- (void)screenRecorderServer:(SYScreenRecorderServer *)server
clientDidDisconnectWithError:(nullable NSError *)error;

@end

NS_ASSUME_NONNULL_END
