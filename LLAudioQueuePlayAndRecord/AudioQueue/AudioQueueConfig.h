//
//  AudioQueueConfig.h
//  LLAudioQueuePlayAndRecord
//
//  Created by linling on 2019/2/20.
//  Copyright © 2019 llmodule. All rights reserved.
//

#ifndef AudioQueueConfig_h
#define AudioQueueConfig_h

#import <AVFoundation/AVFoundation.h>

#define QUEUE_BUFFER_SIZE 3//队列缓冲个数

/**
 *  采样率，要转码为amr的话必须为8000
 需要注意，AAC并不是随便的码率都可以支持。比如如果PCM采样率是44100KHz，那么码率可以设置64000bps，如果是16K，可以设置为32000bps。
 
 */
#define kDefaultSamplebitRate 44100

typedef struct AQPlayerState {
    AudioStreamBasicDescription   mDataFormat;
    AudioQueueRef                 mQueue;
    AudioQueueBufferRef           mBuffers[QUEUE_BUFFER_SIZE];
    AudioFileID                   mAudioFile;
    UInt32                        bufferByteSize;
    SInt64                        mCurrentPacket;
    UInt32                        mNumPacketsToRead;
    AudioStreamPacketDescription  *mPacketDescs;
    bool                          mIsRunning;
}AQPlayerState;

#endif /* AudioQueueConfig_h */
