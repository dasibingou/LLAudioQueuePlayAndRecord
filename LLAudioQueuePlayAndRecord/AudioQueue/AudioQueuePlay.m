//
//  AudioQueuePlay.m
//  LLAudioQueuePlayAndRecord
//
//  Created by linling on 2019/2/20.
//  Copyright © 2019 llmodule. All rights reserved.
//

#import "AudioQueuePlay.h"

#import <AVFoundation/AVFoundation.h>

//The Playback Audio Queue Callback
static void HandleOutputBuffer(void* aqData,AudioQueueRef inAQ,AudioQueueBufferRef inBuffer){
    AQPlayerState *pAqData = (AQPlayerState *) aqData;
    //    if (pAqData->mIsRunning == 0) return; // 注意苹果官方文档这里有这一句,应该是有问题,这里应该是判断如果pAqData->isDone??
    printf("回调\n");
    UInt32 numBytesReadFromFile = 4096;
    UInt32 numPackets = pAqData->mNumPacketsToRead;
    //    AudioFileReadPackets(pAqData->mAudioFile,false,&numBytesReadFromFile,pAqData->mPacketDescs,pAqData->mCurrentPacket,&numPackets,inBuffer->mAudioData);
    AudioFileReadPacketData(pAqData->mAudioFile, false, &numBytesReadFromFile, pAqData->mPacketDescs, pAqData->mCurrentPacket, &numPackets, inBuffer->mAudioData);
    
    if (numPackets > 0) {
        printf("numPackets > 0  播放==%u\n",(unsigned int)numBytesReadFromFile);
        inBuffer->mAudioDataByteSize = numBytesReadFromFile;
        AudioQueueEnqueueBuffer(inAQ,inBuffer,(pAqData->mPacketDescs ? numPackets : 0),pAqData->mPacketDescs);
        pAqData->mCurrentPacket += numPackets;
    } else {
        printf("numPackets <= 0");
        if (pAqData->mIsRunning) {
            
        }
        AudioQueueStop(inAQ,false);
        pAqData->mIsRunning = false;
    }
}

void DeriveBufferSize (AudioStreamBasicDescription inDesc,UInt32 maxPacketSize,Float64 inSeconds,UInt32 *outBufferSize,UInt32 *outNumPacketsToRead) {
    
    static const int maxBufferSize = 0x10000;
    static const int minBufferSize = 0x4000;
    
    if (inDesc.mFramesPerPacket != 0) {
        //如果每个Packet不止一个Frame，则按照包进行计算
        Float64 numPacketsForTime = inDesc.mSampleRate / inDesc.mFramesPerPacket * inSeconds;
        *outBufferSize = numPacketsForTime * maxPacketSize;
    } else {
        //如果每个Packet只有一个Frame，则直接确定缓冲区大小
        *outBufferSize = maxBufferSize > maxPacketSize ? maxBufferSize : maxPacketSize;
    }
    
    if (*outBufferSize > maxBufferSize && *outBufferSize > maxPacketSize){
        *outBufferSize = maxBufferSize;
    }
    else {
        if (*outBufferSize < minBufferSize){
            *outBufferSize = minBufferSize;
        }
    }
    
    *outNumPacketsToRead = *outBufferSize / maxPacketSize;
}

@interface AudioQueuePlay ()

@property (nonatomic, copy) NSString *filePath;
@property (nonatomic, strong) dispatch_queue_t playQueue;
@property (nonatomic, assign) AQPlayerState playerState;
@property (nonatomic, assign) BOOL isPause;

@end

@implementation AudioQueuePlay

- (instancetype)initWithFile:(NSString *)file
{
    self = [super init];
    if (self) {
        self.filePath = file;
        NSString *queueLabel = [NSString stringWithFormat:@"play queue %@",file];
        //播放线程队列
        self.playQueue = dispatch_queue_create([queueLabel cStringUsingEncoding:NSUTF8StringEncoding], DISPATCH_QUEUE_SERIAL);
        [self createAudioQueue];
    }
    return self;
}

