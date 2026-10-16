#import <Foundation/Foundation.h>
#import "AUServer.h"
int main(int argc,const char **argv){@autoreleasepool {
    if(argc!=3)return 2;
    AUServer *server=[[AUServer alloc] initWithRoot:[NSURL fileURLWithPath:@(argv[1])] storage:[NSURL fileURLWithPath:@(argv[2])]];
    NSError *error=nil;if(![server start:&error]){fprintf(stderr,"%s\n",error.localizedDescription.UTF8String);return 1;}
    printf("%s\n",server.baseURL.absoluteString.UTF8String);fflush(stdout);
    [[NSRunLoop currentRunLoop] run];return 0;
}}
