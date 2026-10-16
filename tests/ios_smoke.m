// SPDX-License-Identifier: MIT
// Real UIKit/WebKit and production extension, with a MOCK Aurea engine.
#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>
static NSString *fixture;
static int imported;
@interface AureaEngine:NSObject
- (void)resume; - (void)requestRender;
- (NSArray *)selection;
- (NSString *)layerSourcePath:(long long)layer;
- (long long)importImageFile:(NSString *)path name:(NSString *)name;
- (void)selectLayers:(NSArray *)ids;
@end
@implementation AureaEngine
- (void)resume {}
- (void)requestRender {}
- (NSArray *)selection {return @[@1];}
- (NSString *)layerSourcePath:(long long)layer {(void)layer;return fixture;}
- (long long)importImageFile:(NSString *)path name:(NSString *)name {
    (void)name;UIImage *image=[UIImage imageWithContentsOfFile:path];
    if(!image || image.size.width!=320 || image.size.height!=240)return -1;
    imported++;return 91;
}
- (void)selectLayers:(NSArray *)ids {(void)ids;}
@end
static void Save(id value) {
    NSURL *folder=[NSFileManager.defaultManager URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].firstObject;
    NSData *data=[NSJSONSerialization dataWithJSONObject:value options:NSJSONWritingPrettyPrinted error:nil];
    [data writeToURL:[folder URLByAppendingPathComponent:@"simulator-result.json"] atomically:YES];
    NSLog(@"SIMULATOR_RESULT %@",[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]);
}
@interface SmokeScene:NSObject<UIWindowSceneDelegate>
@property(nonatomic,strong) UIWindow *window;
@property(nonatomic,strong) AureaEngine *engine;
@property(nonatomic) NSInteger attempts;
@property(nonatomic) BOOL started;
@end
@implementation SmokeScene
- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options {
    (void)session;(void)options;
    self.window=[[UIWindow alloc] initWithWindowScene:(UIWindowScene *)scene];
    self.window.rootViewController=[UIViewController new];
    self.window.rootViewController.view.backgroundColor=UIColor.systemBackgroundColor;
    [self.window makeKeyAndVisible];
    fixture=[NSTemporaryDirectory() stringByAppendingPathComponent:@"test input # Korean 테스트.png"];
    UIGraphicsImageRenderer *renderer=[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(16,16)];
    UIImage *image=[renderer imageWithActions:^(UIGraphicsImageRendererContext *c){[UIColor.redColor setFill];[c fillRect:CGRectMake(0,0,16,16)];}];
    [UIImagePNGRepresentation(image) writeToFile:fixture atomically:YES];
    self.engine=[AureaEngine new];[self.engine resume];[self.engine requestRender];
    [self performSelector:@selector(probe) withObject:nil afterDelay:2];
}
- (void)probe {
    if(self.started)return;
    if(++self.attempts>150){Save(@{@"success":@NO,@"error":@"Studio launch/readiness timed out"});return;}
    UIButton *launcher=[self.window viewWithTag:0x41554352];
    UINavigationController *nav=(id)self.window.rootViewController.presentedViewController;
    if(!nav && launcher){[launcher sendActionsForControlEvents:UIControlEventTouchUpInside];}
    if([nav isKindOfClass:UINavigationController.class]) {
        WKWebView *web=[nav.topViewController valueForKey:@"web"];
        if(web){
            [web evaluateJavaScript:@"!!window.AureaStudio?.ready" completionHandler:^(id ready,NSError *error){
                if(!error && [ready boolValue] && !self.started){self.started=YES;[self run:web];}
            }];
        }
    }
    [self performSelector:@selector(probe) withObject:nil afterDelay:2];
}
- (void)run:(WKWebView *)web {
    NSString *script=@"const checks=[];const check=(n,v)=>{if(!v)throw Error(n);checks.push(n)};"
    @"const bridge=(action,args={})=>webkit.messageHandlers.aureaStudio.postMessage({action,...args});"
    @"check('real WASM effects',AureaStudio.counts.effects===307);"
    @"check('real command registry',AureaStudio.counts.commands===731);"
    @"const status=await bridge('status');check('reply handler and mock engine captured',status.available===true);"
    @"const selected=await bridge('selectedMedia');check('selected-media bridge',selected.length===1);"
    @"const input=await fetch(selected[0].url);check('encoded source URL',input.ok&&(await input.arrayBuffer()).byteLength>32);"
    @"await AureaStudio.command('comp.new',{name:'iOS validation',width:320,height:240,frameRate:24,duration:1});"
    @"await AureaStudio.command('layer.newSolid',{name:'iOS solid',color:'#336699',width:160,height:120});"
    @"await AureaStudio.command('effect.apply',{effect:'ec.blur.gaussian'});"
    @"await AureaStudio.exportFrame();const files=await bridge('exports');const png=files.find(x=>x.name.endsWith('.png'));"
    @"check('PNG POST to native storage',png&&png.bytes>32);const imported=await bridge('importExport',{id:png.id});"
    @"check('render imported through native mock',imported.layer===91);await AureaStudio.save();"
    @"const saved=await bridge('exports');check('native project backup',saved.some(x=>x.name.endsWith('.ecproj')));"
    @"await AureaStudio.portableProject();check('native portable backup',(await bridge('exports')).some(x=>x.name.endsWith('.aureastudio.zip')));"
    @"return {success:true,checks,engine:effectcraft.info(),userAgent:navigator.userAgent};";
    [web callAsyncJavaScript:script arguments:@{} inFrame:nil inContentWorld:WKContentWorld.pageWorld completionHandler:^(id result,NSError *error){
        if(error){Save(@{@"success":@NO,@"error":error.description,@"detail":error.userInfo.description});return;}
        NSMutableDictionary *report=[result mutableCopy];report[@"mockImports"]=@(imported);report[@"originalAureaTested"]=@NO;
        if(imported!=1){report[@"success"]=@NO;report[@"error"]=@"Unexpected native mock import count";}
        Save(report);
    }];
}
@end
@interface SmokeApp:NSObject<UIApplicationDelegate>
@end
@implementation SmokeApp
- (UISceneConfiguration *)application:(UIApplication *)application configurationForConnectingSceneSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options {
    (void)application;(void)options;
    UISceneConfiguration *config=[[UISceneConfiguration alloc] initWithName:@"Smoke" sessionRole:session.role];config.delegateClass=SmokeScene.class;return config;
}
@end
int main(int argc,char **argv){@autoreleasepool{return UIApplicationMain(argc,argv,nil,NSStringFromClass(SmokeApp.class));}}
