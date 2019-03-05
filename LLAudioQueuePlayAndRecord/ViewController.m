//
//  ViewController.m
//  LLAudioQueuePlayAndRecord
//
//  Created by linling on 2019/2/20.
//  Copyright © 2019 llmodule. All rights reserved.
//

#import "ViewController.h"
#import "AudioQueuePlay.h"

#import "AudioQueueSocketRecord.h"
#import "AudioQueueSocketPlay.h"
#import "UDPNATManager.h"

#import "GCDAsyncUdpSocket.h"
#import "GCDAsyncSocket.h"

//首先导入头文件信息
#include <ifaddrs.h>
#include <arpa/inet.h>
#include <net/if.h>

#define IOS_CELLULAR    @"pdp_ip0"
#define IOS_WIFI        @"en0"
//#define IOS_VPN       @"utun0"
#define IP_ADDR_IPv4    @"ipv4"
#define IP_ADDR_IPv6    @"ipv6"

#define kTCPDefaultPort  58088
#define kUDPDefaultPort  9000

@interface ViewController () <GCDAsyncSocketDelegate,GCDAsyncUdpSocketDelegate>
{
    BOOL isStartSend;
}

@property (nonatomic, strong) AudioQueuePlay *audioPlayer;

@property (strong, nonatomic) GCDAsyncSocket             *tcpSocket;
@property (strong, nonatomic) GCDAsyncSocket             *acceptSocket;
@property (strong, nonatomic) GCDAsyncSocket             *targetSocket;
@property (strong, nonatomic) GCDAsyncUdpSocket             *udpSocket;

@property (weak, nonatomic) IBOutlet UILabel *tipLabel;
@property (weak, nonatomic) IBOutlet UITextField *ipTF;
@property (weak, nonatomic) IBOutlet UITextField *msgTF;
@property (weak, nonatomic) IBOutlet UITextView *logTV;

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
    NSString *ip = [self getIPAddress:YES];
    self.ipTF.text = ip;
    
    [AudioQueueSocketRecord shareInstance].recordWithData = ^(NSData *audioData) {
        if (self->isStartSend) {
            if (self.targetSocket)
            {
                [self.targetSocket writeData:[audioData copy] withTimeout:-1 tag:0];
            }
            else
            {
                [self writeLog:@"socekt连接错误"];
            }
        }
        
    };
    
    NSData *data = [@"22" dataUsingEncoding:NSUTF8StringEncoding];
    [self.udpSocket sendData:data toHost:@"127.0.0.1" port:kUDPDefaultPort withTimeout:-1 tag:0];
}

- (GCDAsyncSocket *)tcpSocket
{
    if (_tcpSocket == nil)
    {
        _tcpSocket = [[GCDAsyncSocket alloc] initWithDelegate:self delegateQueue:dispatch_get_main_queue()];
    }
    return _tcpSocket;
}

- (GCDAsyncSocket *)targetSocket
{
    if (_tcpSocket && [_tcpSocket isConnected]) {
        return _tcpSocket;
    }
    if (_acceptSocket && [_acceptSocket isConnected]) {
        return _acceptSocket;
    }
    return nil;
}

- (GCDAsyncUdpSocket *)udpSocket
{
    if (_udpSocket == nil)
    {
        //socket
        _udpSocket = [[GCDAsyncUdpSocket alloc] initWithDelegate:self delegateQueue:dispatch_get_main_queue()];
//        //绑定端口
//        [_udpSocket bindToPort:kDefaultPort error:nil];
//        //让udpSocket 开始接收数据
//        [_udpSocket beginReceiving:nil];
    }
    return _udpSocket;
}

