// SPDX-License-Identifier: MIT
#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import "AUServer.h"
#import "AUEngineAccess.h"

typedef void(^AUReply)(id _Nullable, NSString * _Nullable);
static const NSInteger AUButtonTag=0x41554352;
static AUServer *AUSharedServer;
static NSURL *AUDocuments(void) { return [NSFileManager.defaultManager URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].firstObject; }
static void AUAlert(UIViewController *vc,NSString *title,NSString *message) {
    if(!vc.view.window)return;
    UIAlertController *alert=[UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"확인" style:UIAlertActionStyleDefault handler:nil]];
    [vc presentViewController:alert animated:YES completion:nil];
}
@interface AUStudioController : UIViewController <WKNavigationDelegate,WKUIDelegate,WKScriptMessageHandlerWithReply,UIDocumentPickerDelegate,WKDownloadDelegate>
@property(nonatomic,strong) WKWebView *web;
@property(nonatomic,strong) AUServer *server;
@property(nonatomic,copy) AUReply pickerReply;
@property(nonatomic,strong) NSMapTable<WKDownload *,NSURL *> *downloads;
@property(nonatomic,weak) UIButton *launcher;
@property(nonatomic) BOOL closing;
@end
// Break the WKUserContentController -> controller -> webview ownership cycle.
@interface AUWeakReplyHandler : NSObject <WKScriptMessageHandlerWithReply>
@property(nonatomic,weak) id<WKScriptMessageHandlerWithReply> target;
@end
@implementation AUWeakReplyHandler
- (void)userContentController:(WKUserContentController *)controller didReceiveScriptMessage:(WKScriptMessage *)message replyHandler:(void (^)(id,NSString *))replyHandler {
    id<WKScriptMessageHandlerWithReply> target=self.target;
    if(target)[target userContentController:controller didReceiveScriptMessage:message replyHandler:replyHandler];
    else replyHandler(nil,@"Studio has closed.");
}
@end
@implementation AUStudioController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title=@"Studio · EffectCraft";
    self.view.backgroundColor=UIColor.systemBackgroundColor;
    self.overrideUserInterfaceStyle=UIUserInterfaceStyleDark;
    self.navigationItem.leftBarButtonItem=[[UIBarButtonItem alloc] initWithTitle:@"Aurea로" style:UIBarButtonItemStylePlain target:self action:@selector(closeStudio)];
    self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"folder"] style:UIBarButtonItemStylePlain target:self action:@selector(showSavedFiles)];
    self.navigationItem.rightBarButtonItem.accessibilityLabel=@"Studio 보관함";
    self.downloads=[NSMapTable strongToStrongObjectsMapTable];
    NSError *error=nil;
    if(!AUSharedServer) {
        NSURL *root=[NSBundle.mainBundle.bundleURL URLByAppendingPathComponent:@"AureaCraft"];
        AUSharedServer=[[AUServer alloc] initWithRoot:root storage:[[AUDocuments() URLByAppendingPathComponent:@"AureaStudio"] URLByAppendingPathComponent:@"Exports"]];
    }
    self.server=AUSharedServer;
    if(![self.server start:&error]) {
        UILabel *label=[[UILabel alloc] initWithFrame:self.view.bounds]; label.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight; label.textAlignment=NSTextAlignmentCenter; label.numberOfLines=0; label.text=error.localizedDescription; [self.view addSubview:label]; return;
    }
    WKWebViewConfiguration *config=[WKWebViewConfiguration new];
    config.websiteDataStore=WKWebsiteDataStore.defaultDataStore;
    config.allowsInlineMediaPlayback=YES;
    config.mediaTypesRequiringUserActionForPlayback=WKAudiovisualMediaTypeAudio;
    config.preferences.javaScriptCanOpenWindowsAutomatically=NO;
    AUWeakReplyHandler *handler=[AUWeakReplyHandler new];handler.target=self;
    [config.userContentController addScriptMessageHandler:handler contentWorld:WKContentWorld.pageWorld name:@"aureaStudio"];
    self.web=[[WKWebView alloc] initWithFrame:CGRectZero configuration:config];
    self.web.navigationDelegate=self; self.web.UIDelegate=self;
    self.web.opaque=NO; self.web.backgroundColor=UIColor.systemBackgroundColor;
    self.web.scrollView.bounces=NO; self.web.scrollView.contentInsetAdjustmentBehavior=UIScrollViewContentInsetAdjustmentNever;
    self.web.translatesAutoresizingMaskIntoConstraints=NO;
    [self.view addSubview:self.web];
    [NSLayoutConstraint activateConstraints:@[[self.web.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],[self.web.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor],[self.web.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],[self.web.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor]]];
    NSString *suffix=@"studio.html?nosw&storage=indexeddb&frameworkers=1&nogpuworkers";
    [self.web loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:suffix relativeToURL:self.server.baseURL]]];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(backgroundNotification:) name:UIApplicationDidEnterBackgroundNotification object:nil];
}
- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    if(self.isBeingDismissed || self.navigationController.isBeingDismissed) self.launcher.hidden=NO;
}
- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
    [self.web.configuration.userContentController removeScriptMessageHandlerForName:@"aureaStudio" contentWorld:WKContentWorld.pageWorld];
}
- (void)backgroundNotification:(NSNotification *)notification {
    (void)notification;
    [self.web evaluateJavaScript:@"window.AureaStudio?.backgroundSave?.()" completionHandler:nil];
}
- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    [self.web evaluateJavaScript:@"window.AureaStudio?.memoryWarning?.()" completionHandler:nil];
}
- (void)finishClose {
    [self.web.configuration.userContentController removeScriptMessageHandlerForName:@"aureaStudio" contentWorld:WKContentWorld.pageWorld];
    [self.web stopLoading]; self.web.navigationDelegate=nil; self.web.UIDelegate=nil;
    self.launcher.hidden=NO;
    [self dismissViewControllerAnimated:YES completion:nil];
}
- (void)closeStudio {
    if(self.closing)return;
    self.closing=YES; self.navigationItem.leftBarButtonItem.enabled=NO;
    if(!self.web) { [self finishClose];return; }
    __weak AUStudioController *weakSelf=self;
    [self.web callAsyncJavaScript:@"if(window.AureaStudio) return await window.AureaStudio.flushForClose(); return {ready:false};" arguments:@{} inFrame:nil inContentWorld:WKContentWorld.pageWorld completionHandler:^(id result,NSError *error) {
        AUStudioController *strong=weakSelf; if(!strong || !strong.closing)return;
        if(!error) { [strong finishClose]; return; }
        strong.closing=NO; strong.navigationItem.leftBarButtonItem.enabled=YES;
        [strong showCloseWarning];
    }];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,12*NSEC_PER_SEC),dispatch_get_main_queue(),^{
        AUStudioController *strong=weakSelf;
        if(strong.closing && strong.view.window) {strong.closing=NO;strong.navigationItem.leftBarButtonItem.enabled=YES;[strong showCloseWarning];}
    });
}
- (void)showCloseWarning {
    if(self.presentedViewController)return;
    UIAlertController *alert=[UIAlertController alertControllerWithTitle:@"저장 완료를 확인하지 못했습니다" message:@"Studio에 남아 저장 상태를 확인하는 것이 안전합니다. 저장하지 않고 닫으면 최근 변경을 잃을 수 있습니다." preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Studio에 남기" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"저장하지 않고 닫기" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *a){[self finishClose];}]];
    [self presentViewController:alert animated:YES completion:nil];
}
- (BOOL)allowedBlob:(NSURL *)url {
    NSString *prefix=[NSString stringWithFormat:@"blob:http://127.0.0.1:%hu/",self.server.port];
    return [url.absoluteString hasPrefix:prefix];
}
- (void)webView:(WKWebView *)webView decidePolicyForNavigationAction:(WKNavigationAction *)action decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler {
    NSURL *url=action.request.URL;
    BOOL local=[self.server isLocalURL:url] || [self allowedBlob:url];
    if(action.shouldPerformDownload && local) {decisionHandler(WKNavigationActionPolicyDownload);return;}
    if([self.server isLocalURL:url] || [url.absoluteString isEqualToString:@"about:blank"]) {decisionHandler(WKNavigationActionPolicyAllow);return;}
    decisionHandler(WKNavigationActionPolicyCancel);
    if(action.navigationType==WKNavigationTypeLinkActivated) AUAlert(self,@"외부 페이지는 열지 않았습니다",@"Studio는 앱에 포함된 오프라인 편집기입니다. 외부 링크는 이 작업공간에서 열지 않습니다.");
}
- (void)webView:(WKWebView *)webView decidePolicyForNavigationResponse:(WKNavigationResponse *)response decisionHandler:(void (^)(WKNavigationResponsePolicy))decisionHandler {
    decisionHandler(response.canShowMIMEType?WKNavigationResponsePolicyAllow:WKNavigationResponsePolicyDownload);
}
- (WKWebView *)webView:(WKWebView *)webView createWebViewWithConfiguration:(WKWebViewConfiguration *)configuration forNavigationAction:(WKNavigationAction *)action windowFeatures:(WKWindowFeatures *)features {
    if([self.server isLocalURL:action.request.URL])[webView loadRequest:action.request];return nil;
}
- (void)webView:(WKWebView *)webView didFailProvisionalNavigation:(WKNavigation *)navigation withError:(NSError *)error {
    if(error.code!=NSURLErrorCancelled) AUAlert(self,@"Studio를 열지 못했습니다",error.localizedDescription);
}
- (void)webViewWebContentProcessDidTerminate:(WKWebView *)webView {
    UIAlertController *alert=[UIAlertController alertControllerWithTitle:@"편집 프로세스가 종료되었습니다" message:@"기기 메모리 부족 또는 WebKit 오류일 수 있습니다. 다시 열면 마지막 자동 저장본을 복구합니다. 저장되지 않은 작업은 복구되지 않을 수 있습니다." preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Aurea로" style:UIAlertActionStyleCancel handler:^(__unused UIAlertAction *a){[self finishClose];}]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Studio 다시 열기" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a){[webView reload];}]];
    if(!self.presentedViewController)[self presentViewController:alert animated:YES completion:nil];
}
- (void)userContentController:(WKUserContentController *)controller didReceiveScriptMessage:(WKScriptMessage *)message replyHandler:(void (^)(id,NSString *))replyHandler {
    WKSecurityOrigin *origin=message.frameInfo.securityOrigin;
    if(!message.frameInfo.isMainFrame || ![origin.protocol isEqualToString:@"http"] || ![origin.host isEqualToString:@"127.0.0.1"] || origin.port!=self.server.port || ![self.server isLocalURL:message.frameInfo.request.URL] || ![message.body isKindOfClass:NSDictionary.class]) {replyHandler(nil,@"Untrusted bridge request.");return;}
    NSDictionary *body=message.body; NSString *action=body[@"action"];
    if(![action isKindOfClass:NSString.class]) {replyHandler(nil,@"Missing action.");return;}
    if([action isEqualToString:@"status"]) {replyHandler([AUEngineAccess status],nil);return;}
    if([action isEqualToString:@"exports"]) {replyHandler(self.server.exports,nil);return;}
    if([action isEqualToString:@"selectedMedia"]) {
        NSError *error=nil; NSArray<NSURL *> *urls=[AUEngineAccess selectedMedia:&error];
        if(error) {replyHandler(nil,error.localizedDescription);return;}
        NSMutableArray *result=[NSMutableArray array];
        for(NSURL *url in urls) {NSDictionary *item=[self.server registerInput:url error:&error];if(!item){replyHandler(nil,error.localizedDescription);return;}[result addObject:item];}
        replyHandler(result,nil);return;
    }
    if([action isEqualToString:@"pickFiles"]) {
        if(self.pickerReply || self.presentedViewController){replyHandler(nil,@"Another dialog is open.");return;}
        self.pickerReply=replyHandler;
        UIDocumentPickerViewController *picker=[[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeItem] asCopy:YES];
        picker.delegate=self; picker.allowsMultipleSelection=YES;
        [self presentViewController:picker animated:YES completion:nil];return;
    }
    NSString *identifier=body[@"id"];
    if(![identifier isKindOfClass:NSString.class]) {replyHandler(nil,@"Missing saved-file identifier.");return;}
    NSURL *url=[self.server exportURL:identifier];
    if(!url) {replyHandler(nil,@"Saved file no longer exists.");return;}
    if([action isEqualToString:@"openSaved"]) {
        NSError *error=nil;NSDictionary *registered=[self.server registerInput:url error:&error];replyHandler(registered,error.localizedDescription);return;
    }
    if([action isEqualToString:@"importExport"]) {
        NSError *error=nil;NSNumber *layer=[AUEngineAccess importMedia:url error:&error];
        replyHandler(layer?@{@"layer":layer,@"name":url.lastPathComponent}:nil,error.localizedDescription);return;
    }
    if([action isEqualToString:@"shareExport"]) {
        if(self.presentedViewController){replyHandler(nil,@"Another dialog is open.");return;}
        [self share:url];replyHandler(@{@"presented":@YES},nil);return;
    }
    replyHandler(nil,@"Unsupported bridge action.");
}
- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller {
    AUReply reply=self.pickerReply;self.pickerReply=nil;if(reply)reply(@[],nil);
}
- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    AUReply reply=self.pickerReply;self.pickerReply=nil;if(!reply)return;
    if(urls.count>8){reply(nil,@"한 번에 최대 8개 파일을 가져올 수 있습니다.");return;}
    AUServer *server=self.server;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{
        @autoreleasepool {
            NSError *error=nil;NSMutableArray *results=[NSMutableArray array];
            NSURL *cache=[NSFileManager.defaultManager URLsForDirectory:NSCachesDirectory inDomains:NSUserDomainMask].firstObject;
            NSURL *folder=[cache URLByAppendingPathComponent:@"AureaStudioImports"];
            [NSFileManager.defaultManager createDirectoryAtURL:folder withIntermediateDirectories:YES attributes:nil error:&error];
            for(NSURL *url in urls) {
                if(error)break;
                BOOL scope=[url startAccessingSecurityScopedResource];
                NSNumber *size=nil;[url getResourceValue:&size forKey:NSURLFileSizeKey error:&error];
                if(!error && size.unsignedLongLongValue>256ull*1024*1024) error=[NSError errorWithDomain:@"AureaStudio" code:2 userInfo:@{NSLocalizedDescriptionKey:@"파일 하나의 최대 크기는 256 MiB입니다."}];
                NSURL *copy=[folder URLByAppendingPathComponent:[NSString stringWithFormat:@"%@-%@",[NSUUID.UUID.UUIDString substringToIndex:8],url.lastPathComponent]];
                if(!error && [NSFileManager.defaultManager copyItemAtURL:url toURL:copy error:&error]) {
                    NSDictionary *item=[server registerInput:copy error:&error];
                    if(item) {NSMutableDictionary *entry=[item mutableCopy];entry[@"name"]=url.lastPathComponent;[results addObject:entry];}
                }
                if(scope)[url stopAccessingSecurityScopedResource];
            }
            dispatch_async(dispatch_get_main_queue(),^{reply(error?nil:results,error.localizedDescription);});
        }
    });
}
- (void)share:(NSURL *)url {
    UIActivityViewController *sheet=[[UIActivityViewController alloc] initWithActivityItems:@[url] applicationActivities:nil];
    sheet.popoverPresentationController.barButtonItem=self.navigationItem.rightBarButtonItem;
    [self presentViewController:sheet animated:YES completion:nil];
}
- (void)showSavedFiles {
    [self.web evaluateJavaScript:@"window.AureaStudio?.showLibrary?.()" completionHandler:nil];
}
- (void)webView:(WKWebView *)webView navigationAction:(WKNavigationAction *)action didBecomeDownload:(WKDownload *)download {download.delegate=self;}
- (void)webView:(WKWebView *)webView navigationResponse:(WKNavigationResponse *)response didBecomeDownload:(WKDownload *)download {download.delegate=self;}
- (void)download:(WKDownload *)download decideDestinationUsingResponse:(NSURLResponse *)response suggestedFilename:(NSString *)suggested completionHandler:(void (^)(NSURL *))completionHandler {
    if(response.expectedContentLength>256ll*1024*1024) {completionHandler(nil);AUAlert(self,@"파일이 너무 큽니다",@"내보내기 크기를 256 MiB 이하로 줄이세요.");return;}
    NSString *name=suggested.lastPathComponent;
    if(!name.length || [name hasPrefix:@"."] || [name rangeOfCharacterFromSet:NSCharacterSet.controlCharacterSet].location!=NSNotFound)name=@"Studio-export.bin";
    if(name.length>128)name=[NSString stringWithFormat:@"Studio-export.%@",name.pathExtension];
    NSURL *url=[self.server.storageURL URLByAppendingPathComponent:[NSString stringWithFormat:@"%@-%@",[NSUUID.UUID.UUIDString substringToIndex:8],name]];
    [self.downloads setObject:url forKey:download];completionHandler(url);
}
- (void)downloadDidFinish:(WKDownload *)download {
    NSURL *url=[self.downloads objectForKey:download];[self.downloads removeObjectForKey:download];if(!url)return;
    NSNumber *size=nil;[url getResourceValue:&size forKey:NSURLFileSizeKey error:nil];
    if(size.unsignedLongLongValue>256ull*1024*1024) {[NSFileManager.defaultManager removeItemAtURL:url error:nil];AUAlert(self,@"파일이 너무 큽니다",@"256 MiB를 넘은 다운로드는 보관하지 않았습니다.");return;}
    NSError *error=nil;NSDictionary *item=[self.server registerExport:url error:&error];
    if(!item){AUAlert(self,@"저장 오류",error.localizedDescription);return;}
    [self.web callAsyncJavaScript:@"window.AureaStudio?.downloaded?.(item);" arguments:@{@"item":item} inFrame:nil inContentWorld:WKContentWorld.pageWorld completionHandler:nil];
}
- (void)download:(WKDownload *)download didFailWithError:(NSError *)error resumeData:(NSData *)resumeData {
    NSURL *url=[self.downloads objectForKey:download];[self.downloads removeObjectForKey:download];
    if(url)[NSFileManager.defaultManager removeItemAtURL:url error:nil];
    AUAlert(self,@"다운로드를 완료하지 못했습니다",error.localizedDescription);
}
- (void)download:(WKDownload *)download willPerformHTTPRedirection:(NSHTTPURLResponse *)response newRequest:(NSURLRequest *)request decisionHandler:(void (^)(WKDownloadRedirectPolicy))decisionHandler {
    decisionHandler([self.server isLocalURL:request.URL]?WKDownloadRedirectPolicyAllow:WKDownloadRedirectPolicyCancel);
}
@end

