//
//  ViewController.m
//  LLAudioQueuePlayAndRecord
//
//  Created by linling on 2019/2/20.
//  Copyright © 2019 llmodule. All rights reserved.
//

#import "ViewController.h"
#import "AudioQueuePlay.h"

@interface ViewController ()

@property (nonatomic, strong) AudioQueuePlay *audioPlayer;

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
}

- (IBAction)doPlay:(id)sender
{
    if (self.audioPlayer == nil) {
        NSString *filePath = [[NSBundle mainBundle] pathForResource:@"G.E.M.邓紫棋 - 喜欢你.mp3" ofType:nil];
        self.audioPlayer = [[AudioQueuePlay alloc] initWithFile:filePath];
    }
    [self.audioPlayer startPlay];
}
- (IBAction)doPause:(id)sender
{
    [self.audioPlayer pause];
}
- (IBAction)doStop:(id)sender
{
    [self.audioPlayer stop];
    self.audioPlayer = nil;
}

@end
