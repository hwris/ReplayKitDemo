
#import "SYVideoDecoder.h"

#import <VideoToolbox/VideoToolbox.h>

//#define SYH264DecoderLocalRecord

@interface SYVideoDecoder ()

@property (nonatomic, strong) dispatch_semaphore_t semaphore;
@property (nonatomic, strong) NSData *currentSPS;
@property (nonatomic, strong) NSData *currentPPS;
@property (nonatomic, assign, getter=isHasReadKeyFrame) BOOL hasReadKeyFrame;

@property (nonatomic, assign) NSTimeInterval lastFrameCaptureTime;
@property (nonatomic, assign) NSTimeInterval lastFrameCaptureTimeSetTime;
@property (nonatomic, assign) NSTimeInterval frameCaptureTimeOffset;

#ifdef SYH264DecoderLocalRecord
@property (nonatomic, strong) SYH264Writter *h264Writter;
#endif

@end

@implementation SYVideoDecoder {
    VTDecompressionSessionRef _deocderSession;
    CMVideoFormatDescriptionRef _decoderFormatDescription;
}

- (instancetype)initWithConfig:(SYVideoDecoderConfig *)config {
    if ((self = [super init])) {
        _semaphore = dispatch_semaphore_create(1);
        _config = config;
        
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(didEnterBackground:)
                                                     name:UIApplicationDidEnterBackgroundNotification
                                                   object:nil];
    }
    return self;
}

- (void)dealloc {
    [self decoderInvalidate];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)decoderInvalidate {
    dispatch_semaphore_wait(_semaphore, DISPATCH_TIME_FOREVER);
    if (_decoderFormatDescription) {
        CFRelease(_decoderFormatDescription);
        _decoderFormatDescription = NULL;
    }
    
    if(_deocderSession) {
        VTDecompressionSessionInvalidate(_deocderSession);
        CFRelease(_deocderSession);
        _deocderSession = NULL;
    }
    dispatch_semaphore_signal(_semaphore);
}

#ifdef SYH264DecoderLocalRecord
- (SYH264Writter *)h264Writter {
    if (!_h264Writter) {
        _h264Writter = [[SYH264Writter alloc] init];
    }
    return _h264Writter;
}
#endif

- (void)didEnterBackground:(NSNotification *)notification {
    dispatch_semaphore_wait(self.semaphore, DISPATCH_TIME_FOREVER);
    [self resetDecoder];
    dispatch_semaphore_signal(self.semaphore);
}

- (void)resetDescription {
    if (_decoderFormatDescription) {
        CFRelease(_decoderFormatDescription);
        _decoderFormatDescription = NULL;
    }
    
    const uint8_t* const parameterSetPointers[2] = { _currentSPS.bytes, _currentPPS.bytes };
    const size_t parameterSetSizes[2] = { _currentSPS.length, _currentPPS.length };
    
    OSStatus status = CMVideoFormatDescriptionCreateFromH264ParameterSets(kCFAllocatorDefault,
                                                                          2, //param count
                                                                          parameterSetPointers,
                                                                          parameterSetSizes,
                                                                          4, //nal start code size
                                                                          &_decoderFormatDescription);
    NSParameterAssert(status == noErr);
}

- (void)resetDecoder {
    if(_deocderSession) {
        VTDecompressionSessionInvalidate(_deocderSession);
        CFRelease(_deocderSession);
        _deocderSession = NULL;
    }
    
    if (!_decoderFormatDescription) {
        return;
    }
    
    NSDictionary *attrs = @{ (id)(kCVPixelBufferPixelFormatTypeKey) : @(self.config.pixelBufferPixelFormat) };
    
    VTDecompressionOutputCallbackRecord callBackRecord;
    callBackRecord.decompressionOutputCallback = didDecompress;
    callBackRecord.decompressionOutputRefCon = (__bridge void *)self;
    
    OSStatus r = VTDecompressionSessionCreate(kCFAllocatorDefault,
                                              _decoderFormatDescription,
                                              NULL,
                                              (__bridge CFDictionaryRef)(attrs),
                                              &callBackRecord,
                                              &_deocderSession);
    NSParameterAssert(r == noErr);
    
    self.hasReadKeyFrame = NO;
}

- (void)decodeError:(NSError *)error {
    if ([self.delegate respondsToSelector:@selector(videoDecoder:decodeError:)]) {
        [self.delegate videoDecoder:self decodeError:error];
    }
}

- (void)decodeFrame:(NSData *)frame withType:(SYMessageType)type  {
    dispatch_semaphore_wait(self.semaphore, DISPATCH_TIME_FOREVER);
    [self _decodeFrame:frame withType:type];
    dispatch_semaphore_signal(self.semaphore);
}

