//
//  AudioQueueSocketRecord.m
//  LLAudioQueuePlayAndRecord
//
//  Created by linling on 2019/2/23.
//  Copyright © 2019 llmodule. All rights reserved.
//

#import "AudioQueueSocketRecord.h"
#import "AudioQueueSocketPlay.h"

#import <AudioToolbox/AudioToolbox.h>
#import <AVFoundation/AVFoundation.h>
#import <UIKit/UIKit.h>
#include <pthread.h>

@interface AudioQueueSocketRecord ()
{
    AudioConverterRef               _encodeConvertRef;  ///PCM转ACC的编码器
}

@property (nonatomic,assign) BOOL startRecord;
@property (strong, nonatomic) NSLock *synclockIn;
@property (nonatomic, assign) AQPlayerState playerState;

@end

@implementation AudioQueueSocketRecord

static pthread_mutex_t  playDataLock; //用pthread_mutex_t 线程锁效率比NSLock、@synchronized高些


+ (instancetype)shareInstance
{
    static AudioQueueSocketRecord *audioQueueHelpClass = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        audioQueueHelpClass = [[AudioQueueSocketRecord alloc] init];
    });
    return audioQueueHelpClass;
}


- (id)init
{
    self = [super init];
    if (self) {
        _synclockIn = [[NSLock alloc] init];
        [[UIDevice currentDevice] setProximityMonitoringEnabled:YES];
        //设置录音的参数
        [self setupPCMAudioFormat];
        
        int rc;
        rc = pthread_mutex_init(&playDataLock,NULL);
        assert(rc == 0);
    }
    return self;
}

// 设置录音格式
- (void)setupPCMAudioFormat
{
    //重置下
    memset(&_playerState.mDataFormat, 0, sizeof(_playerState.mDataFormat));
    //    int tmp = [[AVAudioSession sharedInstance] sampleRate];
    //设置采样率，这里先获取系统默认的测试下 //TODO:
    //采样率的意思是每秒需要采集的帧数
    _playerState.mDataFormat.mSampleRate = kDefaultSamplebitRate;
    //设置通道数,这里先使用系统的测试下
    UInt32 inputNumberOfChannels = (UInt32)[[AVAudioSession sharedInstance] inputNumberOfChannels];
    _playerState.mDataFormat.mChannelsPerFrame = inputNumberOfChannels;
    //设置format，怎么称呼不知道。
    _playerState.mDataFormat.mFormatID = kAudioFormatLinearPCM;
    _playerState.mDataFormat.mFormatFlags = kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked;
    //每个通道里，一帧采集的bit数目
    _playerState.mDataFormat.mBitsPerChannel = 16;
    //结果分析: 8bit为1byte，即为1个通道里1帧需要采集2byte数据，再*通道数，即为所有通道采集的byte数目。
    //所以这里结果赋值给每帧需要采集的byte数目，然后这里的packet也等于一帧的数据。
    _playerState.mDataFormat.mBytesPerPacket = _playerState.mDataFormat.mBytesPerFrame = (_playerState.mDataFormat.mBitsPerChannel / 8) * _playerState.mDataFormat.mChannelsPerFrame;
    _playerState.mDataFormat.mFramesPerPacket = 1;// 用AudioQueue采集pcm需要这么设置
}

#pragma mark  初始化录音的队列


/**
 生成编码器
 
 @param sourceDes 音频原格式 PCM
 @param targetDes 音频目标格式 ACC
 */
