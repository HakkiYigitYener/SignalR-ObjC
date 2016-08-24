// CWHTTPRequestOperationManager.m
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

#import <Foundation/Foundation.h>

#import "CWHTTPRequestOperationManager.h"
#import "CWHTTPRequestOperation.h"

#import <Availability.h>
#import <Security/Security.h>

#if defined(__IPHONE_OS_VERSION_MIN_REQUIRED)
#import <UIKit/UIKit.h>
#endif

@interface CWHTTPRequestOperationManager ()
@property (readwrite, nonatomic, strong) NSURL *baseURL;
@end

@implementation CWHTTPRequestOperationManager

+ (instancetype)manager {
    return [[self alloc] initWithBaseURL:nil];
}

- (instancetype)init {
    return [self initWithBaseURL:nil];
}

- (instancetype)initWithBaseURL:(NSURL *)url {
    self = [super init];
    if (!self) {
        return nil;
    }

    // Ensure terminal slash for baseURL path, so that NSURL +URLWithString:relativeToURL: works as expected
    if ([[url path] length] > 0 && ![[url absoluteString] hasSuffix:@"/"]) {
        url = [url URLByAppendingPathComponent:@""];
    }

    self.baseURL = url;

    self.requestSerializer = [CWHTTPRequestSerializer serializer];
    self.responseSerializer = [CWJSONResponseSerializer serializer];

    self.securityPolicy = [CWSecurityPolicy defaultPolicy];

    self.reachabilityManager = [CWNetworkReachabilityManager sharedManager];

    self.operationQueue = [[NSOperationQueue alloc] init];

    self.shouldUseCredentialStorage = YES;

    return self;
}

#pragma mark -

#ifdef _SYSTEMCONFIGURATION_H
#endif

- (void)setRequestSerializer:(CWHTTPRequestSerializer <CWURLRequestSerialization> *)requestSerializer {
    NSParameterAssert(requestSerializer);

    _requestSerializer = requestSerializer;
}

- (void)setResponseSerializer:(CWHTTPResponseSerializer <CWURLResponseSerialization> *)responseSerializer {
    NSParameterAssert(responseSerializer);

    _responseSerializer = responseSerializer;
}

#pragma mark -

- (CWHTTPRequestOperation *)HTTPRequestOperationWithHTTPMethod:(NSString *)method
                                                     URLString:(NSString *)URLString
                                                    parameters:(id)parameters
                                                       success:(void (^)(CWHTTPRequestOperation *operation, id responseObject))success
                                                       failure:(void (^)(CWHTTPRequestOperation *operation, NSError *error))failure
{
    NSError *serializationError = nil;
    NSMutableURLRequest *request = [self.requestSerializer requestWithMethod:method URLString:[[NSURL URLWithString:URLString relativeToURL:self.baseURL] absoluteString] parameters:parameters error:&serializationError];
    if (serializationError) {
        if (failure) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wgnu"
            dispatch_async(self.completionQueue ?: dispatch_get_main_queue(), ^{
                failure(nil, serializationError);
            });
#pragma clang diagnostic pop
        }

        return nil;
    }

    return [self HTTPRequestOperationWithRequest:request success:success failure:failure];
}

- (CWHTTPRequestOperation *)HTTPRequestOperationWithRequest:(NSURLRequest *)request
                                                    success:(void (^)(CWHTTPRequestOperation *operation, id responseObject))success
                                                    failure:(void (^)(CWHTTPRequestOperation *operation, NSError *error))failure
{
    CWHTTPRequestOperation *operation = [[CWHTTPRequestOperation alloc] initWithRequest:request];
    operation.responseSerializer = self.responseSerializer;
    operation.shouldUseCredentialStorage = self.shouldUseCredentialStorage;
    operation.credential = self.credential;
    operation.securityPolicy = self.securityPolicy;

    [operation setCompletionBlockWithSuccess:success failure:failure];
    operation.completionQueue = self.completionQueue;
    operation.completionGroup = self.completionGroup;

    return operation;
}

#pragma mark -

- (CWHTTPRequestOperation *)GET:(NSString *)URLString
                     parameters:(id)parameters
                        success:(void (^)(CWHTTPRequestOperation *operation, id responseObject))success
                        failure:(void (^)(CWHTTPRequestOperation *operation, NSError *error))failure
{
    CWHTTPRequestOperation *operation = [self HTTPRequestOperationWithHTTPMethod:@"GET" URLString:URLString parameters:parameters success:success failure:failure];

    [self.operationQueue addOperation:operation];

    return operation;
}

- (CWHTTPRequestOperation *)HEAD:(NSString *)URLString
                      parameters:(id)parameters
                         success:(void (^)(CWHTTPRequestOperation *operation))success
                         failure:(void (^)(CWHTTPRequestOperation *operation, NSError *error))failure
{
    CWHTTPRequestOperation *operation = [self HTTPRequestOperationWithHTTPMethod:@"HEAD" URLString:URLString parameters:parameters success:^(CWHTTPRequestOperation *requestOperation, __unused id responseObject) {
        if (success) {
            success(requestOperation);
        }
    } failure:failure];

    [self.operationQueue addOperation:operation];

    return operation;
}

