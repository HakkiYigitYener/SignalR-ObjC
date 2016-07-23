//
//  SRServerSentEventsTransportTests.m
//  SignalR.Client.ObjC
//
//  Created by Joel Dart on 8/2/15.
//  Copyright (c) 2015 DyKnow LLC. All rights reserved.
//

#import <XCTest/XCTest.h>
#import "SRConnection.h"
#import "SRServerSentEventsTransport.h"
#import "SRMockClientTransport+SSE.h"
#import "SRMockWaitBlockOperation.h"
#import "SRBlockOperation.h"
#import "SRMockSSEResponder.h"

@interface SRConnection (UnitTest)
@property (strong, nonatomic, readwrite) NSNumber * disconnectTimeout;
@end

@interface SRServerSentEventsTransportTests : XCTestCase

@end

@implementation SRServerSentEventsTransportTests

- (void)setUp {
    [super setUp];
    [UMKMockURLProtocol enable];
    [UMKMockURLProtocol reset];
}

- (void)tearDown {
    [UMKMockURLProtocol disable];
    [super tearDown];
}

- (void)testStart_Stop_StartTriggersTheCorrectCallbacks {
    __block BOOL firstClosedCalled = NO;

    SRConnection* connection = [[SRConnection alloc] initWithURLString:@"http://localhost:0000"];
    SRServerSentEventsTransport* sse1 = [SRMockClientTransport sse];
    [SRMockClientTransport negotiateForTransport:sse1];
    [[SRMockClientTransport connectTransport:sse1 statusCode:@0 json:@{}] afterStart:^{
        [connection stop];
    }];
    [SRMockClientTransport abortForTransport:sse1 statusCode:@200 json:@{}];
    
    XCTestExpectation *started = [self expectationWithDescription:@"started"];
    connection.started = ^{
        [started fulfill];
        XCTAssertTrue(firstClosedCalled, @"only get started after the error fails first");
    };
    
    //TODO: closed should really only be called once
    //XCTestExpectation *closed = [self expectationWithDescription:@"closed"];
    __weak __typeof(&*connection)weakConnection = connection;
    connection.closed = ^{
        __strong __typeof(&*weakConnection)strongConnection = weakConnection;
        //[closed fulfill];
        if (!firstClosedCalled) {
            [UMKMockURLProtocol reset];
            SRServerSentEventsTransport* sse2 = [SRMockClientTransport sse];
            [SRMockClientTransport negotiateForTransport:sse2];
            [SRMockClientTransport connectTransport:sse2 statusCode:@0 json:@{}];
            [strongConnection start:sse2];
        }
        firstClosedCalled = YES;
    };
    
    [connection start:sse1];
    [self waitForExpectationsWithTimeout:5.0 handler:nil];
}

- (void)testConnectionCanBeStoppedDuringTransportStart {
    SRConnection* connection = [[SRConnection alloc] initWithURLString:@"http://localhost:0000"];
    SRServerSentEventsTransport* sse = [SRMockClientTransport sse];
    [SRMockClientTransport negotiateForTransport:sse];
    [[SRMockClientTransport connectTransport:sse statusCode:@0 json:@{}] beforeData:^(NSData * _Nonnull data) {
        NSString *eventStream = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        if ([eventStream rangeOfString:@"initialized" options:NSCaseInsensitiveSearch].location != NSNotFound) {
            [connection stop];
        }
    }];
    
    XCTestExpectation *closed = [self expectationWithDescription:@"closed"];
    connection.closed = ^{
        [closed fulfill];
    };
    
    XCTestExpectation *errored = [self expectationWithDescription:@"errored"];
    connection.error = ^(NSError* err){
        [errored fulfill];
    };
    
    connection.started = ^(){
        XCTAssert(NO, @"start was triggered");
    };
    
    [connection start:sse];
    [self waitForExpectationsWithTimeout:5.0 handler:nil];
}

