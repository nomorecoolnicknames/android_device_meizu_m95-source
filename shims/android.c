// android_setsocknetwork() for mtk_agpsd (AGPS/SUPL client) -- the only vendor
// consumer of libandroid's NDK multinetwork API. libandroid is system-only and
// invisible under strict VNDK. Reproduces the fwmark netd's FwmarkServer applies
// for SELECT_NETWORK (netId | explicitlySelected | protectedFromVpn |
// PERMISSION_SYSTEM; system/netd/include/Fwmark.h + Permission.h). The daemon
// runs as user gps and may lack CAP_NET_ADMIN, in which case setsockopt fails
// and this returns -1 exactly like a failed bind -- the caller falls back to
// the default network. Evidence: VNDK_FULL_PREFLIP_BOOT_AUDIT.md.
#include <errno.h>
#include <limits.h>
#include <stdint.h>
#include <sys/socket.h>

typedef uint64_t net_handle_t;
#define NETWORK_UNSPECIFIED 0

static int getnetidfromhandle(net_handle_t handle, unsigned* netid) {
    static const uint32_t k32BitMask = 0xffffffff;
    static const uint32_t kHandleMagic = 0xcafed00d;
    if (handle != NETWORK_UNSPECIFIED && (handle & k32BitMask) != kHandleMagic) {
        return 0;
    }
    if (netid != NULL) {
        *netid = ((handle >> (CHAR_BIT * sizeof(k32BitMask))) & k32BitMask);
    }
    return 1;
}

int android_setsocknetwork(net_handle_t network, int fd) {
    unsigned netid;
    if (!getnetidfromhandle(network, &netid)) {
        errno = EINVAL;
        return -1;
    }
    uint32_t fwmark = (netid & 0xffffu) | 0x000f0000u;
    if (setsockopt(fd, SOL_SOCKET, SO_MARK, &fwmark, sizeof(fwmark)) != 0) {
        return -1;
    }
    return 0;
}