- (void)makeEncodeAudioConverterSourceDes:(AudioStreamBasicDescription)sourceDes targetDes:(AudioStreamBasicDescription)targetDes
{
    // 此处目标格式其他参数均为默认，系统会自动计算，否则无法进入encodeConverterComplexInputDataProc回调
    
    OSStatus status     = 0;
    UInt32 targetSize   = sizeof(targetDes);
    status              = AudioFormatGetProperty(kAudioFormatProperty_FormatInfo, 0, NULL, &targetSize, &targetDes);
    
    // 选择软件编码
    AudioClassDescription audioClassDes;
    status = AudioFormatGetPropertyInfo(kAudioFormatProperty_Encoders,
                                        sizeof(targetDes.mFormatID),
                                        &targetDes.mFormatID,
                                        &targetSize);
    //    log4cplus_info("pcm","get kAudioFormatProperty_Encoders status:%d",(int)status);
    
    UInt32 numEncoders = targetSize/sizeof(AudioClassDescription);
    AudioClassDescription audioClassArr[numEncoders];
    AudioFormatGetProperty(kAudioFormatProperty_Encoders,
                           sizeof(targetDes.mFormatID),
                           &targetDes.mFormatID,
                           &targetSize,
                           audioClassArr);
    //    log4cplus_info("pcm","wrirte audioClassArr status:%d",(int)status);
    
    for (int i = 0; i < numEncoders; i++) {
        if (audioClassArr[i].mSubType == kAudioFormatMPEG4AAC && audioClassArr[i].mManufacturer == kAppleSoftwareAudioCodecManufacturer) {
            memcpy(&audioClassDes, &audioClassArr[i], sizeof(AudioClassDescription));
            break;
        }
    }
    
    status          = AudioConverterNewSpecific(&sourceDes, &targetDes, 1,
                                                &audioClassDes, &_encodeConvertRef);
    
    targetSize      = sizeof(sourceDes);
    status          = AudioConverterGetProperty(_encodeConvertRef, kAudioConverterCurrentInputStreamDescription, &targetSize, &sourceDes);
    
    targetSize      = sizeof(targetDes);
    status          = AudioConverterGetProperty(_encodeConvertRef, kAudioConverterCurrentOutputStreamDescription, &targetSize, &targetDes);
    
    // 设置码率，需要和采样率对应
    UInt32 bitRate  = kDefaultSamplebitRate;
    targetSize      = sizeof(bitRate);
    status          = AudioConverterSetProperty(_encodeConvertRef,
                                                kAudioConverterEncodeBitRate,
                                                targetSize, &bitRate);
}


- (void)initRecordAudioQueue
{
    AudioQueueSocketPlay *aqsp = [AudioQueueSocketPlay shareInstance];
#ifdef UseAmrEncode
    
#else
    [self makeEncodeAudioConverterSourceDes:_playerState.mDataFormat targetDes:aqsp.playerState.mDataFormat];
#endif
    //创建一个录制音频队列
    AudioQueueNewInput (&_playerState.mDataFormat,RecorderCallback,(__bridge void *)self,NULL,NULL,0,&_playerState.mQueue);
    //创建录制音频队列缓冲区
    for (int i = 0; i < QUEUE_BUFFER_SIZE; i++) {
        int inBufferByteSize =1024 * 2 * _playerState.mDataFormat.mChannelsPerFrame;
        AudioQueueAllocateBuffer (_playerState.mQueue,inBufferByteSize,&_playerState.mBuffers[i]);
        AudioQueueEnqueueBuffer (_playerState.mQueue,(_playerState.mBuffers[i]),0,NULL);
    }
}

//录音回调
void RecorderCallback (
                       void                                *inUserData,
                       AudioQueueRef                       inAQ,
                       AudioQueueBufferRef                 inBuffer,
                       const AudioTimeStamp                *inStartTime,
                       UInt32                              inNumberPackets,
                       const AudioStreamPacketDescription  *inPacketDescs
                       )
{
    /*
     inNumPackets 总包数：音频队列缓冲区大小 （在先前估算缓存区大小为2048）/ （dataFormat.mFramesPerPacket (采集数据每个包中有多少帧，此处在初始化设置中为1) * dataFormat.mBytesPerFrame（每一帧中有多少个字节，此处在初始化设置中为每一帧中两个字节）），所以用捕捉PCM数据时inNumPackets为1024。
     注意：如果采集的数据是PCM需要将dataFormat.mFramesPerPacket设置为1，而本例中最终要的数据为AAC,在AAC格式下需要将mFramesPerPacket设置为1024.也就是采集到的inNumPackets为1，所以inNumPackets这个参数在此处可以忽略，因为在转换器中传入的inNumPackets应该为AAC格式下默认的1，在此后写入文件中也应该传的是转换好的inNumPackets。
     */
    
    // collect pcm data，可以在此存储
    
    //    FLAudioQueueHelpClass *aq = [FLAudioQueueHelpClass shareInstance];
    
    
#ifdef UseAmrEncode
    pthread_mutex_lock(&playDataLock);
    if (inNumberPackets > 0) {
        //        NSLog(@"processAudioData :%u", (unsigned int)inBuffer->mAudioDataByteSize);
        NSData *pcmData = [[NSData alloc] initWithBytes:inBuffer->mAudioData length:inBuffer->mAudioDataByteSize];
        //pcm数据不为空时，编码为amr格式
        if (pcmData && pcmData.length > 0) {
            NSData *amrData = [RecordAmrCode encodePCMDataToAMRData:pcmData];
            if ([FLAudioQueueHelpClass shareInstance].recordWithData) {
                [FLAudioQueueHelpClass shareInstance].recordWithData([amrData copy]);
                NSLog(@"%@: send data %lu",[[UIDevice currentDevice] name] , [amrData length]);
            }
        }
    }
    pthread_mutex_unlock(&playDataLock);
#else
    
    AudioBufferList *bufferList = convertPCMToAAC(inBuffer);
    
    NSData *accData = [[NSData alloc] initWithBytes:bufferList->mBuffers[0].mData length:bufferList->mBuffers[0].mDataByteSize];
    if([accData length] > 0)
    {
        dispatch_async(dispatch_get_global_queue(0, 0), ^{
            if ([AudioQueueSocketRecord shareInstance].recordWithData && [accData length] > 10)
                [AudioQueueSocketRecord shareInstance].recordWithData(accData);
        });
        //        NSLog(@"%@: send data %lu",[[UIDevice currentDevice] name] , [accData length]);
        
    }
    // free memory
    free(bufferList->mBuffers[0].mData);
    free(bufferList);
    
#endif
    AudioQueueEnqueueBuffer (inAQ,inBuffer,0,NULL);
    
}

