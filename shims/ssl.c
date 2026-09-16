/* libm95shim_ssl — SSLv3_{client,server}_method for Nougat-era MTK blobs.
 *
 * FACT (DT_NEEDED-closure audit 2026-09-06, logcat vendor19 x104):
 *   CANNOT LINK EXECUTABLE "/vendor/bin/mtk_agpsd": cannot locate symbol
 *   "SSLv3_client_method" referenced by "/vendor/bin/mtk_agpsd"
 * Consumers (readelf UND): bin/mtk_agpsd (client+server), lib/libcurl-ss.so
 * and lib64/libcurl-ss.so. BoringSSL dropped SSLv3 entirely (R libssl exports
 * SSLv23_client_method / TLS_client_method only).
 *
 * Both names map to the version-flexible TLS methods, which is what every
 * modern SUPL / AGPS server negotiates anyway; a real SSLv3 handshake would be
 * refused by any server MTK's AGPS client could still reach. Wired to the
 * consumers by vendor-18.1/wire-shims.py (patchelf --add-needed).
 */
#include <openssl/ssl.h>

const SSL_METHOD *SSLv3_client_method(void) { return TLS_client_method(); }
const SSL_METHOD *SSLv3_server_method(void) { return TLS_server_method(); }
