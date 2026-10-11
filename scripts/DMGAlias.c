#include "DMGAlias.h"
#include <CoreServices/CoreServices.h>

static CFDataRef PortableAliasData(AliasHandle alias) {
    enum { aliasHeaderSize = 150, diskImageAliasTag = 20, aliasEndTag = 0xffff };
    const UInt8 *bytes = (const UInt8 *)*alias;
    CFIndex length = GetHandleSize((Handle)alias);
    if (length < aliasHeaderSize || bytes[6] != 0 || bytes[7] != 2) return NULL;
    CFMutableDataRef data = CFDataCreateMutable(kCFAllocatorDefault, length);
    CFDataAppendBytes(data, bytes, aliasHeaderSize);
    CFIndex position = aliasHeaderSize;
    while (position + 4 <= length) {
        UInt16 tag = ((UInt16)bytes[position] << 8) | bytes[position + 1];
        UInt16 size = ((UInt16)bytes[position + 2] << 8) | bytes[position + 3];
        CFIndex recordSize = 4 + size + (size & 1);
        if (position + recordSize > length) { CFRelease(data); return NULL; }
        if (tag != diskImageAliasTag) CFDataAppendBytes(data, bytes + position, recordSize);
        position += recordSize;
        if (tag == aliasEndTag) break;
    }
    CFIndex resultLength = CFDataGetLength(data);
    UInt8 *result = CFDataGetMutableBytePtr(data);
    result[4] = (UInt8)(resultLength >> 8);
    result[5] = (UInt8)resultLength;
    return data;
}

CFDataRef KazeCreateBackgroundAlias(const char *folder, const char *image) {
    FSRef root, target;
    if (FSPathMakeRef((const UInt8 *)folder, &root, NULL) != noErr ||
        FSPathMakeRef((const UInt8 *)image, &target, NULL) != noErr) return NULL;
    AliasHandle alias = NULL;
    if (FSNewAlias(&root, &target, &alias) != noErr || alias == NULL) return NULL;
    CFDataRef data = PortableAliasData(alias);
    DisposeHandle((Handle)alias);
    return data;
}
