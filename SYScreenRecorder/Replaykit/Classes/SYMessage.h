//
//  SYMessage.h
//  SYScreenRecorder
//
//  Created by 苏杨 on 2022/7/17.
//

#ifndef SYMessage_h
#define SYMessage_h

#include <CoreGraphics/CoreGraphics.h>
#include <CoreMedia/CoreMedia.h>

typedef enum : uint8_t {
    SYMessageTypeVideoMetaData,
    SYMessageTypeVideoFrame,
    SYMessageTypeAudoeFrame,
    SYMessageTypePeerStop
} SYMessageType;

typedef struct {
    NSTimeInterval ts;
    uint8_t tag;
    uint32_t dataLength;
    // data
} SYMessage;

typedef struct {
    uint32_t spsLength;
    uint32_t ppsLength;
    // SPS Data
    // PPS Data
} SYVideoMetaDataMessage;

typedef struct {
    CMTime pts;
    BOOL isKeyFrame;
    uint32_t frameLength;
    // frame Data
} SYVideoFrameMessage;

typedef struct {
    CMTime pts;
    AudioStreamBasicDescription asbd;
    uint32_t frameLength;
    // frame Data
} SYAppAudioFrameMessage;

typedef struct {
    NSInteger errorCode;
    uint32_t errorDescLength;
    //error description.
} SYPeerStopMessage;

#endif /* SYMessage_h */
