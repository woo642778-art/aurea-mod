// SPDX-License-Identifier: MIT
// Only selectors and signatures observed in Aurea 0.1.9 (2185) are used.
#import "AUEngineAccess.h"
#import <objc/runtime.h>
#import <objc/message.h>
static __weak id AULiveEngine;
static IMP AUOriginalRender=NULL;
static IMP AUOriginalResume=NULL;
static BOOL AUInstalled=NO;
static BOOL AUHas(id object,SEL selector,const char *encoding) {
    Method m=class_getInstanceMethod(object_getClass(object),selector);
    return m && strcmp(method_getTypeEncoding(m),encoding)==0;
}
static void AUCapture(id object) { @synchronized(AUEngineAccess.class) { AULiveEngine=object; } }
static void AURenderHook(id object,SEL selector) { AUCapture(object); ((void(*)(id,SEL))AUOriginalRender)(object,selector); }
static void AUResumeHook(id object,SEL selector) { AUCapture(object); ((void(*)(id,SEL))AUOriginalResume)(object,selector); }
static NSError *AUBridgeError(NSString *message) { return [NSError errorWithDomain:@"AureaStudio.Engine" code:1 userInfo:@{NSLocalizedDescriptionKey:message}]; }
@implementation AUEngineAccess
+ (void)install {
    @synchronized(self) {
        if(AUInstalled)return;
        Class cls=NSClassFromString(@"AureaEngine"); if(!cls)return;
        Method render=class_getInstanceMethod(cls,NSSelectorFromString(@"requestRender"));
        Method resume=class_getInstanceMethod(cls,NSSelectorFromString(@"resume"));
        if(render && strcmp(method_getTypeEncoding(render),"v16@0:8")==0) {
            AUOriginalRender=method_getImplementation(render);
            method_setImplementation(render,(IMP)AURenderHook);
        }
        if(resume && strcmp(method_getTypeEncoding(resume),"v16@0:8")==0) {
            AUOriginalResume=method_getImplementation(resume);
            method_setImplementation(resume,(IMP)AUResumeHook);
        }
        AUInstalled=(AUOriginalRender!=NULL || AUOriginalResume!=NULL);
    }
}
+ (id)current { @synchronized(self) { return AULiveEngine; } }
+ (NSDictionary *)status {
    id engine=[self current];
    // Boxing a C comparison produces NSNumber(int), which WebKit sends as 1/0.
    // Explicit boolean objects preserve the JavaScript bridge schema on every ABI.
    return @{@"available":engine ? @YES : @NO,@"observing":AUInstalled ? @YES : @NO,@"mode":@"additive-media-bridge",@"nativeEffectParity":@NO};
}
+ (NSArray<NSURL *> *)selectedMedia:(NSError **)error {
    if(!NSThread.isMainThread) {if(error)*error=AUBridgeError(@"Open this command on the editor thread.");return @[];}
    id engine=[self current];
    if(!engine) {if(error)*error=AUBridgeError(@"먼저 Aurea에서 프로젝트를 열고 레이어를 선택한 뒤 Studio를 다시 여세요.");return @[];}
    SEL selection=NSSelectorFromString(@"selection");
    if(!AUHas(engine,selection,"@16@0:8")) {if(error)*error=AUBridgeError(@"Aurea의 선택 API가 이 빌드와 일치하지 않습니다.");return @[];}
    @try {
        id selected=((id(*)(id,SEL))objc_msgSend)(engine,selection);
        if(![selected isKindOfClass:NSArray.class] || [selected count]==0) {if(error)*error=AUBridgeError(@"Aurea에서 이미지·영상·오디오 레이어를 먼저 선택하세요.");return @[];}
        if([selected count]>8) {if(error)*error=AUBridgeError(@"한 번에 최대 8개 레이어를 가져올 수 있습니다.");return @[];}
        NSMutableArray<NSURL *> *urls=[NSMutableArray array];
        for(id value in selected) {
            if(![value isKindOfClass:NSNumber.class])continue;
            long long layer=[value longLongValue];
            for(NSString *name in @[@"layerSourcePath:",@"layerMediaPath:"]) {
                SEL sel=NSSelectorFromString(name);
                if(!AUHas(engine,sel,"@24@0:8q16"))continue;
                id path=((id(*)(id,SEL,long long))objc_msgSend)(engine,sel,layer);
                if(![path isKindOfClass:NSString.class] || ![path length])continue;
                NSURL *url=[path hasPrefix:@"file://"]?[NSURL URLWithString:path]:[NSURL fileURLWithPath:path];
                NSNumber *regular=nil; [url getResourceValue:&regular forKey:NSURLIsRegularFileKey error:nil];
                if(regular.boolValue) {if(![urls containsObject:url])[urls addObject:url];break;}
            }
        }
        if(!urls.count && error)*error=AUBridgeError(@"선택 항목에서 읽을 수 있는 원본 미디어를 찾지 못했습니다. 텍스트·도형·컴포지션은 Aurea에서 파일로 내보낸 후 가져오세요.");
        return urls;
    } @catch(NSException *exception) {
        (void)exception; if(error)*error=AUBridgeError(@"Aurea의 레이어 정보를 읽지 못했습니다. 원본 프로젝트는 변경하지 않았습니다.");return @[];
    }
}
+ (NSNumber *)importMedia:(NSURL *)url error:(NSError **)error {
    if(!NSThread.isMainThread) {if(error)*error=AUBridgeError(@"Open this command on the editor thread.");return nil;}
    id engine=[self current];
    if(!engine) {if(error)*error=AUBridgeError(@"Aurea 프로젝트가 열려 있지 않습니다. 저장된 결과물은 Studio 보관함에서 다시 가져올 수 있습니다.");return nil;}
    NSString *ext=url.pathExtension.lowercaseString;
    NSString *selectorName=nil;
    if([@[@"png",@"jpg",@"jpeg",@"webp"] containsObject:ext])selectorName=@"importImageFile:name:";
    else if([@[@"mp4",@"mov",@"m4v"] containsObject:ext])selectorName=@"importVideo:name:";
    else if([@[@"wav",@"mp3",@"m4a",@"aac",@"aiff"] containsObject:ext])selectorName=@"importAudio:name:";
    else {if(error)*error=AUBridgeError(@"이 형식은 자동 레이어 가져오기를 지원하지 않습니다. 공유 메뉴로 파일을 저장하세요.");return nil;}
    SEL selector=NSSelectorFromString(selectorName);
    if(!AUHas(engine,selector,"q32@0:8@16@24")) {if(error)*error=AUBridgeError(@"이 Aurea 빌드의 미디어 가져오기 API가 예상과 다릅니다.");return nil;}
    @try {
        long long result=((long long(*)(id,SEL,id,id))objc_msgSend)(engine,selector,url.path,url.lastPathComponent.stringByDeletingPathExtension);
        if(result<=0) {
            SEL last=NSSelectorFromString(@"lastImportError"); id detail=nil;
            if(AUHas(engine,last,"@16@0:8"))detail=((id(*)(id,SEL))objc_msgSend)(engine,last);
            if(error)*error=AUBridgeError([detail isKindOfClass:NSString.class] && [detail length]?detail:@"Aurea가 이 파일을 가져오지 못했습니다. 보관함의 원본 결과물은 유지됩니다.");return nil;
        }
        SEL select=NSSelectorFromString(@"selectLayers:");
        if(AUHas(engine,select,"v24@0:8@16"))((void(*)(id,SEL,id))objc_msgSend)(engine,select,@[@(result)]);
        SEL render=NSSelectorFromString(@"requestRender");
        if(AUHas(engine,render,"v16@0:8"))((void(*)(id,SEL))objc_msgSend)(engine,render);
        return @(result);
    } @catch(NSException *exception) {
        (void)exception; if(error)*error=AUBridgeError(@"가져오기 결과를 확인하지 못했습니다. 중복 생성을 막기 위해 Aurea의 레이어 목록을 먼저 확인하세요.");return nil;
    }
}
@end
