//
//  SYVideoEncoder.h
//  SYScreenRecorder
//
//  Created by 苏杨 on 2019/9/10.
//

#import <CoreMedia/CoreMedia.h>

@class SYVideoEncoderConfig;
@protocol SYVideoEncoderDelegate;

NS_ASSUME_NONNULL_BEGIN

@interface SYVideoEncoder : NSObject


@property (nonatomic) NSUInteger currentBps;
@property (nonatomic, weak) id<SYVideoEncoderDelegate> delegate;

@property (nonatomic, readonly) SYVideoEncoderConfig *config;

- (instancetype)initWithConfig:(SYVideoEncoderConfig *)config;

- (void)encodeFrame:(CVPixelBufferRef)frame withPts:(CMTime)pts;

@end

@interface SYVideoEncoderConfig : NSObject

@property (nonatomic) CGSize videoSize;
@property (nonatomic) NSUInteger fps;
@property (nonatomic) NSTimeInterval gop;
@property (nonatomic) NSUInteger bps;

@end

@protocol SYVideoEncoderDelegate <NSObject>

- (void)videoEncoder:(SYVideoEncoder *)videoEncoder didOutputSps:(NSData *)sps andPps:(NSData *)pps;
- (void)videoEncoder:(SYVideoEncoder *)videoEncoder
didOutputEncodedFrame:(NSData *)frame
                 pts:(CMTime)pts
            keyFrame:(BOOL)isKeyFrame;

@end

NS_ASSUME_NONNULL_END
