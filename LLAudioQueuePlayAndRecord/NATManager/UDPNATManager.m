//
//  UDPNATManager.m
//  LLAudioQueuePlayAndRecord
//
//  Created by linling on 2019/2/25.
//  Copyright © 2019 llmodule. All rights reserved.
//

#import "UDPNATManager.h"

#import "GCDAsyncUdpSocket.h"

@interface UDPNATManager () <GCDAsyncUdpSocketDelegate>

@property (nonatomic, strong) GCDAsyncUdpSocket *udpSocket;

@property (nonatomic, strong) dispatch_queue_t socketDelegateQueue;
@property (nonatomic, strong) dispatch_queue_t socketSendQueue;

@property (nonatomic, assign) long tag;

@property (nonatomic, strong) RequestCompletion block;

@property (nonatomic, copy) NSDictionary *recvData;
@property (nonatomic,copy) NSString* targetIP;

@end

@implementation UDPNATManager
{
    NSUInteger localport;
}

+ (instancetype)sharedManager{
    static UDPNATManager* socketManager;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        socketManager = [[UDPNATManager alloc] init];
    });
    return socketManager;
}

- (instancetype)init{
    self = [super init];
    if (self) {
        _socketDelegateQueue = dispatch_queue_create("UDPNatQueue", DISPATCH_QUEUE_SERIAL);
        _socketSendQueue = dispatch_queue_create("UDPNatSendQueue", DISPATCH_QUEUE_SERIAL);
        
        [self setupSocket];
        _tag = 0;
    }
    return self;
}

//test
- (void)sendTestData:(NSData *)data withIP:(NSString *)ip withPort:(uint16_t)port {
    [self.udpSocket sendData:data toHost:ip port:port withTimeout:-1 tag:self.tag];
}

- (void)setupSocket {
    self.udpSocket = [[GCDAsyncUdpSocket alloc] initWithDelegate:self delegateQueue:self.socketDelegateQueue];
    
    NSError *error = nil;
    if (![[NSUserDefaults standardUserDefaults] integerForKey:@"LocalPortStr"]) {
        localport = (arc4random() % 20000) + 12345;
        [[NSUserDefaults standardUserDefaults] setInteger:localport forKey:@"LocalPortStr"];
    }
    NSLog(@"222=========%ld",(long)[[NSUserDefaults standardUserDefaults] integerForKey:@"LocalPortStr"]);
    if (![self.udpSocket bindToPort:[[NSUserDefaults standardUserDefaults] integerForKey:@"LocalPortStr"] error:&error]) {
        NSLog(@"Error binding: %@", error);
        return;
    }
    if (![self.udpSocket beginReceiving:&error]) {
        NSLog(@"Error receiving: %@", error);
        return;
    }
}
/*
 发送数据至 udp服务器--->获取UDP 服务器返回的IP+PORT
 */
- (NSUInteger)sendDataReturnBlock:(RequestCompletion)block {
    NSDictionary *dict = @{
                           @"message":@{
                                   @"type": @"chat",
                                   @"id": @"123",  //@"id": [YGTimeUtils messageID],
                                   @"subtype":@"request",
                                   }
                           };
    NSData *requestData = [NSJSONSerialization dataWithJSONObject:dict options:NSJSONWritingPrettyPrinted error:nil];
    NSMutableData *sendData = [[NSMutableData alloc] initWithData:[self getContent]];
    [sendData appendData:requestData];
    self.block = block;
    [self timeoutSendData:sendData withTime:1];
    
    return localport;
}
- (void)sendData:(NSData*)data {
    
    uint16_t port = 58089; //IM_UDP_PORT;
    
    NSString *IMhost = @"192.168.0.1";//IM_OUTSIDENET_IP;
    
    dispatch_async(self.socketSendQueue, ^{
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self.udpSocket sendData:data toHost:IMhost port:port withTimeout:-1 tag:self.tag];
        });
    });
    
    self.tag++;
}