- (CWHTTPRequestOperation *)POST:(NSString *)URLString
                      parameters:(id)parameters
                         success:(void (^)(CWHTTPRequestOperation *operation, id responseObject))success
                         failure:(void (^)(CWHTTPRequestOperation *operation, NSError *error))failure
{
    CWHTTPRequestOperation *operation = [self HTTPRequestOperationWithHTTPMethod:@"POST" URLString:URLString parameters:parameters success:success failure:failure];

    [self.operationQueue addOperation:operation];

    return operation;
}

- (CWHTTPRequestOperation *)POST:(NSString *)URLString
                      parameters:(id)parameters
       constructingBodyWithBlock:(void (^)(id <CWMultipartFormData> formData))block
                         success:(void (^)(CWHTTPRequestOperation *operation, id responseObject))success
                         failure:(void (^)(CWHTTPRequestOperation *operation, NSError *error))failure
{
    NSError *serializationError = nil;
    NSMutableURLRequest *request = [self.requestSerializer multipartFormRequestWithMethod:@"POST" URLString:[[NSURL URLWithString:URLString relativeToURL:self.baseURL] absoluteString] parameters:parameters constructingBodyWithBlock:block error:&serializationError];
    if (serializationError) {
        if (failure) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wgnu"
            dispatch_async(self.completionQueue ?: dispatch_get_main_queue(), ^{
                failure(nil, serializationError);
            });
#pragma clang diagnostic pop
        }

        return nil;
    }

    CWHTTPRequestOperation *operation = [self HTTPRequestOperationWithRequest:request success:success failure:failure];

    [self.operationQueue addOperation:operation];

    return operation;
}

- (CWHTTPRequestOperation *)PUT:(NSString *)URLString
                     parameters:(id)parameters
                        success:(void (^)(CWHTTPRequestOperation *operation, id responseObject))success
                        failure:(void (^)(CWHTTPRequestOperation *operation, NSError *error))failure
{
    CWHTTPRequestOperation *operation = [self HTTPRequestOperationWithHTTPMethod:@"PUT" URLString:URLString parameters:parameters success:success failure:failure];

    [self.operationQueue addOperation:operation];

    return operation;
}

- (CWHTTPRequestOperation *)PATCH:(NSString *)URLString
                       parameters:(id)parameters
                          success:(void (^)(CWHTTPRequestOperation *operation, id responseObject))success
                          failure:(void (^)(CWHTTPRequestOperation *operation, NSError *error))failure
{
    CWHTTPRequestOperation *operation = [self HTTPRequestOperationWithHTTPMethod:@"PATCH" URLString:URLString parameters:parameters success:success failure:failure];

    [self.operationQueue addOperation:operation];

    return operation;
}

- (CWHTTPRequestOperation *)DELETE:(NSString *)URLString
                        parameters:(id)parameters
                           success:(void (^)(CWHTTPRequestOperation *operation, id responseObject))success
                           failure:(void (^)(CWHTTPRequestOperation *operation, NSError *error))failure
{
    CWHTTPRequestOperation *operation = [self HTTPRequestOperationWithHTTPMethod:@"DELETE" URLString:URLString parameters:parameters success:success failure:failure];

    [self.operationQueue addOperation:operation];

    return operation;
}

#pragma mark - NSObject

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %p, baseURL: %@, operationQueue: %@>", NSStringFromClass([self class]), self, [self.baseURL absoluteString], self.operationQueue];
}

#pragma mark - NSSecureCoding

+ (BOOL)supportsSecureCoding {
    return YES;
}

- (id)initWithCoder:(NSCoder *)decoder {
    NSURL *baseURL = [decoder decodeObjectForKey:NSStringFromSelector(@selector(baseURL))];

    self = [self initWithBaseURL:baseURL];
    if (!self) {
        return nil;
    }

    self.requestSerializer = [decoder decodeObjectOfClass:[CWHTTPRequestSerializer class] forKey:NSStringFromSelector(@selector(requestSerializer))];
    self.responseSerializer = [decoder decodeObjectOfClass:[CWHTTPResponseSerializer class] forKey:NSStringFromSelector(@selector(responseSerializer))];
    CWSecurityPolicy *decodedPolicy = [decoder decodeObjectOfClass:[CWSecurityPolicy class] forKey:NSStringFromSelector(@selector(securityPolicy))];
    if (decodedPolicy) {
        self.securityPolicy = decodedPolicy;
    }

    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeObject:self.baseURL forKey:NSStringFromSelector(@selector(baseURL))];
    [coder encodeObject:self.requestSerializer forKey:NSStringFromSelector(@selector(requestSerializer))];
    [coder encodeObject:self.responseSerializer forKey:NSStringFromSelector(@selector(responseSerializer))];
    [coder encodeObject:self.securityPolicy forKey:NSStringFromSelector(@selector(securityPolicy))];
}

#pragma mark - NSCopying

- (id)copyWithZone:(NSZone *)zone {
    CWHTTPRequestOperationManager *HTTPClient = [[[self class] allocWithZone:zone] initWithBaseURL:self.baseURL];

    HTTPClient.requestSerializer = [self.requestSerializer copyWithZone:zone];
    HTTPClient.responseSerializer = [self.responseSerializer copyWithZone:zone];
    HTTPClient.securityPolicy = [self.securityPolicy copyWithZone:zone];

    return HTTPClient;
}

@end