- (void)testTransportCanSendAndReceiveMessagesOnConnect {
    SRConnection* connection = [[SRConnection alloc] initWithURLString:@"http://localhost:0000"];
    SRServerSentEventsTransport* sse = [SRMockClientTransport sse];
    [SRMockClientTransport negotiateForTransport:sse];
    
    SRMockSSEResponder *responder = [[SRMockSSEResponder alloc] initWithStatusCode:0 eventStream:@[
        [@"data: initialized\n\n" dataUsingEncoding:NSUTF8StringEncoding],
        [@"data: {\"M\":[{\"H\":\"hubname\", \"M\":\"message1\", \"A\": \"12345\"}]}\n\n" dataUsingEncoding:NSUTF8StringEncoding],
        [@"data: {\"M\":[{\"H\":\"hubname\", \"M\":\"message2\", \"A\": \"12345\"}]}\n\n" dataUsingEncoding:NSUTF8StringEncoding]
    ]];
    [SRMockClientTransport connectTransport:sse responder:responder];
    [SRMockClientTransport sendForTransport:sse statusCode:@200 json:@{}];
    
    __weak __typeof(&*connection)weakConnection = connection;
    XCTestExpectation *started = [self expectationWithDescription:@"started"];
    connection.started = ^(){
        __strong __typeof(&*weakConnection)strongConnection = weakConnection;
        [strongConnection send:@"test" completionHandler:^(id response, NSError *error) {
            //after sending receive two more
            [responder eventStream:@[
                [@"data: {\"M\":[{\"H\":\"hubname\", \"M\":\"message3\", \"A\": \"12345\"}]}\n\n" dataUsingEncoding:NSUTF8StringEncoding],
                [@"data: {\"M\":[{\"H\":\"hubname\", \"M\":\"message4\", \"A\": \"12345\"}]}\n\n" dataUsingEncoding:NSUTF8StringEncoding]
            ]];
        }];
        [started fulfill];
    };
    
    XCTestExpectation *received = [self expectationWithDescription:@"received"];
    __block NSMutableArray* values = [[NSMutableArray alloc] init];
    connection.received = ^(id data) {
        [values addObject: data];
        if ([values count] == 5) {
            XCTAssertEqualObjects([[values objectAtIndex:0] valueForKey:@"M"], @"message1", @"did not receive message1");
            XCTAssertEqualObjects([[values objectAtIndex:1] valueForKey:@"M"], @"message2", @"did not receive message2");
            XCTAssertEqualObjects([[values objectAtIndex:3] valueForKey:@"M"], @"message3", @"did not receive message3");
            XCTAssertEqualObjects([[values objectAtIndex:4] valueForKey:@"M"], @"message4", @"did not receive message4");
            [received fulfill];
        }
    };
    
    [connection start:sse];
    [self waitForExpectationsWithTimeout:5.0 handler:nil];
}

@end

@implementation SRServerSentEventsTransportTests (MessageParsing)

- (void)testIgnoresInitializedAndEmptyLinesWhenParsingMessages {
    SRConnection* connection = [[SRConnection alloc] initWithURLString:@"http://localhost:0000"];
    SRServerSentEventsTransport* sse = [SRMockClientTransport sse];
    [SRMockClientTransport negotiateForTransport:sse];
    [SRMockClientTransport connectTransport:sse statusCode:@0 json:@{
        @"M":@[ @{
            @"H":@"hubname",
            @"M":@"message",
            @"A":@"12345"
        } ]
    }];
    
    XCTestExpectation *received = [self expectationWithDescription:@"received"];
    connection.received = ^(NSDictionary * data){
        if ([[data valueForKey:@"M"] isEqualToString:@"message"]
            && [[data valueForKey:@"H"] isEqualToString:@"hubname"]
            && [[data valueForKey:@"A"] isEqualToString:@"12345"]) {
            [received fulfill];
        }
    };
    
    [connection start:sse];
    [self waitForExpectationsWithTimeout:5.0 handler:nil];
}

- (void)testHandlesExtraEmptyLinesWhenParsingMessages {
    SRConnection* connection = [[SRConnection alloc] initWithURLString:@"http://localhost:0000"];
    SRServerSentEventsTransport* sse = [SRMockClientTransport sse];
    [SRMockClientTransport negotiateForTransport:sse];
    SRMockSSEResponder *responder = [[SRMockSSEResponder alloc] initWithStatusCode:0 eventStream:@[
        [@"data: initialized\n\n\n" dataUsingEncoding:NSUTF8StringEncoding],
        [@"data: {\"M\":[{\"H\":\"hubname\", \"M\":\"message\", \"A\": \"12345\"}]}\n\n" dataUsingEncoding:NSUTF8StringEncoding]
    ]];
    [SRMockClientTransport connectTransport:sse responder:responder];
    
    XCTestExpectation *received = [self expectationWithDescription:@"received"];
    connection.received = ^(NSString * data){
        if (data) {
            [received fulfill];
        }
    };
    
    [connection start:sse];
    [self waitForExpectationsWithTimeout:5.0 handler:nil];
}

