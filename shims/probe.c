// libm95probe — dlopen probe (no logd needed).
// A constructor appends one line to /cache/probe.log every time ANY blob
// wired with --add-needed libm95probe.so is loaded. Answers the binary
// question "does the linker reach our blob?" when logd is dead:
//   probe line present  -> linker OK, failure is inside open()/register.
//   probe line absent   -> linker namespace failure (lib missing/symbol).
// /cache is mounted by second-stage mount_all before HAL services start.
#include <fcntl.h>
#include <stdio.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

__attribute__((constructor)) static void m95_probe(void) {
    char comm[64] = "?";
    char self[64];
    snprintf(self, sizeof(self), "/proc/%d/comm", getpid());
    int fd = open(self, O_RDONLY);
    if (fd >= 0) {
        ssize_t n = read(fd, comm, sizeof(comm) - 1);
        if (n > 0) {
            comm[n] = 0;
            char* nl = strchr(comm, '\n');
            if (nl) *nl = 0;
        }
        close(fd);
    }
    char buf[160];
    int len = snprintf(buf, sizeof(buf), "<6>m95probe: pid=%d comm=%s time=%ld\n",
                       getpid(), comm, (long)time(0));
    // Primary: kernel log. Needs no mounts, no dirs, no logd — survives
    // everything except a full power loss (ram_console keeps the tail).
    fd = open("/dev/kmsg", O_WRONLY | O_CLOEXEC);
    if (fd >= 0) {
        (void)!write(fd, buf, len);
        close(fd);
    }
    // Secondary: files (best effort, may not exist yet at HAL start).
    const char* paths[] = {"/cache/probe.log", "/data/misc/probe.log"};
    for (int i = 0; i < 2; i++) {
        fd = open(paths[i], O_WRONLY | O_CREAT | O_APPEND, 0644);
        if (fd >= 0) {
            (void)!write(fd, buf, len);
            close(fd);
        }
    }
}