- (void)_decodeFrame:(NSData *)frame withType:(SYMessageType)type {
    if (type == SYMessageTypeVideoMetaData) {
        SYVideoMetaDataMessage msg = {};
        [frame getBytes:&msg range:NSMakeRange(0, sizeof(SYVideoMetaDataMessage))];
        NSData *sps = [frame subdataWithRange:NSMakeRange(sizeof(SYVideoMetaDataMessage), msg.spsLength)];
        NSData *pps = [frame subdataWithRange:NSMakeRange(sizeof(SYVideoMetaDataMessage) + sps.length, msg.ppsLength)];
        
        if (_currentSPS && [sps isEqualToData:_currentSPS] &&
            _currentPPS && [pps isEqualToData:_currentPPS]) {
            return;
        }
        
#ifdef SYH264DecoderLocalRecord
        [self.h264Writter writeMetaFrame:frame];
#endif
        _currentSPS = sps;
        _currentPPS = pps;
        [self resetDescription];
        [self resetDecoder];
        return;
    }
    
#ifdef SYH264DecoderLocalRecord
    [self.h264Writter writeFrame:frame];
#endif
    
    SYVideoFrameMessage msg = {};
    [frame getBytes:&msg range:NSMakeRange(0, sizeof(SYVideoFrameMessage))];
    NSData *frameData = [frame subdataWithRange:NSMakeRange(sizeof(SYVideoFrameMessage), msg.frameLength)];
    
    NSLog(@"[SYPTS] before decode: %f", CMTimeGetSeconds(msg.pts));
    
    if (!self.isHasReadKeyFrame) {
        if (!msg.isKeyFrame) {
            return;
        }
        self.hasReadKeyFrame = YES;
    }
    
    if (!_deocderSession) { return; }
    
    CMBlockBufferRef blockBuffer = NULL;
    OSStatus status  = CMBlockBufferCreateWithMemoryBlock(kCFAllocatorDefault,
                                                          frameData.bytes,
                                                          frameData.length,
                                                          kCFAllocatorNull,
                                                          NULL,
                                                          0,
                                                          frameData.length,
                                                          0,
                                                          &blockBuffer);
    
    if(status == kCMBlockBufferNoErr) {
        CMSampleBufferRef sampleBuffer = NULL;
        
        const size_t sampleSizeArray[] = {
            frameData.length
        };
        
        const CMSampleTimingInfo sampleTimingArray[] = {
            { .presentationTimeStamp = msg.pts }
        };
        
        status = CMSampleBufferCreateReady(kCFAllocatorDefault,
                                           blockBuffer,
                                           _decoderFormatDescription ,
                                           1,
                                           1,
                                           sampleTimingArray,
                                           1,
                                           sampleSizeArray,
                                           &sampleBuffer);
        
        if (status == kCMBlockBufferNoErr && sampleBuffer) {
            VTDecodeFrameFlags flags = 0;
            VTDecodeInfoFlags flagOut = 0;
            status = VTDecompressionSessionDecodeFrame(_deocderSession,
                                                       sampleBuffer,
                                                       flags,
                                                       NULL,
                                                       &flagOut);
            if (status != noErr) {
                [self decodeError:[NSError errorWithDomain:@"VTDecompressionSessionDecodeFrame" code:status userInfo:nil]];
                if (status != kVTVideoDecoderMalfunctionErr) {
                    [self resetDecoder];
                }
            }
            CFRelease(sampleBuffer);
        }
        CFRelease(blockBuffer);
    }
}

- (CMTime)presentationTimeStampForFrame:(NSTimeInterval)captureTime {
    if (self.lastFrameCaptureTimeSetTime > 0.0 && captureTime <= self.lastFrameCaptureTime) {
        self.frameCaptureTimeOffset += self.lastFrameCaptureTime + CACurrentMediaTime() - self.lastFrameCaptureTimeSetTime;
    }
    
    self.lastFrameCaptureTime = captureTime;
    NSTimeInterval presentationTimeStamp = captureTime + self.frameCaptureTimeOffset;
    
    int32_t timescale = 1000000;
    return CMTimeMake(presentationTimeStamp * timescale, timescale);
}

- (void)setLastFrameCaptureTime:(NSTimeInterval)lastFrameCaptureTime
{
    _lastFrameCaptureTime = lastFrameCaptureTime;
    self.lastFrameCaptureTimeSetTime = CACurrentMediaTime();
}


static void didDecompress(void *decompressionOutputRefCon,
                          void *sourceFrameRefCon,
                          OSStatus status,
                          VTDecodeInfoFlags infoFlags,
                          CVImageBufferRef pixelBuffer,
                          CMTime presentationTimeStamp,
                          CMTime presentationDuration ) {
    SYVideoDecoder *self = (__bridge SYVideoDecoder *)decompressionOutputRefCon;
    
    if(status != noErr) {
        [self decodeError:[NSError errorWithDomain:@"VTDecompressionSessionDecodeFrameCallback" code:status userInfo:nil]];
        return;
    }
    
    if (pixelBuffer == NULL) { return; }
    
    if ([self.delegate respondsToSelector:@selector(videoDecoder:didOutputPixelBuffer:presentationTimeStamp:)]) {
        [self.delegate videoDecoder:self
              didOutputPixelBuffer:pixelBuffer
             presentationTimeStamp:presentationTimeStamp];
    }
}

@end

@implementation SYVideoDecoderConfig

@end



