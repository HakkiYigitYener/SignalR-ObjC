//
//  SRMockNetwork.m
//  SignalR.Client.ObjC
//
//  Created by Alex Billingsley on 9/2/15.
//  Copyright (c) 2015 DyKnow LLC. All rights reserved.
//

#import "SRMockNetwork.h"
#import <OCMock/OCMock.h>
#import <AFNetworking/AFNetworking.h>

@implementation SRMockNetwork

+ (id)    stub:(id)mock
    statusCode:(NSNumber *)statusCode
          json:(id)json
       success:(NSInteger)successIndex
         error:(NSInteger)errorIndex
{

    [[[mock stub] andDo:^(NSInvocation *invocation) {
        
        void (^completionBlock)(NSURLResponse *response, id _Nullable responseObject, NSError *_Nullable error);
        [invocation getArgument:&completionBlock atIndex:successIndex];
        
        if (completionBlock)
        {
            NSURLResponse *urlResponse = [[NSURLResponse alloc] initWithURL:[NSURL URLWithString:@"http://mock"]
                                                                   MIMEType:nil
                                                      expectedContentLength:-1
                                                           textEncodingName:nil];
            if ([statusCode isEqual:@200])
            {


                if ([json isKindOfClass:[NSString class]])
                {
                    completionBlock(urlResponse, json, nil);
                } else if ([json isKindOfClass:[NSDictionary class]] ||
                           [json isKindOfClass:[NSSet class]] ||
                           [json isKindOfClass:[NSArray class]])
                {
                    NSData *responseData = [NSJSONSerialization dataWithJSONObject:json options:(NSJSONWritingOptions)0 error:NULL];
                    completionBlock(urlResponse, [[NSString alloc] initWithData:responseData encoding:NSUTF8StringEncoding], nil);

                }

                completionBlock(urlResponse, json, nil);
            } else
            {

                completionBlock(urlResponse, nil, [NSError errorWithDomain:@"com.mock.signalR" code:[statusCode integerValue] userInfo:nil]);
            }
        }


    }] dataTaskWithRequest:[OCMArg any] completionHandler:[OCMArg any]];
    return mock;
}

+ (id)mockHttpRequestOperationForClass:(Class)aClass
                            statusCode:(NSNumber *)statusCode
                                  json:(id)json
{
    return [[self class] mockHttpRequestOperationForClass:aClass statusCode:statusCode json:json success:2 error:-1];
}

+ (id)mockHttpRequestOperationForClass:(Class)aClass
                            statusCode:(NSNumber *)statusCode
                                  json:(id)json
                               success:(NSInteger)successIndex
                                 error:(NSInteger)errorIndex
{
    id operationMock = [OCMockObject niceMockForClass:aClass];
    [[[operationMock stub] andReturn:operationMock] alloc];
    // And we stub initWithParam: passing the param we will pass to the method to test
    [[operationMock stub] dataTaskWithRequest:[OCMArg any] completionHandler:[OCMArg any]];
    return [[self class] stub:operationMock statusCode:statusCode json:json success:successIndex error:errorIndex];
}

+ (id)mockHttpRequestOperationForClass:(Class)aClass
                            statusCode:(NSNumber *)statusCode
                        responseString:(NSString *)responseString; {
    return [[self class] mockHttpRequestOperationForClass:aClass statusCode:statusCode json:responseString];
}

+ (id)mockHttpRequestOperationForClass:(Class)aClass
                            statusCode:(NSNumber *)statusCode
                        responseString:(NSString *)responseString
                               success:(NSInteger)successIndex
                                 error:(NSInteger)errorIndex; {
    return [[self class] mockHttpRequestOperationForClass:aClass statusCode:statusCode json:responseString success:successIndex error:errorIndex];
}

+ (id)mockHttpRequestOperationForClass:(Class)aClass
                            statusCode:(NSNumber *)statusCode
                                 error:(NSError *)error; {
    return [[self class] mockHttpRequestOperationForClass:aClass statusCode:statusCode json:error];
}

+ (id)mockHttpRequestOperationForClass:(Class)aClass
                            statusCode:(NSNumber *)statusCode
                                 error:(NSError *)error
                               success:(NSInteger)successIndex
                                 error:(NSInteger)errorIndex; {
    return [[self class] mockHttpRequestOperationForClass:aClass statusCode:statusCode json:error success:successIndex error:errorIndex];
}

@end
