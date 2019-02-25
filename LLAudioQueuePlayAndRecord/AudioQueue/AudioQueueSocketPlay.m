//
//  AudioQueueSocketPlay.m
//  LLAudioQueuePlayAndRecord
//
//  Created by linling on 2019/2/22.
//  Copyright © 2019 llmodule. All rights reserved.
//

#import "AudioQueueSocketPlay.h"

#import <UIKit/UIKit.h>
#import <AudioToolbox/AudioToolbox.h>
#import <AVFoundation/AVFoundation.h>
#include <pthread.h>

@interface AudioQueueSocketPlay ()

@property (strong, nonatomic) NSMutableArray *receiveData;//接收数据的数组
@property (strong, nonatomic) NSLock *synclockOut;//播放的bufffer同步
@property (nonatomic,assign) BOOL startPlay;

@end

@implementation AudioQueueSocketPlay

static pthread_mutex_t  playDataLock; //用pthread_mutex_t 线程锁效率比NSLock、@synchronized高些

+ (instancetype)shareInstance
{
    static AudioQueueSocketPlay *audioQueueHelpClass = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        audioQueueHelpClass = [[AudioQueueSocketPlay alloc] init];
    });
    return audioQueueHelpClass;
}

- (id)init
{
    self = [super init];
    if (self) {
        _receiveData = [[NSMutableArray alloc] init];
        _synclockOut = [[NSLock alloc] init];
        [[UIDevice currentDevice] setProximityMonitoringEnabled:YES];
#ifdef UseAmrEncode
#else
        [self setupACCAudioFormat];
#endif
        
        
        int rc;
        rc = pthread_mutex_init(&playDataLock,NULL);
        assert(rc == 0);
    }
    return self;
}

- (void)setupACCAudioFormat{
    //重置下
    memset(&_playerState.mDataFormat, 0, sizeof(_playerState.mDataFormat));
    _playerState.mDataFormat.mFormatID                   = kAudioFormatMPEG4AAC;
    _playerState.mDataFormat.mSampleRate                 = kDefaultSamplebitRate;
    _playerState.mDataFormat.mFramesPerPacket            = 1024;
    //设置通道数,这里先使用系统的测试下
    UInt32 inputNumberOfChannels = (UInt32)[[AVAudioSession sharedInstance] inputNumberOfChannels];
    _playerState.mDataFormat.mChannelsPerFrame = inputNumberOfChannels;
    
    OSStatus status     = 0;
    UInt32 targetSize   = sizeof(_playerState.mDataFormat);
    status              = AudioFormatGetProperty(kAudioFormatProperty_FormatInfo, 0, NULL, &targetSize, &_playerState.mDataFormat);
}

/**
 播放音频数据
 
 @param data 音频流数据
 */
- (void)playAudioData:(NSData *)data
{
    if (_startPlay == NO)
        return;
    
    pthread_mutex_lock(&playDataLock);
    [_receiveData addObject:data];
    pthread_mutex_unlock(&playDataLock);
    //------------------------
    
    [_synclockOut lock];
    
    
    /*
     为什么会静音，因为接收网络数据比播放慢，就是缓存给AudioQueue用的buffer播放完了，但网络还又数据没推送过来，这时，AudioQueue播放着空buffer，所以没有声音，而且AudioQueue的状态为start，过了一会后网络重新有数据推过来，AudioQueue播放的歌词就对不上了，所以解决歌词对不上的办法是：
     起一个线程，监控buffer，如果buffer为空，pause暂停掉AudioQueue，当buffer开始接收数据时重新start开始AudioQueue，这样就可以不跳过歌词，具体可以参考Matt Gallagher写的AudioStreamer，但是还是会暂停。。
     再进一步，在监控buffer为空的时候，同时，重新起一个网络stream去拿数据（当然要传一个已接收文件的offset偏移量，服务器也要根据offset实现基本的断点续传功能），这样效果会好一点，暂停也不会出现的很频繁。。
     */
    
    if ([_receiveData count] < 8) {//没有数据包的时候，要暂停队列，不然会出现播放一段时间后没有声音的情况。
        AudioQueuePause(_playerState.mQueue);
        NSLog(@"没有数据包，暂停队列");
    }else{
#ifdef UseAmrEncode
        //        AudioQueueStart(_outputQueue,NULL);//开启播放队列
#else
        AudioQueueStart(_playerState.mQueue,NULL);//开启播放队列
        NSLog(@"有数据包，播放队列");
#endif
    }
    
    
    
    [_synclockOut unlock];
    
}

#pragma mark  初始化播放队列

