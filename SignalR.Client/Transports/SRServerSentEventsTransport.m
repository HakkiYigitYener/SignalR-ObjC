//
//  SRServerSentEventsTransport.m
//  SignalR
//
//  Created by Alex Billingsley on 1/7/12.
//  Copyright (c) 2011 DyKnow LLC. (http://dyknow.com/)
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated
//  documentation files (the "Software"), to deal in the Software without restriction, including without limitation
//  the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and
//  to permit persons to whom the Software is furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in all copies or substantial portions of
//  the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO
//  THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF
//  CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
//  DEALINGS IN THE SOFTWARE.
//

#import <AFNetworking/AFNetworking.h>
#import "SRServerSentEventsTransport.h"
#import "SRConnectionInterface.h"
#import "SRExceptionHelper.h"
#import "SRConnectionExtensions.h"
#import "SRLog.h"
#import "SRChunkBuffer.h"
#import "SRServerSentEvent.h"
#import "SREventSourceRequestSerializer.h"
#import "SREventSourceResponseSerializer.h"
#import "SRBlockOperation.h"

typedef void (^SRCompletionHandler)(id response, NSError *error);

@interface SRServerSentEventsTransport ()

@property (assign) BOOL stop;
@property (copy) SRCompletionHandler completionHandler;
@property (strong, nonatomic, readwrite) NSBlockOperation *connectTimeoutOperation;
@property (strong, nonatomic, readonly)  SRChunkBuffer *buffer;
@property (strong, nonatomic, readwrite) NSURLSessionDataTask *eventSource;

@end

@implementation SRServerSentEventsTransport

- (instancetype)initWithSessionConfiguration:(nullable NSURLSessionConfiguration *)configuration
{
    self = [super initWithSessionConfiguration:configuration];
    if (!self)
    {
        return nil;
    }
    _reconnectDelay = @2;
    _buffer = [[SRChunkBuffer alloc] init];

    return self;
}

#pragma mark
#pragma mark SRClientTransportInterface

- (NSString *)name
{
    return @"serverSentEvents";
}

- (BOOL)supportsKeepAlive
{
    return YES;
}

- (void)negotiate:(id<SRConnectionInterface>)connection connectionData:(NSString *)connectionData completionHandler:(void (^)(SRNegotiationResponse *response, NSError *error))block
{
    SRLogSSEDebug(@"serverSentEvents will negotiate");
    [super negotiate:connection connectionData:connectionData completionHandler:block];
}

- (void)start:(id<SRConnectionInterface>)connection connectionData:(NSString *)connectionData completionHandler:(void (^)(id response, NSError *error))block
{
    SRLogSSEDebug(@"serverSentEvents will connect with connectionData %@", connectionData);

    self.completionHandler = block;

    __weak __typeof(& *self) weakSelf = self;
    self.connectTimeoutOperation = [SRTransportConnectTimeoutBlockOperation blockOperationWithBlock:^{
        __strong __typeof(&*weakSelf) strongSelf = weakSelf;
        if (strongSelf.completionHandler)
        {
            NSDictionary *userInfo = @{
                NSLocalizedDescriptionKey: NSLocalizedString(@"Connection timed out.", nil),
                NSLocalizedFailureReasonErrorKey: NSLocalizedString(@"Connection did not receive initialized message before the timeout.", nil),
                NSLocalizedRecoverySuggestionErrorKey: NSLocalizedString(@"Retry or switch transports.", nil)
            };
            NSError *timeout = [[NSError alloc] initWithDomain:[NSString stringWithFormat:NSLocalizedString(@"com.SignalR.SignalR-ObjC.%@", @""), NSStringFromClass([self class])] code:NSURLErrorTimedOut userInfo:userInfo];
            SRLogSSEError(@"serverSentEvents failed to receive initialized message before timeout");
            strongSelf.completionHandler(nil, timeout);
            strongSelf.completionHandler = nil;
        }
    }];
    [self.connectTimeoutOperation performSelector:@selector(start) withObject:nil afterDelay:[[connection transportConnectTimeout] integerValue]];

    [self open:connection connectionData:connectionData isReconnecting:NO];
}