//获取设备当前网络IP地址
- (NSString *)getIPAddress:(BOOL)preferIPv4
{
    NSArray *searchArray = preferIPv4 ?
    @[ /*IOS_VPN @"/" IP_ADDR_IPv4, IOS_VPN @"/" IP_ADDR_IPv6,*/ IOS_WIFI @"/" IP_ADDR_IPv4, IOS_WIFI @"/" IP_ADDR_IPv6, IOS_CELLULAR @"/" IP_ADDR_IPv4, IOS_CELLULAR @"/" IP_ADDR_IPv6 ] :
    @[ /*IOS_VPN @"/" IP_ADDR_IPv6, IOS_VPN @"/" IP_ADDR_IPv4,*/ IOS_WIFI @"/" IP_ADDR_IPv6, IOS_WIFI @"/" IP_ADDR_IPv4, IOS_CELLULAR @"/" IP_ADDR_IPv6, IOS_CELLULAR @"/" IP_ADDR_IPv4 ] ;
    
    NSDictionary *addresses = [self getIPAddresses];
    NSLog(@"addresses: %@", addresses);
    
    __block NSString *address;
    [searchArray enumerateObjectsUsingBlock:^(NSString *key, NSUInteger idx, BOOL *stop)
     {
         address = addresses[key];
         if(address) *stop = YES;
     } ];
    return address ? address : @"0.0.0.0";
}
//获取所有相关IP信息
- (NSDictionary *)getIPAddresses
{
    NSMutableDictionary *addresses = [NSMutableDictionary dictionaryWithCapacity:8];
    
    // retrieve the current interfaces - returns 0 on success
    struct ifaddrs *interfaces;
    if(!getifaddrs(&interfaces)) {
        // Loop through linked list of interfaces
        struct ifaddrs *interface;
        for(interface=interfaces; interface; interface=interface->ifa_next) {
            if(!(interface->ifa_flags & IFF_UP) /* || (interface->ifa_flags & IFF_LOOPBACK) */ ) {
                continue; // deeply nested code harder to read
            }
            const struct sockaddr_in *addr = (const struct sockaddr_in*)interface->ifa_addr;
            char addrBuf[ MAX(INET_ADDRSTRLEN, INET6_ADDRSTRLEN) ];
            if(addr && (addr->sin_family==AF_INET || addr->sin_family==AF_INET6)) {
                NSString *name = [NSString stringWithUTF8String:interface->ifa_name];
                NSString *type;
                if(addr->sin_family == AF_INET) {
                    if(inet_ntop(AF_INET, &addr->sin_addr, addrBuf, INET_ADDRSTRLEN)) {
                        type = IP_ADDR_IPv4;
                    }
                } else {
                    const struct sockaddr_in6 *addr6 = (const struct sockaddr_in6*)interface->ifa_addr;
                    if(inet_ntop(AF_INET6, &addr6->sin6_addr, addrBuf, INET6_ADDRSTRLEN)) {
                        type = IP_ADDR_IPv6;
                    }
                }
                if(type) {
                    NSString *key = [NSString stringWithFormat:@"%@/%@", name, type];
                    addresses[key] = [NSString stringWithUTF8String:addrBuf];
                }
            }
        }
        // Free memory
        freeifaddrs(interfaces);
    }
    return [addresses count] ? addresses : nil;
}

- (void)writeLog:(NSString *)log
{
    NSString *text = [NSString stringWithFormat:@"%@",self.logTV.text];
    text = [NSString stringWithFormat:@"%@%@:%@\n",text,NSDate.date,log];
    self.logTV.text = text;
}

//监听最新的消息
- (void)pullTheMsg
{
    //监听读数据的代理  -1永远监听，不超时，但是只收一次消息，
    //所以每次接受到消息还得调用一次
    if (self.targetSocket) {
        [self.targetSocket readDataWithTimeout:-1 tag:0];
    } else {
        [self writeLog:@"socekt连接错误"];
    }
    
}

- (IBAction)doPlay:(id)sender
{
    if (self.audioPlayer == nil) {
        NSString *filePath = [[NSBundle mainBundle] pathForResource:@"G.E.M.邓紫棋 - 喜欢你.mp3" ofType:nil];
        self.audioPlayer = [[AudioQueuePlay alloc] initWithFile:filePath];
    }
    [self.audioPlayer startPlay];
}
- (IBAction)doPause:(id)sender
{
    [self.audioPlayer pause];
}
- (IBAction)doStop:(id)sender
{
    [self.audioPlayer stop];
    self.audioPlayer = nil;
}

- (IBAction)startRecord:(id)sender
{
    if (isStartSend == NO) {
        
        [[AudioQueueSocketRecord shareInstance] startRecordQueue:YES];
        [[AudioQueueSocketPlay shareInstance] starPlayQueue:YES];
        
        
        if (self.targetSocket) {
            self.tipLabel.text = @"TCP-开始录音和播放录音";
        }else{
            self.tipLabel.text = @"socekt连接错误";
            [self writeLog:@"socekt连接错误"];
        }
        isStartSend = YES;
        
    }
}

- (IBAction)stopRecord:(id)sender
{
    if (isStartSend) {
        isStartSend = NO;
        
        [[AudioQueueSocketRecord shareInstance] startRecordQueue:NO];
        [[AudioQueueSocketPlay shareInstance] starPlayQueue:NO];
        
        self.tipLabel.text = @"停止录音";
        
        if (self.targetSocket) {
            [self.targetSocket disconnect];
        }
        
    }
    
}


