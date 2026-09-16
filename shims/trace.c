// libm95trace — LD_PRELOAD tracer for the composer@2.1-service load path.
// Interposes hw_get_module + dlopen, logging every step to a FILE (no logd).
// Usage (TWRP, system+vendor mounted ro):
//   LD_PRELOAD=/cache/libm95trace.so M95TRACE=/cache/hwctrace.log \
//     /vendor/bin/hw/android.hardware.graphics.composer@2.1-service
#define _GNU_SOURCE
#include <dlfcn.h>
#include <fcntl.h>
#include <stdarg.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <stdlib.h>
#include <stdint.h>

static int tfd = -1;

static void tlog(const char* fmt, ...) {
    if (tfd < 0) {
        const char* p = getenv("M95TRACE");
        tfd = open(p ? p : "/cache/hwctrace.log",
                   O_WRONLY | O_CREAT | O_APPEND, 0644);
        if (tfd < 0) return;
    }
    char buf[512];
    va_list ap;
    va_start(ap, fmt);
    int n = vsnprintf(buf, sizeof(buf), fmt, ap);
    va_end(ap);
    if (n > 0) (void)!write(tfd, buf, n);
}

// ---- hw_get_module (libhardware) ----
struct hw_module_t { uint32_t tag; uint16_t version_major, version_minor; char id[16]; char name[16]; char author[16]; void* methods; void* dso; uint32_t reserved[32]; };
struct hw_device_t;
typedef int (*hw_get_module_fn)(const char*, const struct hw_module_t**);

int hw_get_module(const char* id, const struct hw_module_t** module) {
    static hw_get_module_fn real_fn = NULL;
    if (!real_fn) real_fn = (hw_get_module_fn)dlsym(RTLD_NEXT, "hw_get_module");
    tlog("[trace] hw_get_module(id=%s) called\n", id ? id : "(null)");
    int r = real_fn(id, module);
    tlog("[trace] hw_get_module(id=%s) -> %d module=%p\n", id ? id : "(null)", r,
         module ? *module : 0);
    if (r == 0 && module && *module) {
        char name[128] = "?";
        strncpy(name, (*module)->name, sizeof(name) - 1);
        tlog("[trace]   module name=%s id=%s\n", name, (*module)->id);
    }
    return r;
}

// ---- dlopen ----
void* dlopen(const char* filename, int flag) {
    static void* (*real_dlopen)(const char*, int) = NULL;
    if (!real_dlopen)
        real_dlopen = (void* (*)(const char*, int))dlsym(RTLD_NEXT, "dlopen");
    tlog("[trace] dlopen(%s) called\n", filename ? filename : "(null)");
    void* h = real_dlopen(filename, flag);
    if (!h) {
        const char* (*real_err)(void) =
            (const char* (*)(void))dlsym(RTLD_NEXT, "dlerror");
        tlog("[trace] dlopen(%s) FAILED: %s\n", filename ? filename : "(null)",
             real_err ? real_err() : "?");
    } else {
        tlog("[trace] dlopen(%s) OK handle=%p\n", filename ? filename : "(null)", h);
    }
    return h;
}

__attribute__((constructor)) static void tinit(void) {
    tlog("[trace] === tracer loaded pid=%d ===\n", getpid());
}
