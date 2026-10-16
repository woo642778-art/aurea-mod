// SPDX-License-Identifier: MIT
#ifndef AUREA_STUDIO_HTTP_H
#define AUREA_STUDIO_HTTP_H
#include <stdint.h>
#include <stdbool.h>
typedef struct { uint64_t start; uint64_t length; } AURange;
int AUParseRange(const char *value, uint64_t size, AURange *out);
bool AUSafeRelativePath(const char *path);
bool AUParseUnsigned(const char *text, uint64_t *out);
#endif