- (void)createAudioQueue
{
    CFStringRef cffile = (__bridge CFStringRef)self.filePath;
    //创建url
    CFURLRef cfurl = CFURLCreateWithFileSystemPath(kCFAllocatorDefault, cffile, kCFURLPOSIXPathStyle, false);
    //打开文件
    int error = AudioFileOpenURL(cfurl, kAudioFileReadPermission, 0, &_playerState.mAudioFile);
    if ([self checkError:error] == NO) {
        return;
    }else {
        NSLog(@"打开文件成功");
    }
    
    //释放url
    CFRelease(cfurl);
    //计算结构体数据大小
    UInt32 dateFormatSize = sizeof(_playerState.mDataFormat);
    NSLog(@"dateFormatSize == %u",(unsigned int)dateFormatSize);
    //获取格式
    error = AudioFileGetProperty(_playerState.mAudioFile, kAudioFilePropertyDataFormat, &dateFormatSize, &_playerState.mDataFormat);
    if ([self checkError:error] == NO) {
        NSLog(@"格式获取失败");
        return;
    }else {
        NSLog(@"格式获取成功");
    }
    
    //创建新的队列
    error = AudioQueueNewOutput(&_playerState.mDataFormat, HandleOutputBuffer, &_playerState, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode, 0, &_playerState.mQueue);
    if ([self checkError:error] == NO) {
        NSLog(@"队列创建失败");
        return;
    }else {
        NSLog(@"队列创建成功");
    }
    
    //得到最大包的大小
    UInt32 maxPacketSize;
    UInt32 propertySize = sizeof(maxPacketSize);
    error = AudioFileGetProperty(_playerState.mAudioFile, kAudioFilePropertyPacketSizeUpperBound, &propertySize, &maxPacketSize);
    if ([self checkError:error] == NO) {
        NSLog(@"取最大包大小失败");
        return;
    }else {
        NSLog(@"最大包大小为：%u",(unsigned int)maxPacketSize);
    }
    
    //计算buffer size大小
    DeriveBufferSize(_playerState.mDataFormat, maxPacketSize, 0.5, &_playerState.bufferByteSize, &_playerState.mNumPacketsToRead);
    
    bool isFormatVBR = (_playerState.mDataFormat.mBytesPerPacket == 0 ||_playerState.mDataFormat.mFramesPerPacket == 0);
    
    if (isFormatVBR) {
        _playerState.mPacketDescs =(AudioStreamPacketDescription*) malloc (_playerState.mNumPacketsToRead * sizeof (AudioStreamPacketDescription));
    } else {
        _playerState.mPacketDescs = NULL;
    }
    
    _playerState.mCurrentPacket = 0;
    //缓存
    for (int i = 0; i < QUEUE_BUFFER_SIZE; i++) {
        error = AudioQueueAllocateBuffer(_playerState.mQueue, _playerState.bufferByteSize, &_playerState.mBuffers[i]);
        if (error != NO) {
            NSLog(@"缓存失败");
            return;
        }else {
            NSLog(@"缓存成功");
        }
        HandleOutputBuffer(&_playerState,_playerState.mQueue,_playerState.mBuffers[i]);
    }
}

- (void)startPlay {
    if (self.isPause == YES) {
        AudioQueueStart(_playerState.mQueue, NULL);
    }else {
        dispatch_async(self.playQueue, ^{
            Float32 gain = 10.0;
            
            // Optionally, allow user to override gain setting here
            AudioQueueSetParameter (
                                    _playerState.mQueue,
                                    kAudioQueueParam_Volume,
                                    gain
                                    );
            _playerState.mIsRunning = true;
            
            AudioQueueStart(_playerState.mQueue, NULL);
            
            printf("Playing...\n");
            
            [[NSRunLoop currentRunLoop] run];
        });
    }
    
}

- (void)stop {
    self.isPause = NO;
    AudioQueueStop(_playerState.mQueue, true);
}

- (void)pause {
    self.isPause = YES;
    AudioQueuePause(_playerState.mQueue);
}

- (BOOL)checkError:(int)error {
    if (error == noErr) {
        return YES;
    }
    if (error == kAudioFileUnspecifiedError) {
        NSLog(@"kAudioFileUnspecifiedError");
    } else if(error == kAudioFileUnsupportedFileTypeError){
        NSLog(@"kAudioFileUnsupportedFileTypeError");
    }else if(error == kAudioFileUnsupportedDataFormatError){
        NSLog(@"kAudioFileUnsupportedDataFormatError");
    }else if(error == kAudioFileUnsupportedPropertyError){
        NSLog(@"kAudioFileUnsupportedPropertyError");
    }else if(error == kAudioFileBadPropertySizeError){
        NSLog(@"kAudioFileBadPropertySizeError");
    }else if(error == kAudioFilePermissionsError){
        NSLog(@"kAudioFilePermissionsError");
    }else if(error == kAudioFileNotOptimizedError){
        NSLog(@"kAudioFileNotOptimizedError");
    }else if(error == kAudioFileInvalidChunkError){
        NSLog(@"kAudioFileInvalidChunkError");
    }else if(error == kAudioFileDoesNotAllow64BitDataSizeError){
        NSLog(@"kAudioFileDoesNotAllow64BitDataSizeError");
    }else if(error == kAudioFileInvalidPacketOffsetError){
        NSLog(@"kAudioFileInvalidPacketOffsetError");
    }else if(error == kAudioFileInvalidFileError){
        NSLog(@"kAudioFileInvalidFileError");
    }else if(error == kAudioFileOperationNotSupportedError){
        NSLog(@"kAudioFileOperationNotSupportedError");
    }else if(error == kAudioFileNotOpenError){
        NSLog(@"kAudioFileNotOpenError");
    }else if(error == kAudioFileEndOfFileError){
        NSLog(@"kAudioFileEndOfFileError");
    }else if(error == kAudioFilePositionError){
        NSLog(@"kAudioFilePositionError");
    }else if(error == kAudioFileFileNotFoundError){
        NSLog(@"kAudioFileFileNotFoundError");
    }
    
    return NO;
}

@end
