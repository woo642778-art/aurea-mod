#include "AUHTTP.h"
#include <assert.h>
#include <stdio.h>
int main(void) {
    AURange r;
    assert(AUParseRange(NULL, 10, &r)==200 && r.start==0 && r.length==10);
    assert(AUParseRange("bytes=0-3", 10, &r)==206 && r.start==0 && r.length==4);
    assert(AUParseRange("bytes=3-", 10, &r)==206 && r.start==3 && r.length==7);
    assert(AUParseRange("bytes=-3", 10, &r)==206 && r.start==7 && r.length==3);
    assert(AUParseRange("bytes=0-999", 10, &r)==206 && r.length==10);
    assert(AUParseRange("bytes=-999", 10, &r)==206 && r.length==10);
    assert(AUParseRange("bytes=10-", 10, &r)==416);
    assert(AUParseRange("bytes=8-2", 10, &r)==416);
    assert(AUParseRange("bytes=0-1,3-4", 10, &r)==416);
    assert(AUParseRange("bytes=+1-3", 10, &r)==416);
    assert(AUParseRange("bytes=18446744073709551616-", 10, &r)==416);
    assert(AUParseRange("bytes=-0", 10, &r)==416);
    assert(AUParseRange("bytes=0-0", 0, &r)==416);
    assert(AUParseRange(NULL, 0, &r)==200 && r.length==0);
    assert(AUSafeRelativePath("index.html"));
    assert(AUSafeRelativePath("snippets/module/js/host.js"));
    assert(AUSafeRelativePath("media/abc/test file.mp4"));
    assert(!AUSafeRelativePath("../Info.plist"));
    assert(!AUSafeRelativePath("abc/../../Info.plist"));
    assert(!AUSafeRelativePath("/etc/passwd"));
    assert(!AUSafeRelativePath("abc\\x"));
    assert(!AUSafeRelativePath("a/./b"));
    assert(!AUSafeRelativePath("a//b"));
    assert(!AUSafeRelativePath("a/"));
    assert(!AUSafeRelativePath("a\r\nb"));
    assert(!AUSafeRelativePath(""));
    puts("HTTP safety: 26 assertions passed");
    return 0;
}