- (void)testHandlesNewLinesSpreadOutOverReads {
    SRConnection* connection = [[SRConnection alloc] initWithURLString:@"http://localhost:0000"];
    SRServerSentEventsTransport* sse = [SRMockClientTransport sse];
    [SRMockClientTransport negotiateForTransport:sse];
    SRMockSSEResponder *responder = [[SRMockSSEResponder alloc] initWithStatusCode:0 eventStream:@[
        [@"data: initialized\n\n" dataUsingEncoding:NSUTF8StringEncoding],
        [@"data: {\"M\":[{\"H\":\"hubname\", \"M\":\"message\", \"A\": \"12345\"}]}" dataUsingEncoding:NSUTF8StringEncoding],
        [@"\n" dataUsingEncoding:NSUTF8StringEncoding]
    ]];
    [SRMockClientTransport connectTransport:sse responder:responder];
    
    XCTestExpectation *received = [self expectationWithDescription:@"received"];
    connection.received = ^(NSString * data){
        if ([[data valueForKey:@"M"] isEqualToString:@"message"]
            && [[data valueForKey:@"H"] isEqualToString:@"hubname"]
            && [[data valueForKey:@"A"] isEqualToString:@"12345"]) {
            [received fulfill];
        }
    };
    
    [connection start:sse];
    [self waitForExpectationsWithTimeout:5.0 handler:nil];
}

- (void)xtestHandlesDisconnectMessageFromConnection {
    XCTAssert(NO, @"not implemented - need to determine support. 2.0.2 sends the D:1 disconenct message but latest does not");
}

@end

@implementation SRServerSentEventsTransportTests (Initialize)

- (void)testStartCallsTheCompletionHandlerAfterSuccess {
    SRConnection* connection = [[SRConnection alloc] initWithURLString:@"http://localhost:0000"];
    SRServerSentEventsTransport* sse = [SRMockClientTransport sse];
    [SRMockClientTransport negotiateForTransport:sse];
    [SRMockClientTransport connectTransport:sse statusCode:@0 json:@{}];
    
    XCTestExpectation *started = [self expectationWithDescription:@"started"];
    connection.started = ^{
        [started fulfill];
    };
    [connection start:sse];
    [self waitForExpectationsWithTimeout:5.0 handler:nil];
}

- (void)testStartCallsTheCompletionHandlerAfterInitialFailure {
    SRConnection* connection = [[SRConnection alloc] initWithURLString:@"http://localhost:0000"];
    SRServerSentEventsTransport* sse = [SRMockClientTransport sse];
    [SRMockClientTransport negotiateForTransport:sse];
    [SRMockClientTransport connectTransport:sse statusCode:@400 error:[[NSError alloc] initWithDomain:@"EXPECTED" code:42 userInfo:nil]];
    [SRMockClientTransport abortForTransport:sse statusCode:@200 json:@{}];
    
    XCTestExpectation *errored = [self expectationWithDescription:@"errored"];
    connection.error = ^(NSError *error){
        [errored fulfill];
    };
    XCTestExpectation *closed = [self expectationWithDescription:@"closed"];
    connection.closed = ^{
        [closed fulfill];
    };
    
    [connection start:sse];
    [self waitForExpectationsWithTimeout:5.0 handler:nil];
}

- (void)testTransportCanTimeoutWhenItDoesNotReceiveInitializeMessage {
    SRConnection* connection = [[SRConnection alloc] initWithURLString:@"http://localhost:0000"];
    SRServerSentEventsTransport* sse = [SRMockClientTransport sse];
    [SRMockClientTransport negotiateForTransport:sse];
    SRMockWaitBlockOperation* transportConnectTimeout = [[SRMockWaitBlockOperation alloc] initWithBlockOperationClass:[SRTransportConnectTimeoutBlockOperation class]];
    [[SRMockClientTransport connectTransport:sse statusCode:@0 json:@{}] beforeData:^(NSData * _Nonnull data) {
        NSString *eventStream = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        if ([eventStream rangeOfString:@"initialized" options:NSCaseInsensitiveSearch].location != NSNotFound) {
            transportConnectTimeout.afterWait();
        }
    }];
    [SRMockClientTransport abortForTransport:sse statusCode:@200 json:@{}];
    
    connection.started = ^{
        XCTAssert(NO, @"Connection started");
    };
    
    XCTestExpectation *errored = [self expectationWithDescription:@"errored"];
    connection.error = ^(NSError *error){
        [errored fulfill];
    };
    
    [connection start:sse];
    [self waitForExpectationsWithTimeout:5.0 handler:nil];
}

@end

@implementation SRServerSentEventsTransportTests (Reconnect)

