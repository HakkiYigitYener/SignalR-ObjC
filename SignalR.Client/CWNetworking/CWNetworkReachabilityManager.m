// CWNetworkReachabilityManager.m
// Copyright (c) 2011–2015 Alamofire Software Foundation (http://alamofire.org/)
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.

#import "CWNetworkReachabilityManager.h"
#if !TARGET_OS_WATCH

#import <netinet/in.h>
#import <netinet6/in6.h>
#import <arpa/inet.h>
#import <ifaddrs.h>
#import <netdb.h>

NSString * const CWNetworkingReachabilityDidChangeNotification = @"com.alamofire.networking.reachability.change";
NSString * const CWNetworkingReachabilityNotificationStatusItem = @"CWNetworkingReachabilityNotificationStatusItem";

typedef void (^CWNetworkReachabilityStatusBlock)(CWNetworkReachabilityStatus status);

NSString * CWStringFromNetworkReachabilityStatus(CWNetworkReachabilityStatus status) {
    switch (status) {
        case CWNetworkReachabilityStatusNotReachable:
            return NSLocalizedStringFromTable(@"Not Reachable", @"CWNetworking", nil);
        case CWNetworkReachabilityStatusReachableViaWWAN:
            return NSLocalizedStringFromTable(@"Reachable via WWAN", @"CWNetworking", nil);
        case CWNetworkReachabilityStatusReachableViaWiFi:
            return NSLocalizedStringFromTable(@"Reachable via WiFi", @"CWNetworking", nil);
        case CWNetworkReachabilityStatusUnknown:
        default:
            return NSLocalizedStringFromTable(@"Unknown", @"CWNetworking", nil);
    }
}

static CWNetworkReachabilityStatus CWNetworkReachabilityStatusForFlags(SCNetworkReachabilityFlags flags) {
    BOOL isReachable = ((flags & kSCNetworkReachabilityFlagsReachable) != 0);
    BOOL needsConnection = ((flags & kSCNetworkReachabilityFlagsConnectionRequired) != 0);
    BOOL canConnectionAutomatically = (((flags & kSCNetworkReachabilityFlagsConnectionOnDemand ) != 0) || ((flags & kSCNetworkReachabilityFlagsConnectionOnTraffic) != 0));
    BOOL canConnectWithoutUserInteraction = (canConnectionAutomatically && (flags & kSCNetworkReachabilityFlagsInterventionRequired) == 0);
    BOOL isNetworkReachable = (isReachable && (!needsConnection || canConnectWithoutUserInteraction));

    CWNetworkReachabilityStatus status = CWNetworkReachabilityStatusUnknown;
    if (isNetworkReachable == NO) {
        status = CWNetworkReachabilityStatusNotReachable;
    }
#if	TARGET_OS_IPHONE
    else if ((flags & kSCNetworkReachabilityFlagsIsWWAN) != 0) {
        status = CWNetworkReachabilityStatusReachableViaWWAN;
    }
#endif
    else {
        status = CWNetworkReachabilityStatusReachableViaWiFi;
    }

    return status;
}

/**
 * Queue a status change notification for the main thread.
 *
 * This is done to ensure that the notifications are received in the same order
 * as they are sent. If notifications are sent directly, it is possible that
 * a queued notification (for an earlier status condition) is processed CWter
 * the later update, resulting in the listener being left in the wrong state.
 */
static void CWPostReachabilityStatusChange(SCNetworkReachabilityFlags flags, CWNetworkReachabilityStatusBlock block) {
    CWNetworkReachabilityStatus status = CWNetworkReachabilityStatusForFlags(flags);
    dispatch_async(dispatch_get_main_queue(), ^{
        if (block) {
            block(status);
        }
        NSNotificationCenter *notificationCenter = [NSNotificationCenter defaultCenter];
        NSDictionary *userInfo = @{ CWNetworkingReachabilityNotificationStatusItem: @(status) };
        [notificationCenter postNotificationName:CWNetworkingReachabilityDidChangeNotification object:nil userInfo:userInfo];
    });
}

static void CWNetworkReachabilityCallback(SCNetworkReachabilityRef __unused target, SCNetworkReachabilityFlags flags, void *info) {
    CWPostReachabilityStatusChange(flags, (__bridge CWNetworkReachabilityStatusBlock)info);
}

static const void * CWNetworkReachabilityRetainCallback(const void *info) {
    return Block_copy(info);
}

static void CWNetworkReachabilityReleaseCallback(const void *info) {
    if (info) {
        Block_release(info);
    }
}

@interface CWNetworkReachabilityManager ()
@property (readwrite, nonatomic, strong) id networkReachability;
@property (readwrite, nonatomic, assign) CWNetworkReachabilityStatus networkReachabilityStatus;
@property (readwrite, nonatomic, copy) CWNetworkReachabilityStatusBlock networkReachabilityStatusBlock;
@end

