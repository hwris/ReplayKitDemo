//
//  ViewController.m
//  ReplayKitDemo
//
//  Created by 苏杨 on 2022/6/26.
//

#import "ViewController.h"
#import <UIKit/UIActivityViewController.h>

#import "ScreenRecordViewController.h"

@interface ViewController ()

@end

@implementation ViewController

- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    if ([segue.identifier isEqualToString:@"capture"]) {
        ScreenRecordViewController *vc = segue.destinationViewController;
        NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:@"demo.mp4"];
        if ([NSFileManager.defaultManager fileExistsAtPath:path]) {
            [NSFileManager.defaultManager removeItemAtPath:path error:nil];
        }
        vc.videoOutputURL = [NSURL fileURLWithPath:path];
    }
}


- (IBAction)screenReacordUnwind:(UIStoryboardSegue *)sender {
    ScreenRecordViewController *vc = sender.sourceViewController;
    NSURL *videoOutputURL = vc.videoOutputURL;
    dispatch_async(dispatch_get_main_queue(), ^{
        UIActivityViewController *shareVC = [[UIActivityViewController alloc] initWithActivityItems:@[videoOutputURL] applicationActivities:nil];
        [self presentViewController:shareVC animated:YES completion:nil];
    });
}

@end
