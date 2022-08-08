//
//  SYDataLink.h
//  SYScreenRecorder
//
//  Created by 苏杨 on 2022/7/17.
//

#import <Foundation/Foundation.h>

#import "SYMessage.h"

@protocol SYDataLinkDelegate;

NS_ASSUME_NONNULL_BEGIN

@protocol SYDataLink <NSObject>

@property (nonatomic, weak) id<SYDataLinkDelegate> delegate;

- (void)sendData:(NSData *)data withType:(uint8_t)type;

@end

@protocol SYDataLinkDelegate <NSObject>

- (void)dataLink:(id<SYDataLink>)dataLink
  didReceiveData:(NSData *)data
     withMessage:(SYMessage)msg;

- (void)dataLink:(id<SYDataLink>)dataLink
didDisconnectWithError:(nullable NSError *)err;

@end

@interface SYTCPDataLink : NSObject <SYDataLink>

+ (nullable instancetype)clientWithError:(NSError **)error;

+ (nullable instancetype)serverWithError:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
