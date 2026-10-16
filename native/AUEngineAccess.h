// SPDX-License-Identifier: MIT
#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
@interface AUEngineAccess : NSObject
+ (void)install;
+ (nullable id)current;
+ (NSDictionary *)status;
+ (NSArray<NSURL *> *)selectedMedia:(NSError * _Nullable * _Nullable)error;
+ (nullable NSNumber *)importMedia:(NSURL *)url error:(NSError * _Nullable * _Nullable)error;
@end
NS_ASSUME_NONNULL_END
