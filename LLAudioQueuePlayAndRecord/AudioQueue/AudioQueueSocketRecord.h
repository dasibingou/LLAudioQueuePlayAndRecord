//
//  AudioQueueSocketRecord.h
//  LLAudioQueuePlayAndRecord
//
//  Created by linling on 2019/2/23.
//  Copyright © 2019 llmodule. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "AudioQueueConfig.h"

NS_ASSUME_NONNULL_BEGIN

@interface AudioQueueSocketRecord : NSObject

@property (copy, nonatomic) void (^recordWithData)(NSData *audioData);

+ (instancetype)shareInstance;

- (void)startRecordQueue:(BOOL)startRecord;

@end

NS_ASSUME_NONNULL_END