@interface AUStudioLauncher : NSObject
+ (instancetype)shared;
- (void)attach;
- (void)open:(UIButton *)button;
@end
@implementation AUStudioLauncher
+ (instancetype)shared {static AUStudioLauncher *s;static dispatch_once_t once;dispatch_once(&once,^{s=[self new];});return s;}
- (void)onNotification:(NSNotification *)notification { (void)notification; [self attach]; }
- (void)attach {
    if(!NSThread.isMainThread){dispatch_async(dispatch_get_main_queue(),^{[self attach];});return;}
    [AUEngineAccess install];
    for(UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if(![scene isKindOfClass:UIWindowScene.class] || scene.activationState!=UISceneActivationStateForegroundActive)continue;
        for(UIWindow *window in ((UIWindowScene *)scene).windows) {
            if(!window.isKeyWindow || !window.rootViewController || window.windowLevel!=UIWindowLevelNormal)continue;
            UIButton *existing=[window viewWithTag:AUButtonTag];
            if(existing){[window bringSubviewToFront:existing];continue;}
            UIButton *button=[UIButton buttonWithType:UIButtonTypeSystem];button.tag=AUButtonTag;
            button.frame=CGRectMake(MAX(12,window.bounds.size.width-68),window.safeAreaInsets.top+110,52,52);
            button.autoresizingMask=UIViewAutoresizingFlexibleLeftMargin|UIViewAutoresizingFlexibleBottomMargin;
            button.backgroundColor=[UIColor colorWithRed:0.15 green:0.19 blue:0.24 alpha:0.95];
            [button setTitle:@"EC" forState:UIControlStateNormal];[button setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
            button.titleLabel.font=[UIFont systemFontOfSize:16 weight:UIFontWeightBold];
            button.layer.cornerRadius=26;button.layer.borderWidth=1;button.layer.borderColor=[UIColor colorWithWhite:0.65 alpha:0.5].CGColor;
            button.layer.shadowColor=UIColor.blackColor.CGColor;button.layer.shadowOpacity=0.28;button.layer.shadowRadius=6;button.layer.shadowOffset=CGSizeMake(0,2);
            button.accessibilityLabel=@"EffectCraft Studio 열기";button.accessibilityHint=@"드래그해서 위치를 옮길 수 있습니다.";
            [button addTarget:self action:@selector(open:) forControlEvents:UIControlEventTouchUpInside];
            UIPanGestureRecognizer *pan=[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(drag:)];[button addGestureRecognizer:pan];
            [window addSubview:button];
        }
    }
}
- (void)drag:(UIPanGestureRecognizer *)pan {
    UIView *view=pan.view,*parent=view.superview;if(!parent)return;
    CGPoint delta=[pan translationInView:parent];CGPoint center=CGPointMake(view.center.x+delta.x,view.center.y+delta.y);
    UIEdgeInsets safe=parent.safeAreaInsets;CGFloat r=26;
    center.x=MIN(MAX(center.x,safe.left+r+6),parent.bounds.size.width-safe.right-r-6);
    center.y=MIN(MAX(center.y,safe.top+r+6),parent.bounds.size.height-safe.bottom-r-6);
    view.center=center;[pan setTranslation:CGPointZero inView:parent];
}
- (void)open:(UIButton *)button {
    UIViewController *top=button.window.rootViewController;
    while(top.presentedViewController && !top.presentedViewController.isBeingDismissed)top=top.presentedViewController;
    if([top isKindOfClass:UIAlertController.class] || [top isKindOfClass:UIDocumentPickerViewController.class])return;
    if([top isKindOfClass:UINavigationController.class] && [((UINavigationController *)top).topViewController isKindOfClass:AUStudioController.class])return;
    AUStudioController *vc=[AUStudioController new];vc.launcher=button;
    UINavigationController *navigation=[[UINavigationController alloc] initWithRootViewController:vc];
    navigation.modalPresentationStyle=UIModalPresentationFullScreen;navigation.modalInPresentation=YES;
    button.hidden=YES;[top presentViewController:navigation animated:YES completion:nil];
}
@end
__attribute__((constructor)) static void AUStudioInitialize(void) {
    @autoreleasepool {
        [AUEngineAccess install];
        dispatch_async(dispatch_get_main_queue(),^{
            AUStudioLauncher *launcher=AUStudioLauncher.shared;
            [NSNotificationCenter.defaultCenter addObserver:launcher selector:@selector(onNotification:) name:UIApplicationDidBecomeActiveNotification object:nil];
            [NSNotificationCenter.defaultCenter addObserver:launcher selector:@selector(onNotification:) name:UIWindowDidBecomeKeyNotification object:nil];
            [NSNotificationCenter.defaultCenter addObserver:launcher selector:@selector(onNotification:) name:UISceneDidActivateNotification object:nil];
            [launcher attach];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC),dispatch_get_main_queue(),^{[launcher attach];});
        });
    }
}