- (void)send:(id<SRConnectionInterface>)connection data:(NSString *)data connectionData:(NSString *)connectionData completionHandler:(void (^)(id response, NSError *error))block
{
    SRLogSSEDebug(@"serverSentEvents will send data %@", data);
    [super send:connection data:data connectionData:connectionData completionHandler:block];
}

- (void)abort:(id<SRConnectionInterface>)connection timeout:(NSNumber *)timeout connectionData:(NSString *)connectionData
{
    SRLogSSEDebug(@"serverSentEvents will abort");
    _stop = YES;
    [self.eventSource cancel];
    [super abort:connection timeout:timeout connectionData:connectionData];//we expect this to set stop to YES
}

- (void)lostConnection:(id<SRConnectionInterface>)connection
{
    SRLogSSEWarn(@"serverSentEvents lost connection, cancelling connection");
    [self.eventSource cancel];
}

#pragma mark -
#pragma mark SSE Transport

- (void)open:(id <SRConnectionInterface>)connection connectionData:(NSString *)connectionData isReconnecting:(BOOL)isReconnecting
{
    id parameters = @{
        @"transport" : [self name],
        @"connectionToken" : ([connection connectionToken]) ? [connection connectionToken]:@"",
        @"messageId" : ([connection messageId]) ? [connection messageId]:@"",
        @"groupsToken" : ([connection groupsToken]) ? [connection groupsToken]:@"",
        @"connectionData" : (connectionData) ? connectionData:@"",
    };

    if ([connection queryString])
    {
        NSMutableDictionary *_parameters = [NSMutableDictionary dictionaryWithDictionary:parameters];
        [_parameters addEntriesFromDictionary:[connection queryString]];
        parameters = _parameters;
    }

    //TODO: prepareRequest
    __weak __typeof(& *self) weakSelf = self;
    __weak __typeof(& *connection) weakConnection = connection;
    SRLogSSEDebug(@"serverSentEvents will connect at url: %@%@%@", connection.url, (isReconnecting) ? @"reconnect":@"connect", parameters);
    AFHTTPSessionManager *manager = [[AFHTTPSessionManager alloc] initWithBaseURL:[NSURL URLWithString:connection.url] sessionConfiguration:self.sessionConfiguration];
    [manager setRequestSerializer:[SREventSourceRequestSerializer serializer]];
    [manager setResponseSerializer:[SREventSourceResponseSerializer serializer]];
    //manager = self.securityPolicy;

    self.eventSource = [manager GET:(isReconnecting) ? @"reconnect":@"connect" parameters:parameters success:^(NSURLSessionDataTask *_Nonnull task, id _Nullable responseObject) {
        SRLogSSEWarn(@"serverSentEvents did complete");
        __strong __typeof(&*weakSelf) strongSelf = weakSelf;
        __strong __typeof(&*weakConnection) strongConnection = weakConnection;
        if (strongSelf.stop)
        {
            [strongSelf completeAbort];
        } else if (![strongSelf tryCompleteAbort])
        {
            [strongSelf reconnect:strongConnection data:connectionData];
        }
    } failure:^(NSURLSessionDataTask *_Nullable task, NSError *_Nonnull error) {
        __strong __typeof(&*weakSelf) strongSelf = weakSelf;
        __strong __typeof(&*weakConnection) strongConnection = weakConnection;

        SRLogSSEError(@"serverSentEvents did fail with error %@", error);

        if (strongSelf.completionHandler)
        {
            SRLogSSEDebug(@"serverSentEvents did fail while connecting");
            [NSObject cancelPreviousPerformRequestsWithTarget:strongSelf.connectTimeoutOperation
                                                     selector:@selector(start)
                                                       object:nil];
            strongSelf.connectTimeoutOperation = nil;

            strongSelf.completionHandler(nil, error);
            strongSelf.completionHandler = nil;
        } else  //failure while reconnecting should error
        {   // Check if the request is aborted
            BOOL isRequestAborted = [SRExceptionHelper isRequestAborted:error];

            if (!isRequestAborted)
            {
                // Don't raise exceptions if the request was aborted (connection was stopped).
                [strongConnection didReceiveError:error];
            }

            if (strongSelf.stop)
            {
                [strongSelf completeAbort];
            } else if (![strongSelf tryCompleteAbort])
            {
                [strongSelf reconnect:strongConnection data:connectionData];
            }
        }

    }];


    [manager setDataTaskDidReceiveDataBlock:^(NSURLSession *_Nonnull session, NSURLSessionDataTask *_Nonnull dataTask, NSData *_Nonnull receivedData) {
        __strong __typeof(&*weakSelf) strongSelf = weakSelf;
        __strong __typeof(&*weakConnection) strongConnection = weakConnection;

        [strongSelf.buffer add:receivedData];
        while ([strongSelf.buffer hasChunks])
        {
            NSString *line = [strongSelf.buffer readLine];

            // No new lines in the buffer so stop processing
            if (line == nil)
            {
                break;
            }

            SRServerSentEvent *sseEvent = nil;
            if (![SRServerSentEvent tryParseEvent:line sseEvent:&sseEvent])
            {
                continue;
            }

            if ([sseEvent.event isEqual:@"data"])
            {
                NSString *data = [[NSString alloc] initWithData:sseEvent.data encoding:NSUTF8StringEncoding];
                SRLogSSEInfo(@"serverSentEvents did receive: %@", data);
                if ([data caseInsensitiveCompare:@"initialized"] == NSOrderedSame)
                {
                    // This will noop if we're not in the reconnecting state
                    if ([strongConnection changeState:reconnecting toState:connected])
                    {
                        // Raise the reconnect event if the connection comes back up
                        [strongConnection didReconnect];
                    }

                    continue;
                }

                BOOL shouldReconnect = NO;
                BOOL disconnect = NO;
                [strongSelf processResponse:strongConnection response:data shouldReconnect:&shouldReconnect disconnected:&disconnect];
                if (strongSelf.completionHandler)
                {
                    [NSObject cancelPreviousPerformRequestsWithTarget:strongSelf.connectTimeoutOperation
                                                             selector:@selector(start)
                                                               object:nil];
                    strongSelf.connectTimeoutOperation = nil;

                    strongSelf.completionHandler(nil, nil);
                    strongSelf.completionHandler = nil;
                }

                if (disconnect)
                {
                    SRLogSSEDebug(@"serverSentEvents did receive disconnect command from server");
                    _stop = YES;
                    [strongConnection disconnect];
                }
            }
        }
    }];
}

- (void)reconnect:(id <SRConnectionInterface>)connection data:(NSString *)data
{
    __weak __typeof(& *self) weakSelf = self;
    __weak __typeof(& *connection) weakConnection = connection;
    SRLogSSEDebug(@"will reconnect in %@", self.reconnectDelay);
    [[SRServerSentEventsReconnectBlockOperation blockOperationWithBlock:^{
        __strong __typeof(&*weakSelf) strongSelf = weakSelf;
        __strong __typeof(&*weakConnection) strongConnection = weakConnection;

        if (connection.state != disconnected && [SRConnection ensureReconnecting:strongConnection])
        {
            SRLogSSEWarn(@"reconnecting");
            [strongSelf.eventSource cancel];
            //now that all the current connections are tearing down, we have the queue to ourselves
            [strongSelf open:strongConnection connectionData:data isReconnecting:YES];
        }

    }] performSelector:@selector(start) withObject:nil afterDelay:[self.reconnectDelay integerValue]];
}

@end
