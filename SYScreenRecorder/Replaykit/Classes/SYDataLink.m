//
//  SYDataLink.m
//  SYScreenRecorder
//
//  Created by 苏杨 on 2022/7/17.
//

#import "SYDataLink.h"

#import <CocoaAsyncSocket/GCDAsyncSocket.h>

static uint16_t const APP_PORT = 9119;
static NSTimeInterval const SEND_TIMEOUT = 1;
static NSTimeInterval const READ_TIMEOUT = 1;
static long const HEAD_TAG = 0;
static long const BODY_TAG = 1;

@interface SYTCPDataLink (GCDAsyncSocketDelegate) <GCDAsyncSocketDelegate>

@end

@implementation SYTCPDataLink {
    GCDAsyncSocket *_socket;
    GCDAsyncSocket *_acceptedSocket;
    dispatch_queue_t _queue;
}

@synthesize delegate = _delegate;

- (instancetype)init {
    if ((self = [super init])) {
        _queue = dispatch_queue_create("data_link_queue", DISPATCH_QUEUE_SERIAL);
        _socket = [[GCDAsyncSocket alloc] initWithDelegate:self delegateQueue:_queue];
    }
    return self;
}

-(void)dealloc {
    [_socket disconnectAfterReadingAndWriting];
    [_acceptedSocket disconnectAfterReadingAndWriting];
    _acceptedSocket = nil;
}

- (void)sendData:(nonnull NSData *)data withType:(uint8_t)type {
    size_t bodyLength = sizeof(SYMessage) + data.length;
    NSMutableData *mutableData = [NSMutableData dataWithCapacity:sizeof(size_t) + bodyLength];
    SYMessage msg = {
        .ts = CACurrentMediaTime(),
        .tag = type,
        .dataLength = (uint32_t)data.length
    };
    [mutableData appendBytes:&bodyLength length:sizeof(size_t)];
    [mutableData appendBytes:&msg length:sizeof(SYMessage)];
    [mutableData appendData:data];
    
    NSLog(@"Client:(ts: %f tag: %d len: %u)",
          msg.ts, msg.tag, msg.dataLength);
    
    [_acceptedSocket ?: _socket writeData:mutableData withTimeout:SEND_TIMEOUT tag:HEAD_TAG];
}

+ (instancetype)clientWithError:(NSError *__autoreleasing  _Nullable *)error {
    SYTCPDataLink *dataLink = [self new];
    BOOL isSuccess = [dataLink->_socket connectToHost:@"localhost"
                                               onPort:APP_PORT
                                                error:error];
    return isSuccess ? dataLink : nil;
}

+ (instancetype)serverWithError:(NSError *__autoreleasing  _Nullable *)error {
    SYTCPDataLink *dataLink = [self new];
    BOOL isSuccess = [dataLink->_socket acceptOnPort:APP_PORT error:error];
    return isSuccess ? dataLink : nil;
}

@end

@implementation SYTCPDataLink (GCDAsyncSocketDelegate)

- (void)socket:(GCDAsyncSocket *)sock didAcceptNewSocket:(GCDAsyncSocket *)newSocket {
    _acceptedSocket = newSocket;
    [_acceptedSocket readDataToLength:sizeof(size_t) withTimeout:READ_TIMEOUT tag:HEAD_TAG];
}

- (void)socket:(GCDAsyncSocket *)sock didReadData:(NSData *)data withTag:(long)tag {
    if (tag == HEAD_TAG) {
        size_t bodyLength = 0;
        [data getBytes:&bodyLength length:sizeof(size_t)];
        [sock readDataToLength:bodyLength withTimeout:READ_TIMEOUT tag:BODY_TAG];
    } else if (tag == BODY_TAG) {
        SYMessage msg = {};
        [data getBytes:&msg length:sizeof(SYMessage)];
        NSData *content = [data subdataWithRange:NSMakeRange(sizeof(SYMessage), msg.dataLength)];
        NSLog(@"Server:(ts: %f tag: %d len: %u(%ld))",
              msg.ts, msg.tag, msg.dataLength, content.length);
        [_delegate dataLink:self didReceiveData:content withMessage:msg];
        [_acceptedSocket readDataToLength:sizeof(size_t) withTimeout:READ_TIMEOUT tag:HEAD_TAG];
    }
}

- (void)socketDidDisconnect:(GCDAsyncSocket *)sock withError:(nullable NSError *)err {
    [_delegate dataLink:self didDisconnectWithError:err];
}

@end
