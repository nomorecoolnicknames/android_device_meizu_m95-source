/* libnetd_client.so (vendor, ELF32) — setNetworkForSocket for the VoLTE SIP
 * stack.
 *
 * FACT (capture m95-b19-volte-20260925, logcat-all.txt:24262):
 *   CANNOT LINK EXECUTABLE "/vendor/bin/volte_stack": library
 *   "libnetd_client.so" not found: needed by main executable
 * libnetd_client is system-only (system/netd/client/Android.bp: no
 * vendor_available). On 18.1 the vendor namespace reached /system/lib through
 * VNDK-lite; Android 13 has none (system/linkerconfig/main.cc:365-369). With
 * volte_stack dead, init removes its socket, volte_ua gives up connecting to it
 * after 150 retries (api_channel.c:243 ASSERT, exit(-11) = status 245), and
 * volte_imcb, waiting on volte_ua's socket, dies the same way.
 *
 * volte_stack and wfca import exactly one symbol from libnetd_client:
 * setNetworkForSocket (their UND set intersected with the exports of the
 * handset's /system/lib/libnetd_client.so). Every other import of volte_stack
 * resolves in the vendor namespace (VNDK v33 + LLNDK, checked the same way).
 *
 * libandroid_net is LLNDK, and android_setsocknetwork() is exactly
 * setNetworkForSocket() with the netId packed into a net_handle_t and the
 * -errno return turned into -1/errno (frameworks/base/native/android/net.c:
 * 52-65, unpacking in getnetidfromhandle() at 30-43). So this packs the handle
 * the way gethandlefromnetid() (net.c:45-50) does and undoes
 * the errno conversion: the fwmarkd round trip still happens in the system copy
 * of libnetd_client, with the netd-side permission checks of 18.1. SELinux:
 * net_domain(volte_stack) already grants unix_socket_connect(netdomain,
 * fwmarkd, netd) (system/sepolicy/public/net.te:23).
 *
 * libcharon's protectFromVpn is deliberately NOT here: charon is the ePDG/WFC
 * IKE daemon (persist.mtk_epdg_support=0, no service in our rc files) and
 * libandroid_net has no equivalent — a stub would claim a VPN bypass that never
 * happened.
 */
#include <android/multinetwork.h>
#include <errno.h>
#include <stdint.h>

#define NETID_UNSET 0u /* system/netd/include/netid_client.h:24 */

/* Must match kHandleMagic in frameworks/base/native/android/net.c. */
static const uint32_t kHandleMagic = 0xcafed00d;

int setNetworkForSocket(unsigned netId, int socketFd) {
    net_handle_t handle = netId == NETID_UNSET
            ? NETWORK_UNSPECIFIED
            : ((net_handle_t)netId << 32) | kHandleMagic;

    if (android_setsocknetwork(handle, socketFd) == 0)
        return 0;
    return -errno;
}
