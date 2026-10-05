// libm95shim_utils — UTF-16/UTF-8 helpers removed from R libutils.
//
// N-era libutils exported strndup16to8/strdup8to16/strnlen16to8/strncpy16to8
// (used by the RIL stack + nvram_agent_binder). R dropped them. Local,
// dependency-free implementations (logic copied from AOSP system/core/libutils).
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
// char16_t is a C++11 builtin; do NOT typedef it.

extern "C" {

size_t strnlen16to8(const char16_t* s, size_t n) {
    size_t r = 0;
    while (n-- > 0 && *s++) r++;
    return r;
}

char* strncpy16to8(char* dest, const char16_t* src, size_t n) {
    char* d = dest;
    while (n-- > 0) {
        char16_t c = *src++;
        *d++ = (c < 0x80) ? (char)c : '?';
    }
    return dest;
}

char* strndup16to8(const char16_t* s, size_t n) {
    n = strnlen16to8(s, n);
    char* r = (char*)malloc(n + 1);
    if (!r) return NULL;
    strncpy16to8(r, s, n);
    r[n] = '\0';
    return r;
}

char16_t* strdup8to16(const char* s, size_t* out_len) {
    size_t n = strlen(s);
    char16_t* r = (char16_t*)malloc((n + 1) * sizeof(char16_t));
    if (!r) return NULL;
    for (size_t i = 0; i < n; i++) r[i] = (char16_t)(unsigned char)s[i];
    r[n] = 0;
    if (out_len) *out_len = n;
    return r;
}

}  // extern "C"

// android_memset16/android_memset32 -- removed from R libcutils (N had them in
// libcutils/arch-arm64/android_memset.S). gralloc.mt6797.so imports both and
// the whole graphics stack (allocator, composer via the FB adapter, SF) dies

// Semantics per the old header: count is in BYTES, must be a multiple of the
// element size, dst aligned to the element size.
extern "C" void android_memset16(uint16_t* dst, uint16_t value, size_t count) {
    count /= sizeof(uint16_t);
    while (count-- > 0) *dst++ = value;
}

extern "C" void android_memset32(uint32_t* dst, uint32_t value, size_t count) {
    count /= sizeof(uint32_t);
    while (count-- > 0) *dst++ = value;
}

// android::PermissionCache::checkCallingPermission -- libpqservice.so (MTK PQ
// client, in the closure of libGLES_mali via libgpu_aux -> libdpframework)
// imports it. R's libbinder exports it only in the system variant; the VNDK
// apex vendor variant that the sphal namespace resolves libbinder.so to has
// no PermissionCache at all, so every system process that loads the GPU
// driver died with "cannot locate symbol ... referenced by libpqservice.so"

// N-era ABI (static, const String16&), no libbinder dependency here.
namespace android {
class String16;
class PermissionCache {
  public:
    static bool checkCallingPermission(const String16& permission);
    static bool checkPermission(const String16& permission, int32_t pid, uint32_t uid);
};
bool PermissionCache::checkCallingPermission(const String16&) {
    return true;
}

// same story as libpqservice above -- under lite the system libbinder provided
// PermissionCache, the VNDK variant has none.
bool PermissionCache::checkPermission(const String16&, int32_t, uint32_t) {
    return true;
}
}  // namespace android

// ---- android::MemoryHeapBase(int fd, size_t size, uint32_t flags, off_t offset)
// N mangled the offset as uint32_t (C1Eijjj on both ABIs: size was uint32 on
// 64-bit too). R (libbinder): 32-bit C1Eijjl, 64-bit C1Eimjl. libmtkcam_cct.so
// (dlopened by libcam_platform.so on the camera HAL's device-enumeration path)
// is the only importer (vendor22: "dlopen failed: cannot locate symbol
// _ZN7android14MemoryHeapBaseC1Eijjj" x68, then CamDeviceManagerImp::
// enumDeviceLocked() SIGSEGV null). Constructors on `this`; manual
// declarations only, resolved from the system libbinder at runtime (lite).
extern "C" {
#ifdef __LP64__
void _ZN7android14MemoryHeapBaseC1Eimjl(void* self, int fd, unsigned long size,
                                        uint32_t flags, long offset);
void _ZN7android14MemoryHeapBaseC1Eijjj(void* self, int fd, uint32_t size,
                                        uint32_t flags, uint32_t offset) {
    _ZN7android14MemoryHeapBaseC1Eimjl(self, fd, size, flags, (long)offset);
}
#else
void _ZN7android14MemoryHeapBaseC1Eijjl(void* self, int fd, uint32_t size,
                                        uint32_t flags, long offset);
void _ZN7android14MemoryHeapBaseC1Eijjj(void* self, int fd, uint32_t size,
                                        uint32_t flags, uint32_t offset) {
    _ZN7android14MemoryHeapBaseC1Eijjl(self, fd, size, flags, (long)offset);
}
#endif
}  // extern "C"
