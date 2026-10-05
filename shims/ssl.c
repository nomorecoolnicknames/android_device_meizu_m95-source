
#include <openssl/ssl.h>

const SSL_METHOD *SSLv3_client_method(void) { return TLS_client_method(); }
const SSL_METHOD *SSLv3_server_method(void) { return TLS_server_method(); }
