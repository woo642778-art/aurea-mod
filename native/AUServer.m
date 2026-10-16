// SPDX-License-Identifier: MIT
#import "AUServer.h"
#import "AUHTTP.h"
#import <arpa/inet.h>
#import <sys/socket.h>
#import <fcntl.h>
#import <unistd.h>
#import <errno.h>

static const uint64_t AUMaxTransfer=256ull*1024*1024;
static NSError *AUError(NSString *message) {
    return [NSError errorWithDomain:@"AureaStudio" code:1 userInfo:@{NSLocalizedDescriptionKey:message}];
}
static BOOL AUSend(int fd,const void *data,size_t length) {
    const uint8_t *p=data;
    while(length) {
        ssize_t n=send(fd,p,length,0);
        if(n<0 && errno==EINTR) continue;
        if(n<=0) return NO;
        p+=n; length-=(size_t)n;
    }
    return YES;
}
static NSString *AUMime(NSString *ext) {
    NSDictionary *types=@{@"wasm":@"application/wasm",@"js":@"text/javascript; charset=utf-8",@"mjs":@"text/javascript; charset=utf-8",@"html":@"text/html; charset=utf-8",@"css":@"text/css; charset=utf-8",@"json":@"application/json",@"ecproj":@"application/json",@"webmanifest":@"application/manifest+json",@"svg":@"image/svg+xml",@"png":@"image/png",@"jpg":@"image/jpeg",@"jpeg":@"image/jpeg",@"webp":@"image/webp",@"gif":@"image/gif",@"mp4":@"video/mp4",@"mov":@"video/quicktime",@"webm":@"video/webm",@"wav":@"audio/wav",@"mp3":@"audio/mpeg",@"m4a":@"audio/mp4",@"txt":@"text/plain; charset=utf-8"};
    return types[ext.lowercaseString]?:@"application/octet-stream";
}
static BOOL AUHead(int fd,int code,NSString *type,uint64_t length,NSDictionary *extra) {
    NSDictionary *labels=@{@200:@"OK",@206:@"Partial Content",@400:@"Bad Request",@403:@"Forbidden",@404:@"Not Found",@405:@"Method Not Allowed",@408:@"Request Timeout",@411:@"Length Required",@413:@"Content Too Large",@416:@"Range Not Satisfiable",@500:@"Internal Server Error",@503:@"Service Unavailable",@507:@"Insufficient Storage"};
    NSMutableString *s=[NSMutableString stringWithFormat:@"HTTP/1.1 %d %@\r\nConnection: close\r\nContent-Type: %@\r\nContent-Length: %llu\r\nX-Content-Type-Options: nosniff\r\nCross-Origin-Opener-Policy: same-origin\r\nCross-Origin-Embedder-Policy: require-corp\r\nCross-Origin-Resource-Policy: same-origin\r\nCache-Control: no-store\r\n",code,labels[@(code)]?:@"Error",type,(unsigned long long)length];
    for(NSString *key in extra) [s appendFormat:@"%@: %@\r\n",key,extra[key]];
    [s appendString:@"\r\n"];
    NSData *d=[s dataUsingEncoding:NSUTF8StringEncoding];
    return AUSend(fd,d.bytes,d.length);
}
static void AUJSON(int fd,int code,id object) {
    NSData *d=[NSJSONSerialization dataWithJSONObject:object options:0 error:nil];
    if(!d) d=[@"{\"error\":\"Serialization failure\"}" dataUsingEncoding:NSUTF8StringEncoding];
    if(AUHead(fd,code,@"application/json; charset=utf-8",d.length,@{})) AUSend(fd,d.bytes,d.length);
}
static BOOL AUFilename(NSString *name) {
    if(![name isKindOfClass:NSString.class] || name.length==0 || name.length>160 || [name hasPrefix:@"."]) return NO;
    if(![name isEqualToString:name.lastPathComponent] || [name rangeOfString:@"\\"].location!=NSNotFound) return NO;
    return [name rangeOfCharacterFromSet:NSCharacterSet.controlCharacterSet].location==NSNotFound;
}

