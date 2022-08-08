
#import <Foundation/Foundation.h>
#import <CoreMedia/CoreMedia.h>

#import "SYMessage.h"

NS_ASSUME_NONNULL_BEGIN

@protocol SYVideoDecoderDelegate;
@class SYVideoDecoderConfig;

@interface SYVideoDecoder : NSObject

@property (nonatomic, weak, nullable) id<SYVideoDecoderDelegate> delegate;

@property (nonatomic, strong, readonly) SYVideoDecoderConfig *config;

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithConfig:(SYVideoDecoderConfig *)config;

- (void)decodeFrame:(NSData *)frame withType:(SYMessageType)type;

@end

@protocol SYVideoDecoderDelegate <NSObject>

- (void)videoDecoder:(SYVideoDecoder *)videoDecoder didOutputPixelBuffer:(CVPixelBufferRef)pixelBuffer presentationTimeStamp:(CMTime)presentationTimeStamp;
- (void)videoDecoder:(SYVideoDecoder *)videoDecoder decodeError:(NSError *)error;

@end

@interface SYVideoDecoderConfig : NSObject

@property (nonatomic, assign) uint32_t pixelBufferPixelFormat;

@end

NS_ASSUME_NONNULL_END

