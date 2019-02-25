//
//  AudioQueueRecord.m
//  LLAudioQueuePlayAndRecord
//
//  Created by linling on 2019/2/20.
//  Copyright © 2019 llmodule. All rights reserved.
//

#import "AudioQueueRecord.h"

#import <AVFoundation/AVFoundation.h>
#import <UIKit/UIKit.h>

@interface AudioQueueRecord ()
{
    AudioStreamBasicDescription audioDescription;///音频参数
}

@property (nonatomic,assign) BOOL startRecord;

@property(nonatomic,strong)NSURL* recordFileUrl;

@property(nonatomic,strong)AVAudioRecorder* recorder;

@property(nonatomic,strong)NSDictionary* recordSetting;

@property(nonatomic,strong)AVAudioFormat* audioFormat;

@end

@implementation AudioQueueRecord

- (AVAudioFormat *)audioFormat
{
    if (!_audioFormat) {
        audioDescription.mSampleRate = kDefaultSamplebitRate;
        audioDescription.mFormatID = kAudioFormatLinearPCM;
        audioDescription.mFormatFlags = kAudioFormatFlagIsPacked | kAudioFormatFlagIsSignedInteger;
        audioDescription.mChannelsPerFrame = 1;
        audioDescription.mFramesPerPacket = 1;
        audioDescription.mBitsPerChannel = 16;
        audioDescription.mBytesPerFrame = (audioDescription.mBitsPerChannel/8)*audioDescription.mChannelsPerFrame;
        audioDescription.mBytesPerPacket = audioDescription.mBytesPerFrame*audioDescription.mFramesPerPacket;
        
        _audioFormat = [[AVAudioFormat alloc] initWithStreamDescription:&audioDescription];
    }
    return _audioFormat;
}

//将语音录制进指定路径的文件
- (void)startRecordToFilePath:(NSString *)filePath {
    AVAudioSession *session = [AVAudioSession sharedInstance];
    NSError *sessionError;
    //设置我们需要的功能
    [session setCategory:AVAudioSessionCategoryPlayAndRecord error:&sessionError];
    if (session == nil) {
        NSLog(@"Error creating session: %@",[sessionError description]);
    }else{
        //设置成功则启动激活会话
        [session setActive:YES error:nil];
    }
    //录制文件的路径
    self.recordFileUrl = [NSURL fileURLWithPath:filePath];
    
    if ([[[UIDevice currentDevice] systemVersion] floatValue] < 10.0) {
        //iOS10之前设置参数为字典设置
        NSDictionary *dict = @{AVSampleRateKey:@(audioDescription.mSampleRate),//采样率 8000/11025/22050/44100/96000（影响音频的质量）
                               AVFormatIDKey:@(audioDescription.mFormatID),// 音频格式
                               AVLinearPCMBitDepthKey:@(audioDescription.mBitsPerChannel), //采样位数 8、16、24、32, 默认为16
                               AVNumberOfChannelsKey:@(audioDescription.mChannelsPerFrame),// 音频通道数 1 或 2
                               AVEncoderAudioQualityKey:@(AVAudioQualityHigh),//录音质量
                               AVLinearPCMIsFloatKey:@(NO),
                               };
        self.recorder = [[AVAudioRecorder alloc] initWithURL:self.recordFileUrl settings:dict error:&sessionError];
    }else {
        //audioDescription为第一步创建的格式对象
        self.audioFormat = [[AVAudioFormat alloc] initWithStreamDescription:&(audioDescription)];
        //iOS10后可以直接传入AVAudioFormat对象
        self.recorder = [[AVAudioRecorder alloc] initWithURL:self.recordFileUrl format:self.audioFormat error:&sessionError];
    }
    
    if (self.recorder) {
        [self.recorder record];
    }else{
        NSLog(@"音频格式和文件存储格式不匹配,无法初始化Recorder");
    }
}

- (void)playAudioByFilePath:(NSString *)path
{
    NSData *pcmData = [NSData dataWithContentsOfFile:path];
    NSError *error;
    AVAudioPlayer *avaudioPlayer = [[AVAudioPlayer alloc] initWithData:pcmData error:&error];
    [avaudioPlayer play];
}

@end
