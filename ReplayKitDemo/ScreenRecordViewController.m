//
//  ScreenRecordViewController.m
//  ReplayKitDemo
//
//  Created by 苏杨 on 2022/8/4.
//

#import "ScreenRecordViewController.h"

@import SYScreenRecorder;
@import ReplayKit;

@interface ScreenRecordViewController ()

@property (weak, nonatomic) IBOutlet UIButton *button;
@property (weak, nonatomic) IBOutlet RPSystemBroadcastPickerView *rpPickerView;

@end

@interface ScreenRecordViewController (SYScreenRecorderServerDelegate) <SYScreenRecorderServerDelegate>

@end

@implementation ScreenRecordViewController {
    SYScreenRecorderServer *_screenRecorder;
    SYAVWriter *_avWriter;
    __weak UIWindow *_rpPickerWindow;
    BOOL _videoDidOutput;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    _button.userInteractionEnabled = NO;
    
//  iOS 12.2系统以下，第一次启动时设置`preferredExtension`会筛选不到,
//  所以首次启动时先不设置`preferredExtension`
    BOOL needSetPreferredExtension = YES;
    if (@available(iOS 12.2, *)) {
        needSetPreferredExtension = YES;
    } else {
        NSString *isLaunchedKey = @"AppLaunched";
        BOOL isLaunched = [NSUserDefaults.standardUserDefaults boolForKey:isLaunchedKey];
        needSetPreferredExtension = isLaunched;
        if (!isLaunched) {
            [NSUserDefaults.standardUserDefaults setBool:YES forKey:isLaunchedKey];
        }
    }
    
    if (needSetPreferredExtension) {
        self.rpPickerView.preferredExtension =
        [NSBundle.mainBundle.bundleIdentifier stringByAppendingString:@".ReplayKitUpload"];
    }
    
    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(windowDidBecomeVisible:)
                                               name:UIWindowDidBecomeVisibleNotification
                                             object:nil];
    
    [self setup];
}

- (void)windowDidBecomeVisible:(NSNotification *)note {
    NSString *windowClassName = [[@"RP"
                                  stringByAppendingString:@"ModalPresentation"]
                                 stringByAppendingString:@"Window"];
    if (![NSStringFromClass([note.object class]) isEqualToString:windowClassName]) {
        return;
    }
    _rpPickerWindow = note.object;
}

- (void)videoDidOutput {
    if (!self.button.isUserInteractionEnabled) {
        self.button.userInteractionEnabled = YES;
        [self.button setTitle:@"Stop Capture" forState:UIControlStateNormal];
        [self hideRPPickerView];
    }
}

- (void)hideRPPickerView {
    _rpPickerWindow.rootViewController = nil;
    _rpPickerWindow.hidden = YES;
    
    [NSNotificationCenter.defaultCenter removeObserver:self
                                                  name:UIWindowDidBecomeVisibleNotification
                                                object:nil];
    //iOS 13上上述方法失效，采用URL使App回前台来间接关闭RPPickerWindow
    [UIApplication.sharedApplication openURL:[NSURL URLWithString:@"RPDemo://"]
                                     options:@{}
                           completionHandler:nil];
}

- (void)setup {
    _screenRecorder = [SYScreenRecorderServer startByUDPDataLink];
    _screenRecorder.delegate = self;
    [_screenRecorder startAudioCaptureRunning];
    
    [self setupAndStartAVWriter];
}

- (void)destroy {
    [_screenRecorder stopAudioCaptureRunning];
    [_screenRecorder stopScreenCapture];
    
    _screenRecorder = nil;
    
    [self stopAndDestroyAVWriter];
}

- (void)setupAndStartAVWriter {
    if (_avWriter) {
        return;
    }
    
    SYAVWriterConfig *config = [SYAVWriterConfig new];
    config.ouputPath = _videoOutputURL;
    config.videoBitRate = 5000 * 1000;
    config.maxKeyFrameInterval = 1;
    config.pixelBufferPixelFormat = kCVPixelFormatType_420YpCbCr8PlanarFullRange;
    config.fps = 30;
    
    _avWriter = [[SYAVWriter alloc] initWithConfig:config];
    [_avWriter startWriting];
}

- (void)stopAndDestroyAVWriter {
    [_avWriter stopWriting];
    _avWriter = nil;
}

- (IBAction)tapButton:(UIButton *)sender {
    [self destroy];
    [self performSegueWithIdentifier:@"exit" sender:self];
}

@end

@implementation ScreenRecordViewController (SYScreenRecorderServerDelegate)

- (void)screenRecorderServer:(nonnull SYScreenRecorderServer *)server audioSessionInterruption:(AVAudioSessionInterruptionType)interruptionType {
    
}

- (void)screenRecorderServer:(nonnull SYScreenRecorderServer *)server clientDidDisconnectWithError:(nullable NSError *)error {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self tapButton:self.button];
    });
}

- (void)screenRecorderServer:(nonnull SYScreenRecorderServer *)server didOutputAppAudio:(nonnull CMSampleBufferRef)appAudio {
    
}

- (void)screenRecorderServer:(nonnull SYScreenRecorderServer *)server didOutputMicAudio:(nonnull CMSampleBufferRef)micAudio {
    [_avWriter writeAudioBuffer:micAudio];
}

- (void)screenRecorderServer:(nonnull SYScreenRecorderServer *)server didOutputVideoFrame:(nonnull CVPixelBufferRef)videoFrame pts:(CMTime)pts{
    [_avWriter writeVideoBuffer:videoFrame presentationTimeStamp:pts];
    if (!_videoDidOutput) {
        _videoDidOutput = YES;
        dispatch_async(dispatch_get_main_queue(), ^{
            [self videoDidOutput];
        });
    }
}

@end