@implementation AUServer {
    NSURL *_root;
    NSURL *_storageURL;
    NSString *_token;
    uint16_t _port;
    int _socket;
    dispatch_source_t _acceptSource;
    dispatch_queue_t _acceptQueue;
    dispatch_semaphore_t _slots;
    NSMutableDictionary<NSString *,NSURL *> *_inputs;
    NSMutableDictionary<NSString *,NSURL *> *_saved;
}
@synthesize storageURL=_storageURL, token=_token, port=_port;
- (instancetype)initWithRoot:(NSURL *)root storage:(NSURL *)storage {
    if((self=[super init])) {
        _root=root.URLByResolvingSymlinksInPath;
        _storageURL=storage.URLByResolvingSymlinksInPath;
        _socket=-1; _token=NSUUID.UUID.UUIDString.lowercaseString;
        _inputs=[NSMutableDictionary dictionary]; _saved=[NSMutableDictionary dictionary];
        _acceptQueue=dispatch_queue_create("aurea.studio.accept",DISPATCH_QUEUE_SERIAL);
        _slots=dispatch_semaphore_create(6);
    }
    return self;
}
- (NSURL *)baseURL { return [NSURL URLWithString:[NSString stringWithFormat:@"http://127.0.0.1:%hu/%@/",_port,_token]]; }
- (BOOL)isLocalURL:(NSURL *)url {
    return [url.scheme isEqualToString:@"http"] && [url.host isEqualToString:@"127.0.0.1"] && url.port.unsignedIntValue==_port && [url.path hasPrefix:[NSString stringWithFormat:@"/%@/",_token]];
}
- (BOOL)start:(NSError **)error {
    if(_socket>=0) return YES;
    NSFileManager *fm=NSFileManager.defaultManager;
    if(![fm createDirectoryAtURL:_storageURL withIntermediateDirectories:YES attributes:nil error:error]) return NO;
    int sock=socket(AF_INET,SOCK_STREAM,0);
    if(sock<0) { if(error)*error=AUError(@"Cannot create the local workspace server."); return NO; }
    int one=1; setsockopt(sock,SOL_SOCKET,SO_REUSEADDR,&one,sizeof(one));
    setsockopt(sock,SOL_SOCKET,SO_NOSIGPIPE,&one,sizeof(one));
    uint16_t preferred=48531;
    NSInteger old=[NSUserDefaults.standardUserDefaults integerForKey:@"AureaStudio.LocalPort"];
    if(old>=1024 && old<=65535) preferred=(uint16_t)old;
    struct sockaddr_in addr={0}; addr.sin_len=sizeof(addr); addr.sin_family=AF_INET; addr.sin_addr.s_addr=htonl(INADDR_LOOPBACK); addr.sin_port=htons(preferred);
    if(bind(sock,(struct sockaddr *)&addr,sizeof(addr))<0) {
        addr.sin_port=0;
        if(bind(sock,(struct sockaddr *)&addr,sizeof(addr))<0) { close(sock); if(error)*error=AUError(@"Cannot bind the local workspace server."); return NO; }
    }
    socklen_t count=sizeof(addr);
    if(getsockname(sock,(struct sockaddr *)&addr,&count)<0 || listen(sock,8)<0 || fcntl(sock,F_SETFL,O_NONBLOCK)<0) {
        close(sock); if(error)*error=AUError(@"Cannot start the local workspace server."); return NO;
    }
    _port=ntohs(addr.sin_port); _socket=sock;
    [NSUserDefaults.standardUserDefaults setInteger:_port forKey:@"AureaStudio.LocalPort"];
    _acceptSource=dispatch_source_create(DISPATCH_SOURCE_TYPE_READ,(uintptr_t)sock,0,_acceptQueue);
    __weak AUServer *weakSelf=self;
    dispatch_source_set_event_handler(_acceptSource,^{
        AUServer *strong=weakSelf; if(!strong) return;
        for(;;) {
            int fd=accept(sock,NULL,NULL);
            if(fd<0) { if(errno==EINTR)continue; break; }
            setsockopt(fd,SOL_SOCKET,SO_NOSIGPIPE,&one,sizeof(one));
            struct timeval tv={20,0};
            setsockopt(fd,SOL_SOCKET,SO_RCVTIMEO,&tv,sizeof(tv));
            setsockopt(fd,SOL_SOCKET,SO_SNDTIMEO,&tv,sizeof(tv));
            int flags=fcntl(fd,F_GETFL,0); if(flags>=0)fcntl(fd,F_SETFL,flags & ~O_NONBLOCK);
            if(dispatch_semaphore_wait(strong->_slots,DISPATCH_TIME_NOW)!=0) { AUJSON(fd,503,@{@"error":@"Workspace is busy. Retry after the current transfer finishes."}); close(fd); continue; }
            dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{
                @autoreleasepool {
                    @try { [strong handle:fd]; }
                    @catch(NSException *e) { (void)e; AUJSON(fd,500,@{@"error":@"Local transfer failed."}); }
                    @finally { close(fd); dispatch_semaphore_signal(strong->_slots); }
                }
            });
        }
    });
    dispatch_source_set_cancel_handler(_acceptSource,^{close(sock);});
    dispatch_resume(_acceptSource);
    NSArray<NSURL *> *existing=[fm contentsOfDirectoryAtURL:_storageURL includingPropertiesForKeys:@[NSURLIsRegularFileKey] options:NSDirectoryEnumerationSkipsHiddenFiles error:nil];
    for(NSURL *url in existing) [self registerExport:url error:nil];
    return YES;
}
- (void)stop {
    if(_acceptSource) { dispatch_source_cancel(_acceptSource); _acceptSource=nil; }
    _socket=-1;
}
- (void)dealloc { [self stop]; }
- (NSDictionary *)registerInput:(NSURL *)url error:(NSError **)error {
    NSURL *resolved=url.URLByResolvingSymlinksInPath;
    NSNumber *regular=nil,*size=nil;
    [resolved getResourceValue:&regular forKey:NSURLIsRegularFileKey error:nil];
    [resolved getResourceValue:&size forKey:NSURLFileSizeKey error:nil];
    if(!resolved.isFileURL || !regular.boolValue || !size || size.unsignedLongLongValue>AUMaxTransfer) {
        if(error)*error=AUError(@"Choose a readable local file no larger than 256 MiB."); return nil;
    }
    NSString *key=NSUUID.UUID.UUIDString.lowercaseString;
    @synchronized(self) {
        if(_inputs.count>=256) { if(error)*error=AUError(@"Restart Aurea before importing more files into Studio."); return nil; }
        _inputs[key]=resolved;
    }
    NSString *leaf=[resolved.lastPathComponent stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet characterSetWithCharactersInString:@"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"]];
    NSString *urlString=[self.baseURL.absoluteString stringByAppendingFormat:@"media/%@/%@",key,leaf?:@"media.bin"];
    return @{@"name":resolved.lastPathComponent,@"url":urlString,@"bytes":size};
}
- (NSDictionary *)registerExport:(NSURL *)url error:(NSError **)error {
    NSURL *resolved=url.URLByResolvingSymlinksInPath;
    NSString *prefix=[_storageURL.path stringByAppendingString:@"/"];
    NSNumber *regular=nil,*size=nil;
    [resolved getResourceValue:&regular forKey:NSURLIsRegularFileKey error:nil];
    [resolved getResourceValue:&size forKey:NSURLFileSizeKey error:nil];
    if(![resolved.path hasPrefix:prefix] || !regular.boolValue || !AUFilename(resolved.lastPathComponent)) {
        if(error)*error=AUError(@"The exported file is not in Studio storage."); return nil;
    }
    NSString *identifier=nil;
    @synchronized(self) {
        identifier=[_saved allKeysForObject:resolved].firstObject;
        if(!identifier) { identifier=NSUUID.UUID.UUIDString.lowercaseString; _saved[identifier]=resolved; }
    }
    return @{@"id":identifier,@"name":resolved.lastPathComponent,@"bytes":size?:@0};
}
- (NSURL *)exportURL:(NSString *)identifier { @synchronized(self) { return _saved[identifier]; } }
- (NSArray<NSDictionary *> *)exports {
    NSMutableArray *items=[NSMutableArray array];
    NSDictionary *copy; @synchronized(self) { copy=[_saved copy]; }
    for(NSString *identifier in copy) {
        NSURL *url=copy[identifier]; NSNumber *size=nil;
        if([url getResourceValue:&size forKey:NSURLFileSizeKey error:nil]) [items addObject:@{@"id":identifier,@"name":url.lastPathComponent,@"bytes":size?:@0}];
    }
    return [items sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a,NSDictionary *b) { return [a[@"name"] localizedStandardCompare:b[@"name"]]; }];
}
- (void)handle:(int)fd {
    NSMutableData *input=[NSMutableData data];
    NSData *separator=[@"\r\n\r\n" dataUsingEncoding:NSASCIIStringEncoding];
    NSRange boundary=NSMakeRange(NSNotFound,0);
    uint8_t buffer[65536];
    while(boundary.location==NSNotFound) {
        ssize_t n=recv(fd,buffer,8192,0);
        if(n<0 && errno==EINTR)continue;
        if(n<=0) { AUJSON(fd,408,@{@"error":@"Incomplete request."}); return; }
        [input appendBytes:buffer length:(NSUInteger)n];
        boundary=[input rangeOfData:separator options:0 range:NSMakeRange(0,input.length)];
        if((boundary.location==NSNotFound && input.length>32768) || (boundary.location!=NSNotFound && boundary.location>32768)) { AUJSON(fd,400,@{@"error":@"Request headers are too large."}); return; }
    }
    NSData *header=[input subdataWithRange:NSMakeRange(0,boundary.location)];
    NSString *text=[[NSString alloc] initWithData:header encoding:NSISOLatin1StringEncoding];
    NSArray<NSString *> *lines=[text componentsSeparatedByString:@"\r\n"];
    NSArray<NSString *> *request=[lines.firstObject componentsSeparatedByString:@" "];
    if(request.count!=3 || ![request[2] isEqualToString:@"HTTP/1.1"]) { AUJSON(fd,400,@{@"error":@"Invalid HTTP request."}); return; }
    NSString *method=request[0], *target=request[1];
    NSMutableDictionary<NSString *,NSString *> *headers=[NSMutableDictionary dictionary];
    for(NSUInteger i=1;i<lines.count;i++) {
        NSRange colon=[lines[i] rangeOfString:@":"];
        if(colon.location==NSNotFound || colon.location==0) { AUJSON(fd,400,@{@"error":@"Malformed header."}); return; }
        NSString *key=[[lines[i] substringToIndex:colon.location] lowercaseString];
        NSString *value=[[lines[i] substringFromIndex:colon.location+1] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        if(headers[key]) { AUJSON(fd,400,@{@"error":@"Duplicate header."}); return; }
        headers[key]=value;
    }
    NSString *host=[NSString stringWithFormat:@"127.0.0.1:%hu",_port];
    NSString *prefix=[NSString stringWithFormat:@"/%@/",_token];
    if(![headers[@"host"] isEqualToString:host] || ![target hasPrefix:prefix]) { AUJSON(fd,403,@{@"error":@"Local workspace access only."}); return; }
    if(headers[@"transfer-encoding"]) { AUJSON(fd,400,@{@"error":@"Chunked requests are not accepted."}); return; }
    NSString *origin=[@"http://" stringByAppendingString:host];
    if(headers[@"origin"] && ![headers[@"origin"] isEqualToString:origin]) { AUJSON(fd,403,@{@"error":@"Origin mismatch."}); return; }
    NSURLComponents *parts=[NSURLComponents componentsWithString:[origin stringByAppendingString:target]];
    if(![parts.percentEncodedPath hasPrefix:prefix]) { AUJSON(fd,400,@{@"error":@"Invalid request URL."}); return; }
    NSString *relative=[[parts.percentEncodedPath substringFromIndex:prefix.length] stringByRemovingPercentEncoding];
    if(!relative || [relative rangeOfCharacterFromSet:NSCharacterSet.controlCharacterSet].location!=NSNotFound || !AUSafeRelativePath(relative.UTF8String)) { AUJSON(fd,400,@{@"error":@"Invalid resource path."}); return; }
    if([method isEqualToString:@"POST"] && [relative isEqualToString:@"api/export"]) {
        if(![headers[@"x-aurea-token"] isEqualToString:_token]) { AUJSON(fd,403,@{@"error":@"Invalid export token."}); return; }
        uint64_t length=0;
        if(!headers[@"content-length"] || !AUParseUnsigned(headers[@"content-length"].UTF8String,&length)) { AUJSON(fd,411,@{@"error":@"A valid Content-Length is required."}); return; }
        if(length==0 || length>AUMaxTransfer) { AUJSON(fd,413,@{@"error":@"Export must be between 1 byte and 256 MiB."}); return; }
        NSString *name=nil;
        for(NSURLQueryItem *item in parts.queryItems) if([item.name isEqualToString:@"name"] && !name) name=item.value;
        if(!AUFilename(name)) { AUJSON(fd,400,@{@"error":@"Invalid export filename."}); return; }
        NSSet *allowed=[NSSet setWithArray:@[@"ecproj",@"json",@"lottie",@"mp4",@"mov",@"m4v",@"m4a",@"aac",@"wav",@"aiff",@"mp3",@"png",@"jpg",@"jpeg",@"webp",@"gif",@"zip",@"webm",@"tiff",@"exr"]];
        if(![allowed containsObject:name.pathExtension.lowercaseString]) { AUJSON(fd,400,@{@"error":@"Unsupported export extension."}); return; }
        NSDictionary *disk=[NSFileManager.defaultManager attributesOfFileSystemForPath:_storageURL.path error:nil];
        if(disk[NSFileSystemFreeSize] && [disk[NSFileSystemFreeSize] unsignedLongLongValue]<length+16*1024*1024) { AUJSON(fd,507,@{@"error":@"Insufficient free storage."}); return; }
        NSString *uuid=NSUUID.UUID.UUIDString.lowercaseString;
        NSURL *temporary=[_storageURL URLByAppendingPathComponent:[@".transfer-" stringByAppendingString:uuid]];
        NSString *finalName=[NSString stringWithFormat:@"%@-%@",[uuid substringToIndex:8],name];
        NSURL *destination=[_storageURL URLByAppendingPathComponent:finalName];
        NSOutputStream *stream=[NSOutputStream outputStreamWithURL:temporary append:NO];
        [stream open];
        uint64_t received=0; BOOL ok=YES;
        NSUInteger bodyStart=boundary.location+4, available=input.length-bodyStart;
        if(available>length) ok=NO;
        const uint8_t *body=(const uint8_t *)input.bytes+bodyStart;
        while(ok && received<available) {
            NSInteger written=[stream write:body+received maxLength:available-(NSUInteger)received];
            if(written<=0) {ok=NO;break;} received+=(uint64_t)written;
        }
        while(ok && received<length) {
            size_t need=(size_t)MIN((uint64_t)sizeof(buffer),length-received);
            ssize_t n=recv(fd,buffer,need,0);
            if(n<0 && errno==EINTR)continue;
            if(n<=0) {ok=NO;break;}
            NSUInteger written=0;
            while(written<(NSUInteger)n) {
                NSInteger step=[stream write:buffer+written maxLength:(NSUInteger)n-written];
                if(step<=0) {ok=NO;break;} written+=(NSUInteger)step;
            }
            received+=(uint64_t)written;
        }
        if(stream.streamError) ok=NO;
        [stream close];
        NSError *moveError=nil;
        if(!ok || received!=length || ![NSFileManager.defaultManager moveItemAtURL:temporary toURL:destination error:&moveError]) {
            [NSFileManager.defaultManager removeItemAtURL:temporary error:nil];
            AUJSON(fd,500,@{@"error":@"Transfer was interrupted; no incomplete export was kept."}); return;
        }
        NSDictionary *result=[self registerExport:destination error:nil];
        AUJSON(fd,200,result?:@{@"error":@"Cannot register the export."}); return;
    }
    if(![method isEqualToString:@"GET"] && ![method isEqualToString:@"HEAD"]) { AUJSON(fd,405,@{@"error":@"Method not allowed."}); return; }
    NSURL *file=nil;
    if([relative hasPrefix:@"media/"]) {
        NSArray *segments=[relative componentsSeparatedByString:@"/"];
        if(segments.count==3) { @synchronized(self) { file=_inputs[segments[1]]; } }
    } else {
        file=[_root URLByAppendingPathComponent:relative].URLByResolvingSymlinksInPath;
        if(![file.path hasPrefix:[_root.path stringByAppendingString:@"/"]]) file=nil;
    }
    NSNumber *regular=nil,*size=nil;
    [file getResourceValue:&regular forKey:NSURLIsRegularFileKey error:nil];
    [file getResourceValue:&size forKey:NSURLFileSizeKey error:nil];
    if(!regular.boolValue || !size) { AUJSON(fd,404,@{@"error":@"Resource not found."}); return; }
    AURange range;
    int code=AUParseRange(headers[@"range"].UTF8String,size.unsignedLongLongValue,&range);
    if(code==416) { AUHead(fd,416,@"text/plain",0,@{@"Content-Range":[NSString stringWithFormat:@"bytes */%@",size]}); return; }
    NSMutableDictionary *extra=[@{@"Accept-Ranges":@"bytes"} mutableCopy];
    if(code==206) extra[@"Content-Range"]=[NSString stringWithFormat:@"bytes %llu-%llu/%@",(unsigned long long)range.start,(unsigned long long)(range.start+range.length-1),size];
    int source=open(file.fileSystemRepresentation,O_RDONLY);
    if(source<0) { AUJSON(fd,404,@{@"error":@"Resource is not readable."}); return; }
    if(lseek(source,(off_t)range.start,SEEK_SET)<0 || !AUHead(fd,code,AUMime(file.pathExtension),range.length,extra)) {close(source);return;}
    if(![method isEqualToString:@"HEAD"]) {
        uint64_t left=range.length;
        while(left) {
            ssize_t n=read(source,buffer,(size_t)MIN((uint64_t)sizeof(buffer),left));
            if(n<0 && errno==EINTR)continue;
            if(n<=0 || !AUSend(fd,buffer,(size_t)n)) break;
            left-=(uint64_t)n;
        }
    }
    close(source);
}
@end