- (void)testConnectionErrorRetries__RetriesAfterADelay__CommunicatesLifeCycleViaConnection {
    SRConnection* connection = [[SRConnection alloc] initWithURLString:@"http://localhost:0000"];
    SRServerSentEventsTransport* sse = [SRMockClientTransport sse];
    [SRMockClientTransport negotiateForTransport:sse];
    __block SRMockWaitBlockOperation* reconnectDelayBlock = nil;
    [[[SRMockClientTransport connectTransport:sse statusCode:@500 json:@{
        @"M":@[ @{
            @"H":@"hubname",
            @"M":@"message",
            @"A":@"12345"
        } ]
    }] beforeEnd:^(NSError * _Nullable error) {
        reconnectDelayBlock = [[SRMockWaitBlockOperation alloc] initWithBlockOperationClass:[SRServerSentEventsReconnectBlockOperation class]];
    }] afterEnd:^(NSError * _Nullable error) {
        reconnectDelayBlock.afterWait();
    }];
    [SRMockClientTransport abortForTransport:sse statusCode:@200 json:@{}];
    [SRMockClientTransport reconnectTransport:sse statusCode:@0 json:nil];
    
    XCTestExpectation *reconnecting = [self expectationWithDescription:@"reconnecting"];
    connection.reconnecting = ^(){
        [reconnecting fulfill];
    };
    
    XCTestExpectation *reconnected = [self expectationWithDescription:@"reconnected"];
    connection.reconnected = ^(){
        [reconnected fulfill];
    };
    
    [connection start:sse];
    [self waitForExpectationsWithTimeout:5.0 handler:nil];
}

- (void)testDisconnectsOnReconnectTimeout {
    SRConnection* connection = [[SRConnection alloc] initWithURLString:@"http://localhost:0000"];
    SRServerSentEventsTransport* sse = [SRMockClientTransport sse];
    [SRMockClientTransport negotiateForTransport:sse];
     __block SRMockWaitBlockOperation* reconnectDelayBlock = nil;
    [[[SRMockClientTransport connectTransport:sse statusCode:@500 json:@{
        @"M":@[ @{
            @"H":@"hubname",
            @"M":@"message",
            @"A":@"12345"
        } ]
    }] beforeEnd:^(NSError * _Nullable error) {
        reconnectDelayBlock = [[SRMockWaitBlockOperation alloc] initWithBlockOperationClass:[SRServerSentEventsReconnectBlockOperation class]];
    }] afterEnd:^(NSError * _Nullable error) {
        reconnectDelayBlock.afterWait();
    }];
    
    __block SRMockWaitBlockOperation* reconnectTimeoutBlock = nil;
    connection.stateChanged = ^(connectionState state) {
        if (state == reconnecting) {
            reconnectTimeoutBlock = [[SRMockWaitBlockOperation alloc] initWithWaitTime:[connection.disconnectTimeout doubleValue]];
        }
    };
    [SRMockClientTransport abortForTransport:sse statusCode:@200 json:nil];
    [[SRMockClientTransport reconnectTransport:sse statusCode:@0 json:@{}] beforeStart:^{
        reconnectTimeoutBlock.afterWait();
    }];
    
    XCTestExpectation *started = [self expectationWithDescription:@"started"];
    connection.started = ^{
        [started fulfill];
    };
    
    XCTestExpectation *reconnecting = [self expectationWithDescription:@"Retrying callback called"];
    connection.reconnecting = ^(){
        [reconnecting fulfill];
    };
    
    connection.reconnected = ^(){
        XCTAssert(NO, @"unexpected change!");
    };
    
    XCTestExpectation *closed = [self expectationWithDescription:@"closed"];
    connection.closed = ^(){
        [closed fulfill];
    };
    
    [connection start:sse];
    [self waitForExpectationsWithTimeout:5.0 handler:nil];
}

- (void)testStreamClosesCleanlyShouldReconnect {
    SRConnection* connection = [[SRConnection alloc] initWithURLString:@"http://localhost:0000"];
    SRServerSentEventsTransport* sse = [SRMockClientTransport sse];
    [SRMockClientTransport negotiateForTransport:sse];
    __block SRMockWaitBlockOperation* reconnectDelayBlock = nil;
    [[[SRMockClientTransport connectTransport:sse statusCode:@200 json:@{
        @"M":@[ @{
            @"H":@"hubname",
            @"M":@"message",
            @"A":@"12345"
        } ]
    }] beforeEnd:^(NSError * _Nullable error) {
        reconnectDelayBlock = [[SRMockWaitBlockOperation alloc] initWithBlockOperationClass:[SRServerSentEventsReconnectBlockOperation class]];
    }] afterEnd:^(NSError * _Nullable error) {
        reconnectDelayBlock.afterWait();
    }];
    [SRMockClientTransport abortForTransport:sse statusCode:@200 json:@{}];
    [SRMockClientTransport reconnectTransport:sse statusCode:@0 json:@{}];
    
    XCTestExpectation *reconnecting = [self expectationWithDescription:@"reconnecting"];
    connection.reconnecting = ^(){
        [reconnecting fulfill];
    };
    
    XCTestExpectation *reconnected = [self expectationWithDescription:@"reconnected"];
    connection.reconnected = ^(){
        [reconnected fulfill];
    };
    
    [connection start:sse];
    [self waitForExpectationsWithTimeout:5.0 handler:nil];
}