- (NSData *)getContent {
    NSData *returnData = [[NSData alloc] init];
    //时间戳
    NSString *timeString = @"345";//[YGTimeUtils messageIDForSecond];
    //签名
    NSString *keyString = nil;
//    if ([YGUtilities jugdeCurrentEvironment]==1) {
//        keyString = IM_OutsideNetTestToken;
//    }else if ([YGUtilities jugdeCurrentEvironment]==2) {
//        keyString = IM_OfficialToken;
//    }else {
//        return returnData;
//    }
    keyString = @"678";
    //版本号
    NSString *versionStr = [[[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleShortVersionString"] stringByReplacingOccurrencesOfString:@"." withString:@""];
    while (versionStr.length < 4) {
        versionStr = [NSString stringWithFormat:@"0%@",versionStr];
    }
    //合并
    NSString *MD5Str = [NSString stringWithFormat:@"%@%@",timeString,keyString];
    //服务器标识
    NSString *server = @"";
    if ([server length] != 8) {
        server = @"000.0000";
    }
    MD5Str = [NSString stringWithFormat:@"%@%@",MD5Str,server];
    NSString *requestString = [NSString stringWithFormat:@"%@,%@,%@",timeString,versionStr,MD5Str];
    returnData = [requestString dataUsingEncoding:NSUTF8StringEncoding];
    
    return returnData;
}
/*
 发送 至 指定地址端口的 数据(用于UDP 打洞)
 */
- (BOOL)sendDataWithTargetIP:(NSString *)targetIP targetPort:(NSString *)targetPort content:(NSString *)content {
    _isUdpNatTranting = NO;
    __block int count = 0;
    //开始打洞--->开启线程 不断发送消息
    while (!_isUdpNatTranting) {
        //发送数据包
        self.targetIP = targetIP;
        [self sendDataWith:targetIP targetPort:targetPort content:content callBack:^(NSDictionary *response, NSError *error) {
            //接收数据包
            if (error) {
                NSLog(@"获取数据失败!");
            }
            NSLog(@"获取的数据response===============%@",response);
            if (response != nil && [response[@"address"] isEqualToString:targetIP]) {
                if (count >= 5) {
                    self->_isUdpNatTranting = YES;
//                    YGMRLProxy *proxy = [[YGMRLProxy sharedManager]initWithMRL:@"rtp://1.1.1.180:23850" updSocket:self.udpSocket];
                }
                count++;
            }
        }];
    }
    return _isUdpNatTranting;
}
//打洞数据发送
- (void)sendDataWith:(NSString *)targetIP targetPort:(NSString *)targetPort content:(NSString *)content callBack:(RequestCompletion)callBack {
    
    dispatch_async(self.socketSendQueue, ^{
        NSData *contentData = [content dataUsingEncoding:NSUTF8StringEncoding];
        NSLog(@"%@发送消息 111111:  ip===%@   port===%@    content===%@",[NSThread currentThread],targetIP,targetPort,content);
        //发送数据包
        [self.udpSocket sendData:contentData toHost:targetIP port:targetPort.integerValue withTimeout:2000 tag:self.tag];
        NSLog(@"%@发送消息 222222:  ip===%@   port===%@    content===%@",[NSThread currentThread],targetIP,targetPort,content);
    });
    self.block = callBack;
    self.tag++;
}

- (void)timeoutSendData:(NSData *)data withTime:(NSInteger)time  {
    [self sendData:data];
    //超时
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (self.block) {
            if (time >= 3) {
                self.block(nil, [NSError errorWithDomain:@"失败" code:101 userInfo:nil]);
                self.block = nil;
            } else {
                [self timeoutSendData:data withTime:time+1];
            }
        }
    });
}

#pragma mark - GCDAsyncUdpSocketDelegate

- (void)udpSocket:(GCDAsyncUdpSocket *)sock didConnectToAddress:(NSData *)address {
    NSLog(@"\n\n didConnectToAddress \n\n");
}

- (void)udpSocket:(GCDAsyncUdpSocket *)sock didNotConnect:(NSError *)error {
    NSLog(@"\n\n didNotConnect \n\n");
    if (self.block) {
        self.block(nil, error);
        self.block = nil;
    }
}

- (void)udpSocket:(GCDAsyncUdpSocket *)sock didSendDataWithTag:(long)tag {
    NSLog(@"\n\n didSendDataWithTag \n\n");
    [sock beginReceiving:nil];
}

- (void)udpSocket:(GCDAsyncUdpSocket *)sock didNotSendDataWithTag:(long)tag dueToError:(NSError *)error {
    NSLog(@"\n\n didNotSendDataWithTag \n\n");
    if (self.block) {
        self.block(nil, error);
        self.block = nil;
    }
}

- (void)udpSocket:(GCDAsyncUdpSocket *)sock didReceiveData:(NSData *)data fromAddress:(NSData *)address withFilterContext:(id)filterContext {
    if (_isUdpNatTranting) {
        NSLog(@"=9898989898====%@====",data);
        
        return;
    }
    NSLog(@"\n\n didReceiveData \n\n");
    NSLog(@"fromAddress==%@",[GCDAsyncUdpSocket hostFromAddress:address]);
    NSString *result  =[[ NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if ([result isEqualToString:@"000"]) {
        NSString *strAddress = [GCDAsyncUdpSocket hostFromAddress:address];
        NSDictionary *dict = @{@"content":result,@"address":strAddress};
        if (self.block) {
            self.block(dict, nil);
            self.block = nil;
        }
    } else {
        NSError *err;
        NSDictionary *jsonDic = [NSJSONSerialization JSONObjectWithData:data
                                                                options:NSJSONReadingMutableContainers
                                                                  error:&err];
        if(err) {
            NSLog(@"json解析失败：%@",err);
            return;
        }
        
        if (jsonDic && [jsonDic isKindOfClass:[NSDictionary class]]) {
            NSLog(@"socket收到数据:\n%@",result);
            if (self.block) {
                self.block(jsonDic[@"message"], nil);
                self.block = nil;
            }
        } else {
            if (self.block) {
                self.block(nil, [NSError errorWithDomain:@"失败" code:101 userInfo:nil]);
                self.block = nil;
            }
        }
    }
}

- (void)udpSocketDidClose:(GCDAsyncUdpSocket *)sock withError:(NSError *)error {
    NSLog(@"\n\n udpSocketDidClose \n\n");
    if (self.block) {
        self.block(nil, error);
        self.block = nil;
    }
}





- (void)startUDPNAT
{
    //接收方打洞     用dstport，和 dstip开始打洞======== 网关  getawayip
//    YGMessageChatNatType netType = [self judgeTheNat];
//    ipTestString = _address;
//    if (netType == YGMessageChatNatType_Intranet) {//非内网
//        NSString *dsport = [NSString stringWithFormat:@"%ld",_dstPort];
//        [YGUtilities showTextHUD:@"非内网开始打洞" andView:self.view maintainTime:HUD_DURATION_TIME];
//        dispatch_async(dispatch_get_global_queue(0, 0), ^{
//            BOOL flag = [[YGUDPNatManager sharedManager] sendDataWithTargetIP:_dstIp targetPort:dsport content:@"000"];
//            if (flag) {
//                dispatch_async(dispatch_get_main_queue(), ^{
//                    [YGUtilities showTextHUD:@"打洞成功!" andView:weakSelf.view maintainTime:5.0];
//                });
//            }
//        });
//    } else if(netType == YGMessageChatNatType_NotSameNat) {//不同Nat  模拟打洞用_dstLocalPort address
//        NSString *dsport = [NSString stringWithFormat:@"%ld",_dstLocalPort];//对方的端口
//        //NSString *localPort = [NSString stringWithFormat:@"%ld",_srcPort];// 本地的端口
//        [YGUtilities showTextHUD:@"不同NAT开始打洞" andView:self.view maintainTime:HUD_DURATION_TIME];
//        dispatch_async(dispatch_get_global_queue(0, 0), ^{
//            //
//            BOOL flag = [[YGUDPNatManager sharedManager] sendDataWithTargetIP:_address targetPort:dsport content:@"000"];
//            if (flag) {
//                dispatch_async(dispatch_get_main_queue(), ^{
//                    [YGUtilities showTextHUD:@"打洞成功!" andView:weakSelf.view maintainTime:5.0];
//                    
//                });
//            }
//        });
//        dispatch_async(dispatch_get_global_queue(0, 0), ^{
//            //
//            BOOL flag = [[YGUDPNatManager sharedManager] sendDataWithTargetIP:_address targetPort:dsport content:@"000"];
//            if (flag) {
//                dispatch_async(dispatch_get_main_queue(), ^{
//                    [YGUtilities showTextHUD:@"打洞成功!" andView:weakSelf.view maintainTime:5.0];
//                    
//                });
//            }
//        });
//        
//    } else {//内网
//        NSString *dsport = [NSString stringWithFormat:@"%ld",_dstPort];
//        [YGUtilities showTextHUD:@"非内网开始打洞" andView:self.view maintainTime:HUD_DURATION_TIME];
//        dispatch_async(dispatch_get_global_queue(0, 0), ^{
//            BOOL flag = [[YGUDPNatManager sharedManager] sendDataWithTargetIP:_dstIp targetPort:dsport content:@"000"];
//            if (flag) {
//                dispatch_async(dispatch_get_main_queue(), ^{
//                    [YGUtilities showTextHUD:@"打洞成功!" andView:weakSelf.view maintainTime:5.0];
//                });
//            }
//        });
//    }
}

@end
