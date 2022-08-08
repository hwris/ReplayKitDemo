//
//  SYAVRecorder.h
//  SYAVRecorder
//
//  Created by 苏杨 on 2016/11/19.
//  Copyright © 2016年 suyang. All rights reserved.
//
#import <Foundation/Foundation.h>
#import <CoreMedia/CoreMedia.h>

@class SYAVWriterConfig;

NS_ASSUME_NONNULL_BEGIN

@interface SYAVWriter : NSObject

@property (nonatomic, readonly) SYAVWriterConfig *config;

- (instancetype)init UNAVAILABLE_ATTRIBUTE;
- (instancetype)new UNAVAILABLE_ATTRIBUTE;
- (instancetype)initWithConfig:(SYAVWriterConfig *)config;

- (void)startWriting;
- (void)stopWriting;

- (void)writeVideoBuffer:(CVPixelBufferRef)buffer presentationTimeStamp:(CMTime)presentationTimeStamp;
- (void)writeAudioBuffer:(CMSampleBufferRef)sampleBuffer;

@end

@interface SYAVWriterConfig : NSObject

@property (nonatomic, copy) NSURL *ouputPath;
@property (nonatomic) double videoBitRate;
@property (nonatomic) NSTimeInterval maxKeyFrameInterval;
@property (nonatomic) uint32_t pixelBufferPixelFormat;
@property (nonatomic) NSUInteger fps;

@end

NS_ASSUME_NONNULL_END