- (IBAction)startConnect:(id)sender {
    NSError *error;
    [_tcpSocket disconnect];
    [self.tcpSocket connectToHost:_ipTF.text onPort:kTCPDefaultPort error:&error];
    if (error) {
        NSLog(@"%@",[error description]);
    }
    
}
- (IBAction)startListening:(id)sender {
    NSError *error;
    
    [self.tcpSocket acceptOnPort:kTCPDefaultPort error:&error];
    if (error) {
        NSLog(@"%@",[error description]);
        [self writeLog:[error description]];
    }
    else
    {
        [self writeLog:@"开始监听"];
//        self.tipLabel.text = [NSString stringWithFormat:@"开始监听"];
    }
}
- (IBAction)sendMsg:(id)sender {
    NSString *str = [NSString stringWithFormat:@"send:%@",self.msgTF.text];
    NSData *msg = [self.msgTF.text dataUsingEncoding:NSUTF8StringEncoding];
    [self writeLog:str];
//    if ([self.tcpSocket isConnected]) {
//        [self.tcpSocket writeData:msg withTimeout:-1 tag:0];
//        [self writeLog:@"tcpSocket send"];
//    }
//    else if ([self.acceptSocket isConnected]) {
//        [self.acceptSocket writeData:msg withTimeout:-1 tag:0];
//        [self writeLog:@"acceptSocket send"];
//    }
    if (self.targetSocket) {
        [self.targetSocket writeData:msg withTimeout:-1 tag:0];
    } else {
        [self writeLog:@"socekt连接错误"];
    }
    self.msgTF.text = @"";
}

- (IBAction)udpNAT:(id)sender
{
//    NSString *ip = @"10.128.70.70"; //self.ipTF.text
//    BOOL flag = [[UDPNATManager sharedManager] sendDataWithTargetIP:ip targetPort:@"58088" content:@"000"];
//    if (flag) {
//        [self writeLog:@"打洞成功"];
//    }
}

#pragma mark - GCDAsyncSocketDelegate

- (void)socket:(GCDAsyncSocket *)sock didAcceptNewSocket:(GCDAsyncSocket *)newSocket
{
    [self writeLog:@"接收到一个Socket连接"];
//    self.tipLabel.text = [NSString stringWithFormat:@"接收到一个Socket连接"];
    
    _acceptSocket = newSocket;
    [self pullTheMsg];
}

/**
 * Called when a socket connects and is ready for reading and writing.
 * The host parameter will be an IP address, not a DNS name.
 **/
- (void)socket:(GCDAsyncSocket *)sock didConnectToHost:(NSString *)host port:(uint16_t)port
{
    [self writeLog:[NSString stringWithFormat:@"%@:%d连接成功",host,port]];
//    self.tipLabel.text = [NSString stringWithFormat:@"%@:%d连接成功",host,port];
    [self pullTheMsg];
}

/**
 * Called when a socket connects and is ready for reading and writing.
 * The host parameter will be an IP address, not a DNS name.
 **/
- (void)socket:(GCDAsyncSocket *)sock didConnectToUrl:(NSURL *)url
{
    [self writeLog:[NSString stringWithFormat:@"didConnectToUrl : %@",url]];
    NSLog(@"didConnectToUrl : %@",url);
}

/**
 * Called when a socket has completed reading the requested data into memory.
 * Not called if there is an error.
 **/
- (void)socket:(GCDAsyncSocket *)sock didReadData:(NSData *)data withTag:(long)tag
{
    NSString *str = [NSString stringWithFormat:@"recevie:%@",[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]];
    [self writeLog:str];
    NSLog(@"%@: rece data %lu",[[UIDevice currentDevice] name] , [data length]);
    [self pullTheMsg];
    
//    if (isStartSend) {
//
//#ifdef isUserAudioUnit
//        [[FLAudioUnitHelpClass shareInstance] playAudioData:data];
//#else
//        [[FLAudioQueueHelpClass shareInstance] playAudioData:data];
//#endif
//    }
}


- (void)socket:(GCDAsyncSocket *)sock didWriteDataWithTag:(long)tag
{
    //    NSLog(@"发送成功");
    [self writeLog:@"发送成功"];
//    [sock readDataWithTimeout:30 tag:0];
    
}

- (void)socketDidDisconnect:(GCDAsyncSocket *)sock withError:(nullable NSError *)err
{
//    [self stopRecord:nil];
    [self writeLog:[NSString stringWithFormat:@"TCP连接断开"]];
    [self writeLog:[err description]];
//    self.tipLabel.text = [NSString stringWithFormat:@"TCP连接断开"];
    
}

#pragma mark - GCDAsyncUdpSocketDelegate

- (void)udpSocket:(GCDAsyncUdpSocket *)sock didSendDataWithTag:(long)tag
{
    NSLog (@"DidSend");
}

- (void)udpSocket:(GCDAsyncUdpSocket *)sock didReceiveData:(NSData *)data
      fromAddress:(NSData *)address
withFilterContext:(id)filterContext
{
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        if (isStartSend)
        {
            
        }
    });
    NSLog(@"%@: rece data %lu",[[UIDevice currentDevice] name] , [data length]);
    
    
}

@end
