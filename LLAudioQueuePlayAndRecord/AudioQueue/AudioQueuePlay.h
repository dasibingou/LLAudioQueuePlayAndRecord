//
//  AudioQueuePlay.h
//  LLAudioQueuePlayAndRecord
//
//  Created by linling on 2019/2/20.
//  Copyright © 2019 llmodule. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "AudioQueueConfig.h"

NS_ASSUME_NONNULL_BEGIN

@interface AudioQueuePlay : NSObject

- (instancetype)initWithFile:(NSString *)file;

- (void)startPlay;

- (void)stop;

- (void)pause;

@end

NS_ASSUME_NONNULL_END