@end

@implementation SRServerSentEventsTransportTests (LostConnection)

- (void)testLostConnectionAbortsAllConnectionsAndReconnects {
    SRConnection* connection = [[SRConnection alloc] initWithURLString:@"http://localhost:0000"];
    SRServerSentEventsTransport* sse = [SRMockClientTransport sse];
    [SRMockClientTransport negotiateForTransport:sse];
    __block SRMockWaitBlockOperation* reconnectDelayBlock = nil;
    [[SRMockClientTransport connectTransport:sse statusCode:@0 json:@{
       @"M":@[ @{
           @"H":@"hubname",
           @"M":@"message",
           @"A":@"12345"
       } ]
    }] afterData:^(NSData * _Nonnull data) {
        NSString *eventStream = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        if ([eventStream rangeOfString:@"12345" options:NSCaseInsensitiveSearch].location != NSNotFound) {
            reconnectDelayBlock = [[SRMockWaitBlockOperation alloc] initWithBlockOperationClass:[SRServerSentEventsReconnectBlockOperation class]];
            [sse lostConnection:connection];
            //TODO: Hack to allow NSURLProtocolClient to finish pumping messages
            [NSThread sleepForTimeInterval:.1];
            reconnectDelayBlock.afterWait();
        }
    }];
    [SRMockClientTransport abortForTransport:sse statusCode:@200 json:@{}];
    [SRMockClientTransport reconnectTransport:sse statusCode:@0 json:@{}];
    
    XCTestExpectation *reconnecting = [self expectationWithDescription:@"reconnecting"];
    connection.reconnecting = ^(){
        [reconnecting fulfill];
    };
    
    XCTestExpectation *reconnected = [self expectationWithDescription:@"reconnected"];
    connection.reconnected = ^(){
        [reconnected fulfill];
    };
    
    [connection start:sse];
    [self waitForExpectationsWithTimeout:5.0 handler:nil];
}

@end

@implementation SRServerSentEventsTransportTests (Ping)

- (void)xtestPingIntervalStopsTheConnectionOn401s {
    SRConnection* connection = [[SRConnection alloc] initWithURLString:@"http://localhost:0000"];
    SRServerSentEventsTransport* sse = [SRMockClientTransport sse];
    [SRMockClientTransport negotiateForTransport:sse];
    [SRMockClientTransport connectTransport:sse statusCode:@0 json:@{
        @"M":@[ @{
            @"H":@"hubname",
            @"M":@"message",
            @"A":@"12345"
        } ]
    }];
    
    XCTestExpectation *errored = [self expectationWithDescription:@"errored"];
    connection.error = ^(NSError *error){
        [errored fulfill];
        XCTAssert(NO, @"todo: verify it's a 401");
    };
    
    [connection start:sse];
    [self waitForExpectationsWithTimeout:5.0 handler:nil];
}

- (void)xtestPingIntervalStopsTheConnectionOn403s {
    SRConnection* connection = [[SRConnection alloc] initWithURLString:@"http://localhost:0000"];
    SRServerSentEventsTransport* sse = [SRMockClientTransport sse];
    [SRMockClientTransport negotiateForTransport:sse];
    [SRMockClientTransport connectTransport:sse statusCode:@0 json:@{
        @"M":@[ @{
            @"H":@"hubname",
            @"M":@"message",
            @"A":@"12345"
        } ]
    }];
    
    XCTestExpectation *errored = [self expectationWithDescription:@"errored"];
    connection.error = ^(NSError *error){
        [errored fulfill];
        XCTAssert(NO, @"todo: verify it's a 403");
    };
    
    [connection start:sse];
    [self waitForExpectationsWithTimeout:5.0 handler:nil];
}

- (void)xtestPingIntervalBehavesAppropriately {
    XCTAssert(NO, @"not implemented");
}

@end