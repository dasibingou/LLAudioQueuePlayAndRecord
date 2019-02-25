//
//  AudioQueueSocketPlay.h
//  LLAudioQueuePlayAndRecord
//
//  Created by linling on 2019/2/22.
//  Copyright © 2019 llmodule. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "AudioQueueConfig.h"

NS_ASSUME_NONNULL_BEGIN

@interface AudioQueueSocketPlay : NSObject

@property (nonatomic, assign) AQPlayerState playerState;

+ (instancetype)shareInstance;

/**
 开始播放队列
 */
- (void)starPlayQueue:(BOOL)startPlay;
/**
 播放音频数据
 
 @param data 音频流数据
 */
- (void)playAudioData:(NSData *)data;

@end

NS_ASSUME_NONNULL_END
