// SPDX-License-Identifier: MIT
#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
@interface AUServer : NSObject
@property(nonatomic, readonly) NSURL *baseURL;
@property(nonatomic, readonly) NSURL *storageURL;
@property(nonatomic, readonly) NSString *token;
@property(nonatomic, readonly) uint16_t port;
- (instancetype)initWithRoot:(NSURL *)root storage:(NSURL *)storage;
- (BOOL)start:(NSError * _Nullable * _Nullable)error;
- (void)stop;
- (BOOL)isLocalURL:(NSURL *)url;
- (nullable NSDictionary *)registerInput:(NSURL *)url error:(NSError * _Nullable * _Nullable)error;
- (nullable NSURL *)exportURL:(NSString *)identifier;
- (NSArray<NSDictionary *> *)exports;
- (nullable NSDictionary *)registerExport:(NSURL *)url error:(NSError * _Nullable * _Nullable)error;
@end
NS_ASSUME_NONNULL_END
