//
//  SYVideoEncoder.m
//  SYScreenRecorder
//
//  Created by 苏杨 on 2019/9/10.
//

#import "SYVideoEncoder.h"

#import <VideoToolbox/VideoToolbox.h>

@interface SYVideoEncoder ()

@property (nonatomic) SYVideoEncoderConfig *config;

@end

@implementation SYVideoEncoder {
    VTCompressionSessionRef _compressionSession;
}

- (instancetype)initWithConfig:(SYVideoEncoderConfig *)config {
    self = [super init];
    if (self) {
        _config = config;
        _currentBps = config.bps;
        [self resetCompressionSession];
    }
    return self;
}

- (void)dealloc {
    [self destoryCompressionSession];
}

- (void)resetCompressionSession {
    [self destoryCompressionSession];
    
    OSStatus status = VTCompressionSessionCreate(NULL,
                                                 _config.videoSize.width,
                                                 _config.videoSize.height,
                                                 kCMVideoCodecType_H264,
                                                 NULL,
                                                 NULL,
                                                 NULL,
                                                 VideoCompressonOutputCallback,
                                                 (__bridge void *)self,
                                                 &_compressionSession);
    if (status != noErr) {
        return;
    }
    
    
    VTSessionSetProperty(_compressionSession, kVTCompressionPropertyKey_MaxKeyFrameInterval, (__bridge CFTypeRef)@(_config.gop * _config.fps));
    VTSessionSetProperty(_compressionSession, kVTCompressionPropertyKey_MaxKeyFrameIntervalDuration, (__bridge CFTypeRef)@(_config.gop));
    VTSessionSetProperty(_compressionSession, kVTCompressionPropertyKey_ExpectedFrameRate, (__bridge CFTypeRef)@(_config.fps));
    VTSessionSetProperty(_compressionSession, kVTCompressionPropertyKey_AverageBitRate, (__bridge CFTypeRef)@(_currentBps));
    NSArray *limit = @[@(_currentBps * 1.5/8), @(1)];
    VTSessionSetProperty(_compressionSession, kVTCompressionPropertyKey_DataRateLimits, (__bridge CFArrayRef)limit);
    VTSessionSetProperty(_compressionSession, kVTCompressionPropertyKey_RealTime, kCFBooleanTrue);
    VTSessionSetProperty(_compressionSession, kVTCompressionPropertyKey_ProfileLevel, kVTProfileLevel_H264_Main_AutoLevel);
    VTSessionSetProperty(_compressionSession, kVTCompressionPropertyKey_AllowFrameReordering, kCFBooleanTrue);
    VTSessionSetProperty(_compressionSession, kVTCompressionPropertyKey_H264EntropyMode, kVTH264EntropyMode_CABAC);
    NSDictionary *transferProperties = @{(id)kVTPixelTransferPropertyKey_ScalingMode : (id)kVTScalingMode_Letterbox};
    VTSessionSetProperty(_compressionSession, kVTCompressionPropertyKey_PixelTransferProperties, (__bridge CFTypeRef)(transferProperties));

    VTCompressionSessionPrepareToEncodeFrames(_compressionSession);
}

- (void)destoryCompressionSession {
    if (_compressionSession) {
        VTCompressionSessionCompleteFrames(_compressionSession, kCMTimeInvalid);
        
        VTCompressionSessionInvalidate(_compressionSession);
        CFRelease(_compressionSession);
        _compressionSession = NULL;
    }
}

- (void)setCurrentBps:(NSUInteger)currentBps {
    if (_currentBps == currentBps) {
        return;
    }
    
    VTSessionSetProperty(_compressionSession, kVTCompressionPropertyKey_AverageBitRate, (__bridge CFTypeRef)@(currentBps));
    NSArray *limit = @[@(currentBps * 1.5/8), @(1)];
    VTSessionSetProperty(_compressionSession, kVTCompressionPropertyKey_DataRateLimits, (__bridge CFArrayRef)limit);
    _currentBps = currentBps;
}

- (void)encodeFrame:(CVPixelBufferRef)frame withPts:(CMTime)pts {
    VTEncodeInfoFlags flags;
    OSStatus status = VTCompressionSessionEncodeFrame(_compressionSession,
                                                      frame,
                                                      pts,
                                                      kCMTimeInvalid,
                                                      NULL,
                                                      (__bridge void *)(self),
                                                      &flags);
    if(status != noErr){
        [self resetCompressionSession];
    }
}

#pragma mark -- VideoCallBack
static void VideoCompressonOutputCallback(void *VTref,
                                          void *VTFrameRef,
                                          OSStatus status,
                                          VTEncodeInfoFlags infoFlags,
                                          CMSampleBufferRef sampleBuffer) {
    if (status != noErr || !sampleBuffer) {
        return;
    }
    
    CFArrayRef array = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, true);
    if (!array) {
        return;
    }
    
    CFDictionaryRef dic = (CFDictionaryRef)CFArrayGetValueAtIndex(array, 0);
    if (!dic)  {
        return;
    }
    
    SYVideoEncoder *videoEncoder = (__bridge SYVideoEncoder *)VTref;
    
    BOOL keyframe = !CFDictionaryContainsKey(dic, kCMSampleAttachmentKey_NotSync);
    if (keyframe) {
        CMFormatDescriptionRef format = CMSampleBufferGetFormatDescription(sampleBuffer);
        
        size_t spsSize, spsCount, ppsSize, ppsCount;;
        const uint8_t *sps, *pps;
        OSStatus spsStatusCode = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(format,
                                                                                    0,
                                                                                    &sps,
                                                                                    &spsSize,
                                                                                    &spsCount,
                                                                                    0);
        OSStatus ppsStatusCode = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(format,
                                                                                    1,
                                                                                    &pps,
                                                                                    &ppsSize,
                                                                                    &ppsCount,
                                                                                    0);
        if (spsStatusCode == noErr && ppsStatusCode == noErr) {
            NSData *spsData = [NSData dataWithBytes:sps length:spsSize];
            NSData *ppsData = [NSData dataWithBytes:pps length:ppsSize];
            
            [videoEncoder.delegate videoEncoder:videoEncoder didOutputSps:spsData andPps:ppsData];
        }
    }
    
    CMBlockBufferRef dataBuffer = CMSampleBufferGetDataBuffer(sampleBuffer);
    size_t length, totalLength;
    char *dataPointer;
    OSStatus statusCodeRet = CMBlockBufferGetDataPointer(dataBuffer, 0, &length, &totalLength, &dataPointer);
    if (statusCodeRet != noErr) {
        return;
    }
    
    [videoEncoder.delegate videoEncoder:videoEncoder
                  didOutputEncodedFrame:[NSData dataWithBytes:dataPointer length:totalLength]
                                    pts:CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                               keyFrame:keyframe];
}

@end

@implementation SYVideoEncoderConfig

@end