@implementation CWNetworkReachabilityManager

+ (instancetype)sharedManager {
    static CWNetworkReachabilityManager *_sharedManager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        struct sockaddr_in address;
        bzero(&address, sizeof(address));
        address.sin_len = sizeof(address);
        address.sin_family = AF_INET;

        _sharedManager = [self managerForAddress:&address];
    });

    return _sharedManager;
}

#ifndef __clang_analyzer__
+ (instancetype)managerForDomain:(NSString *)domain {
    SCNetworkReachabilityRef reachability = SCNetworkReachabilityCreateWithName(kCFAllocatorDefault, [domain UTF8String]);

    CWNetworkReachabilityManager *manager = [[self alloc] initWithReachability:reachability];

    return manager;
}
#endif

#ifndef __clang_analyzer__
+ (instancetype)managerForAddress:(const void *)address {
    SCNetworkReachabilityRef reachability = SCNetworkReachabilityCreateWithAddress(kCFAllocatorDefault, (const struct sockaddr *)address);
    CWNetworkReachabilityManager *manager = [[self alloc] initWithReachability:reachability];

    return manager;
}
#endif

- (instancetype)initWithReachability:(SCNetworkReachabilityRef)reachability {
    self = [super init];
    if (!self) {
        return nil;
    }

    self.networkReachability = CFBridgingRelease(reachability);
    self.networkReachabilityStatus = CWNetworkReachabilityStatusUnknown;

    return self;
}

- (instancetype)init NS_UNAVAILABLE
{
    return nil;
}

- (void)dealloc {
    [self stopMonitoring];
}

#pragma mark -

- (BOOL)isReachable {
    return [self isReachableViaWWAN] || [self isReachableViaWiFi];
}

- (BOOL)isReachableViaWWAN {
    return self.networkReachabilityStatus == CWNetworkReachabilityStatusReachableViaWWAN;
}

- (BOOL)isReachableViaWiFi {
    return self.networkReachabilityStatus == CWNetworkReachabilityStatusReachableViaWiFi;
}

#pragma mark -

- (void)startMonitoring {
    [self stopMonitoring];

    if (!self.networkReachability) {
        return;
    }

    __weak __typeof(self)weakSelf = self;
    CWNetworkReachabilityStatusBlock callback = ^(CWNetworkReachabilityStatus status) {
        __strong __typeof(weakSelf)strongSelf = weakSelf;

        strongSelf.networkReachabilityStatus = status;
        if (strongSelf.networkReachabilityStatusBlock) {
            strongSelf.networkReachabilityStatusBlock(status);
        }

    };

    id networkReachability = self.networkReachability;
    SCNetworkReachabilityContext context = {0, (__bridge void *)callback, CWNetworkReachabilityRetainCallback, CWNetworkReachabilityReleaseCallback, NULL};
    SCNetworkReachabilitySetCallback((__bridge SCNetworkReachabilityRef)networkReachability, CWNetworkReachabilityCallback, &context);
    SCNetworkReachabilityScheduleWithRunLoop((__bridge SCNetworkReachabilityRef)networkReachability, CFRunLoopGetMain(), kCFRunLoopCommonModes);

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0),^{
        SCNetworkReachabilityFlags flags;
        if (SCNetworkReachabilityGetFlags((__bridge SCNetworkReachabilityRef)networkReachability, &flags)) {
            CWPostReachabilityStatusChange(flags, callback);
        }
    });
}

- (void)stopMonitoring {
    if (!self.networkReachability) {
        return;
    }

    SCNetworkReachabilityUnscheduleFromRunLoop((__bridge SCNetworkReachabilityRef)self.networkReachability, CFRunLoopGetMain(), kCFRunLoopCommonModes);
}

#pragma mark -

- (NSString *)localizedNetworkReachabilityStatusString {
    return CWStringFromNetworkReachabilityStatus(self.networkReachabilityStatus);
}

#pragma mark -

- (void)setReachabilityStatusChangeBlock:(void (^)(CWNetworkReachabilityStatus status))block {
    self.networkReachabilityStatusBlock = block;
}

#pragma mark - NSKeyValueObserving

+ (NSSet *)keyPathsForValuesCWfectingValueForKey:(NSString *)key {
    if ([key isEqualToString:@"reachable"] || [key isEqualToString:@"reachableViaWWAN"] || [key isEqualToString:@"reachableViaWiFi"]) {
        return [NSSet setWithObject:@"networkReachabilityStatus"];
    }

    return [super keyPathsForValuesAffectingValueForKey:key];
}

@end
#endif
