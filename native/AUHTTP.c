// SPDX-License-Identifier: MIT
#include "AUHTTP.h"
#include <string.h>
#include <stddef.h>
#include <limits.h>
static bool unsigned_part(const char *s, const char *end, uint64_t *out) {
    if (!s || s==end) return false;
    uint64_t value=0;
    for (; s<end; s++) {
        if (*s<'0' || *s>'9') return false;
        unsigned d=(unsigned)(*s-'0');
        if (value>(UINT64_MAX-d)/10) return false;
        value=value*10+d;
    }
    *out=value;
    return true;
}
bool AUParseUnsigned(const char *text, uint64_t *out) {
    return text && out && unsigned_part(text,text+strlen(text),out);
}
int AUParseRange(const char *value, uint64_t size, AURange *out) {
    if (!out) return 416;
    *out=(AURange){0,size};
    if (!value) return 200;
    if (strncmp(value,"bytes=",6)!=0 || size==0) return 416;
    const char *start=value+6, *end=value+strlen(value), *dash=strchr(start,'-');
    if (!dash || strchr(dash+1,'-') || strchr(start,',')) return 416;
    uint64_t a=0,b=0;
    if (dash==start) {
        if (!unsigned_part(dash+1,end,&b) || b==0) return 416;
        if (b>size) b=size;
        *out=(AURange){size-b,b};
    } else {
        if (!unsigned_part(start,dash,&a) || a>=size) return 416;
        if (dash+1==end) b=size-1;
        else if (!unsigned_part(dash+1,end,&b) || b<a) return 416;
        if (b>=size) b=size-1;
        *out=(AURange){a,b-a+1};
    }
    return 206;
}
bool AUSafeRelativePath(const char *path) {
    if (!path || !*path || *path=='/' || *path=='\\') return false;
    const char *part=path;
    for (const char *p=path;;p++) {
        unsigned char c=(unsigned char)*p;
        if ((c && c<32) || c==127 || c=='\\') return false;
        if (c=='/' || c==0) {
            size_t n=(size_t)(p-part);
            if (!n || (n==1 && part[0]=='.') || (n==2 && part[0]=='.' && part[1]=='.')) return false;
            if (!c) return true;
            part=p+1;
        }
    }
}
