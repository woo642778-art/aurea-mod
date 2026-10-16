// SPDX-License-Identifier: MIT. A mock verifies the bridge contract, not Aurea runtime behavior.
#import <Foundation/Foundation.h>
#import "AUEngineAccess.h"
#import <objc/runtime.h>
static int renders=0,resumes=0,imports=0;
static NSString *sourcePath;
static NSArray *selectedIDs;
@interface AureaEngine : NSObject
- (void)requestRender; - (void)resume;
- (NSArray *)selection;
- (NSString *)layerSourcePath:(long long)layer;
- (NSString *)layerMediaPath:(long long)layer;
- (long long)importImageFile:(NSString *)path name:(NSString *)name;
- (void)selectLayers:(NSArray *)layers;
@end
@implementation AureaEngine
- (void)requestRender {renders++;}
- (void)resume {resumes++;}
- (NSArray *)selection {return @[@17];}
- (NSString *)layerSourcePath:(long long)layer {return layer==17?sourcePath:nil;}
- (NSString *)layerMediaPath:(long long)layer {(void)layer;return @"/nonexistent/proxy";}
- (long long)importImageFile:(NSString *)path name:(NSString *)name {if(![NSFileManager.defaultManager fileExistsAtPath:path]||!name.length)return -1;imports++;return 91;}
- (void)selectLayers:(NSArray *)layers {selectedIDs=layers;}
@end
#define CHECK(x) do{if(!(x)){fprintf(stderr,"FAIL line %d: %s\n",__LINE__,#x);return 1;}checks++;}while(0)
int main(void){@autoreleasepool {
    int checks=0;[AUEngineAccess install];[AUEngineAccess install];
    CHECK(![AUEngineAccess status][@"available"].boolValue);
    AureaEngine *engine=[AureaEngine new];[engine resume];[engine requestRender];
    CHECK(resumes==1&&renders==1);CHECK([AUEngineAccess current]==engine);
    CHECK([AUEngineAccess status][@"available"].boolValue);
    sourcePath=[NSTemporaryDirectory() stringByAppendingPathComponent:[NSUUID.UUID.UUIDString stringByAppendingString:@".png"]];
    CHECK([[@"file-fixture" dataUsingEncoding:NSUTF8StringEncoding] writeToFile:sourcePath atomically:YES]);
    NSError *error=nil;NSArray *media=[AUEngineAccess selectedMedia:&error];CHECK(!error&&media.count==1);CHECK([media[0] path]!=nil);CHECK([[media[0] path] isEqualToString:sourcePath]);
    NSNumber *layer=[AUEngineAccess importMedia:[NSURL fileURLWithPath:sourcePath] error:&error];CHECK(!error&&layer.longLongValue==91);CHECK(imports==1&&renders==2);CHECK([selectedIDs isEqual:@[@91]]);
    error=nil;CHECK(![AUEngineAccess importMedia:[NSURL fileURLWithPath:@"/tmp/unsupported.ecproj"] error:&error]);CHECK(error!=nil&&imports==1);
    [NSFileManager.defaultManager removeItemAtPath:sourcePath error:nil];
    printf("Engine bridge mock: %d assertions passed (not a test of the original Aurea engine).\n",checks);
    return 0;
}}