- (void)initPlayAudioQueue
{
    //创建一个输出队列
    int inBufferByteSize = 1024*2*_playerState.mDataFormat.mChannelsPerFrame;
    
#ifdef UseAmrEncode
    OSStatus status = AudioQueueNewOutput(&_playerState.mDataFormat, PlayCallback, (__bridge void *) self, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode, 0,&_playerState.mQueue);
    
#else
    inBufferByteSize = 1024*2*_playerState.mDataFormat.mChannelsPerFrame;
    OSStatus status = AudioQueueNewOutput(&_playerState.mDataFormat, PlayCallback, (__bridge void*)self, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode, 0,&_playerState.mQueue);
#endif
    NSLog(@"status ：%d",status);
    //创建并分配缓冲区空间3个缓冲区
    for (int i=0; i < QUEUE_BUFFER_SIZE; ++i) {
        AudioQueueAllocateBuffer(_playerState.mQueue, inBufferByteSize, &_playerState.mBuffers[i]);
        makeSilent(_playerState.mBuffers[i]);  //改变数据
        //        AudioStreamPacketDescription *paks = calloc(sizeof(AudioStreamPacketDescription), 1);
        //        paks[0].mStartOffset = 0;
        //        paks[0].mDataByteSize = 0;
        //        CheckError(AudioQueueEnqueueBuffer(_outputQueue, _outputBuffers[i],1, paks), "cant enqueue");
        AudioQueueEnqueueBuffer(_playerState.mQueue,_playerState.mBuffers[i],0,NULL);
    }
    
    
    //-----设置音量
    Float32 gain = 5.0;                                       // 1
    // Optionally, allow user to override gain setting here 设置音量
    AudioQueueSetParameter (_playerState.mQueue,kAudioQueueParam_Volume,gain);
}

// 输出回调、播放回调
static void PlayCallback(void *aqData,AudioQueueRef inAQ,AudioQueueBufferRef inBuffer)
{
    AudioQueueSocketPlay *aq = [AudioQueueSocketPlay shareInstance];
    
    BOOL  couldSignal = NO;
    static int lastIndex = 0;
    static int packageCounte = 3;
    
    if (aq.receiveData.count > packageCounte) {
        couldSignal = YES;
    }
    
    if (couldSignal) {
        @autoreleasepool {
            NSMutableData *data = [[NSMutableData alloc] init];
            AudioStreamPacketDescription *packs = calloc(sizeof(AudioStreamPacketDescription), packageCounte);
            for (int i = 0; i < packageCounte; i++) {
                NSData *audio = aq.receiveData.firstObject;
                [data appendData:audio];
                packs[i].mStartOffset = lastIndex;
                packs[i].mDataByteSize = (UInt32)audio.length;
                lastIndex += audio.length;
                
                pthread_mutex_lock(&playDataLock);
                [aq.receiveData removeObjectAtIndex:0];
                pthread_mutex_unlock(&playDataLock);
            }
            memcpy(inBuffer->mAudioData, [data bytes], data.length);
            inBuffer->mAudioDataByteSize = (UInt32)data.length;
            CheckError(AudioQueueEnqueueBuffer(aq.playerState.mQueue, inBuffer, packageCounte, packs), "cant enqueue");
            free(packs);
        }
    } else {
        NSLog(@"makeSilent");
        makeSilent(inBuffer);
        AudioStreamPacketDescription *paks = calloc(sizeof(AudioStreamPacketDescription), 1);
        paks[0].mStartOffset = 0;
        paks[0].mDataByteSize = 0;
        CheckError(AudioQueueEnqueueBuffer(aq.playerState.mQueue, inBuffer,1, paks), "cant enqueue");
    }
}

static void CheckError(OSStatus error,const char *operaton){
    if (error==noErr) {
        return;
    }
    char errorString[20]={};
    *(UInt32 *)(errorString+1)=CFSwapInt32HostToBig(error);
    if (isprint(errorString[1])&&isprint(errorString[2])&&isprint(errorString[3])&&isprint(errorString[4])) {
        errorString[0]=errorString[5]='\'';
        errorString[6]='\0';
    }else{
        sprintf(errorString, "%d",(int)error);
    }
    fprintf(stderr, "Error:%s (%s)\n",operaton,errorString);
    //    exit(1);
}

void makeSilent(AudioQueueBufferRef buffer)
{
    for (int i=0; i < buffer->mAudioDataBytesCapacity; i++) {
        buffer->mAudioDataByteSize = buffer->mAudioDataBytesCapacity;
        UInt8 * samples = (UInt8 *) buffer->mAudioData;
        samples[i]=0;
    }
}

- (void)starPlayQueue:(BOOL)startPlay
{
    _startPlay = startPlay;
    if (_startPlay) {
        pthread_mutex_lock(&playDataLock);
        [_receiveData removeAllObjects];
        [self initPlayAudioQueue];
#ifdef UseAmrEncode
        AudioQueueStart(_outputQueue,NULL);//开启播放队列
#else
#endif
        pthread_mutex_unlock(&playDataLock);
        
    }else{
        [_synclockOut lock];
        AudioQueueDispose(_playerState.mQueue, YES);
        [_synclockOut unlock];
    }
    
}

@end