#pragma mark - PCM -> AAC

#pragma mark encodeConverterComplexInputDataProc1

OSStatus encodeConverterComplexInputDataProc1(AudioConverterRef              inAudioConverter,
                                              UInt32                         *ioNumberDataPackets,
                                              AudioBufferList                *ioData,
                                              AudioStreamPacketDescription   **outDataPacketDescription,
                                              void                           *inUserData) {
    AudioQueueSocketRecord *aq = [AudioQueueSocketRecord shareInstance];
    ioData->mBuffers[0].mData           = inUserData;
    ioData->mBuffers[0].mNumberChannels = aq.playerState.mDataFormat.mChannelsPerFrame;
    ioData->mBuffers[0].mDataByteSize   = 1024*2; // 2 为dataFormat.mBytesPerFrame 每一帧的比特数
    return 0;
}

#pragma mark PCM -> AAC

AudioBufferList* convertPCMToAAC (AudioQueueBufferRef inBuffer) {
    AudioQueueSocketRecord *aq = [AudioQueueSocketRecord shareInstance];
    //    [aq.synclockIn lock];
    UInt32   maxPacketSize    = 0;
    UInt32   size             = sizeof(maxPacketSize);
    OSStatus status;
    status = AudioConverterGetProperty(aq->_encodeConvertRef,
                                       kAudioConverterPropertyMaximumOutputPacketSize,
                                       &size,
                                       &maxPacketSize);
    //    log4cplus_info("AudioConverter","kAudioConverterPropertyMaximumOutputPacketSize status:%d \n",(int)status);
    AudioBufferList *bufferList             = (AudioBufferList *)malloc(sizeof(AudioBufferList));
    bufferList->mNumberBuffers              = 1;
    bufferList->mBuffers[0].mNumberChannels = aq.playerState.mDataFormat.mChannelsPerFrame;
    bufferList->mBuffers[0].mData           = malloc(maxPacketSize);
    bufferList->mBuffers[0].mDataByteSize   = inBuffer->mAudioDataByteSize;
    AudioStreamPacketDescription outputPacketDescriptions;
    // inNumPackets设置为1表示编码产生1帧数据即返回，官方：On entry, the capacity of outOutputData expressed in packets in the converter's output format. On exit, the number of packets of converted data that were written to outOutputData. 在输入表示输出数据的最大容纳能力 在转换器的输出格式上，在转换完成时表示多少个包被写入
    UInt32 inNumPackets = 1;
    
    // inNumPackets设置为1表示编码产生1帧数据即返回
    status = AudioConverterFillComplexBuffer(aq->_encodeConvertRef,
                                             encodeConverterComplexInputDataProc1,
                                             inBuffer->mAudioData,
                                             &inNumPackets,
                                             bufferList,
                                             &outputPacketDescriptions);
    
    //    if (status == 0) {
    //        NSLog(@"bufferList->mBuffers[0].mDataByteSize :%u",(unsigned int)bufferList->mBuffers[0].mDataByteSize);
    //    }
    //
    //    [aq.synclockIn lock];
    
    return bufferList;
}

- (void)startRecordQueue:(BOOL)startRecord
{
    _startRecord = startRecord;
    
    if (_startRecord) {
        [self initRecordAudioQueue];
        //开启录制队列
        AudioQueueStart(_playerState.mQueue, NULL);
    }else{
        [_synclockIn lock];
        AudioQueueDispose(_playerState.mQueue, YES);
        [_synclockIn unlock];
    }
    
}

@end
