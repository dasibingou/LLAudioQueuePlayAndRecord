//
//  UDPNATManager.h
//  LLAudioQueuePlayAndRecord
//
//  Created by linling on 2019/2/25.
//  Copyright © 2019 llmodule. All rights reserved.
//

#import <Foundation/Foundation.h>

typedef void(^RequestCompletion)(id data,id msg);

NS_ASSUME_NONNULL_BEGIN

@interface UDPNATManager : NSObject

@property (nonatomic, assign) BOOL isUdpNatTranting;

+ (instancetype)sharedManager;

- (NSUInteger)sendDataReturnBlock:(RequestCompletion)block;

- (BOOL)sendDataWithTargetIP:(NSString *)targetIP targetPort:(NSString *)targetPort content:(NSString *)content;

//test
- (void)sendTestData:(NSData *)data withIP:(NSString *)ip withPort:(uint16_t)port;


@end

NS_ASSUME_NONNULL_END
