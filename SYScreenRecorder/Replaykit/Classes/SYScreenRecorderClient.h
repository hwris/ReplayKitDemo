//
//  SYScreenRecorderClient.h
//  SYScreenRecorder
//
//  Created by 苏杨 on 2019/9/7.
//

#import <CoreMedia/CoreMedia.h>

@protocol SYScreenRecorderClientDelegate;
@protocol SYDataLink;

NS_ASSUME_NONNULL_BEGIN

@interface SYScreenRecorderClient : NSObject

@property (nonatomic, weak) id<SYScreenRecorderClientDelegate> delegate;

- (instancetype)initWithDataLink:(id<SYDataLink>)dataLink;

- (void)pushVideo:(CMSampleBufferRef)video;
- (void)pushAppAudio:(CMSampleBufferRef)appAudio;

+ (instancetype)startByUDPDataLink;

@end

@protocol SYScreenRecorderClientDelegate <NSObject>

- (void)screenRecorderClient:(SYScreenRecorderClient *)client
serverDidDisconnectWithError:(nullable NSError *)error;

@end

NS_ASSUME_NONNULL_END
