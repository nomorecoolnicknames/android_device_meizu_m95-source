





















































#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <android/log.h>
#include <sys/system_properties.h>

#define LOG_TAG "m95shim_ssl"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGW(...) __android_log_print(ANDROID_LOG_WARN, LOG_TAG, __VA_ARGS__)

typedef struct ssl_method_st SSL_METHOD;
typedef struct ssl_ctx_st SSL_CTX;
typedef struct ssl_st SSL;
typedef struct bio_st BIO;
typedef struct bio_method_st BIO_METHOD;

/* The Nougat-era method table, as the blob lays it out (OpenSSL 1.0 order). */
struct n_bio_method {
    int type;
    const char *name;
    int (*bwrite)(void *, const char *, int);
    int (*bread)(void *, char *, int);
    int (*bputs)(void *, const char *);
    int (*bgets)(void *, char *, int);
    long (*ctrl)(void *, int, long, void *);
    int (*create)(void *);
    int (*destroy)(void *);
    long (*callback_ctrl)(void *, int, void *);
};

static void *next(const char *name) {
    void *fn = dlsym(RTLD_NEXT, name);
    if (fn == NULL) LOGW("%s not found after the shim", name);
    return fn;
}

const SSL_METHOD *SSLv3_client_method(void) {
    const SSL_METHOD *(*fn)(void) = next("TLS_client_method");
    return fn ? fn() : NULL;
}

const SSL_METHOD *SSLv3_server_method(void) {
    const SSL_METHOD *(*fn)(void) = next("TLS_server_method");
    return fn ? fn() : NULL;
}

int SSL_CTX_set_cipher_list(SSL_CTX *ctx, const char *str) {
    int (*real)(SSL_CTX *, const char *) = next("SSL_CTX_set_cipher_list");
    if (real == NULL || str == NULL) return 0;
    if (real(ctx, str)) return 1;

    void (*clear)(void) = next("ERR_clear_error");
    size_t len = strlen(str);
    char *copy = malloc(len + 1), *kept = malloc(len + 1);
    if (copy == NULL || kept == NULL) {
        free(copy);
        free(kept);
        return 0;
    }
    memcpy(copy, str, len + 1);
    kept[0] = '\0';
    int dropped = 0;
    char *save = NULL;
    for (char *tok = strtok_r(copy, ":, ", &save); tok; tok = strtok_r(NULL, ":, ", &save)) {
        if (real(ctx, tok)) {
            if (kept[0]) strcat(kept, ":");
            strcat(kept, tok);
        } else {
            ++dropped;
        }
    }
    if (clear) clear();
    int ok = kept[0] ? real(ctx, kept) : real(ctx, "ALL");
    LOGI("cipher list: %d unknown name(s) dropped, using \"%s\" (%s)", dropped,
         kept[0] ? kept : "ALL", ok ? "ok" : "failed");
    free(copy);
    free(kept);
    return ok;
}

static int log_failure(SSL *ssl, int ret, const char *what) {
    if (ret > 0) return ret;
    int (*get_error)(const SSL *, int) = next("SSL_get_error");
    unsigned long (*peek)(void) = next("ERR_peek_error");
    char *(*text)(unsigned long, char *) = next("ERR_error_string");
    int err = get_error ? get_error(ssl, ret) : -1;
    /* 2 and 3 are WANT_READ / WANT_WRITE: a non-blocking socket, not an error. */
    if (err != 2 && err != 3) {
        char buf[256] = "";
        unsigned long code = peek ? peek() : 0;
        if (text && code) text(code, buf);
        LOGW("%s -> %d, SSL_get_error %d, %s", what, ret, err, code ? buf : "no queued error");
    }
    return ret;
}

static void pin_host(SSL *ssl);

int SSL_do_handshake(SSL *ssl) {
    int (*real)(SSL *) = next("SSL_do_handshake");
    if (real == NULL) return -1;
    pin_host(ssl);
    return log_failure(ssl, real(ssl), "SSL_do_handshake");
}

int SSL_connect(SSL *ssl) {
    int (*real)(SSL *) = next("SSL_connect");
    if (real == NULL) return -1;
    pin_host(ssl);
    return log_failure(ssl, real(ssl), "SSL_connect");
}

/* ---- BIO adapter for Nougat-layout custom BIO methods ---------------------- */

#define SHADOW_BYTES 128            /* larger than any 2016 struct bio_st */
#define BIO_FLAGS_RWS_RETRY 0x0f    /* READ|WRITE|IO_SPECIAL|SHOULD_RETRY */

struct adapter {
    const struct n_bio_method *blob;
    BIO_METHOD *ours;
};

static struct adapter adapters[4];
static int n_adapters;

static void *(*p_get_data)(BIO *);
static int (*p_test_flags)(const BIO *, int);
static void (*p_set_flags)(BIO *, int);
static void (*p_clear_retry)(BIO *);

static const struct n_bio_method *blob_of(BIO *bio, void **shadow) {
    *shadow = p_get_data ? p_get_data(bio) : NULL;
    return *shadow ? *(const struct n_bio_method **)((char *)*shadow + SHADOW_BYTES) : NULL;
}

/* Flags the blob set on the shadow (with this BoringSSL's helpers, so at its
 * offsets) are copied to the real BIO the library looks at. */
static void sync_flags(BIO *bio, void *shadow) {
    p_clear_retry(bio);
    int f = p_test_flags((BIO *)shadow, BIO_FLAGS_RWS_RETRY);
    if (f) p_set_flags(bio, f);
}

static int ad_write(BIO *bio, const char *buf, int len) {
    void *sh;
    const struct n_bio_method *m = blob_of(bio, &sh);
    if (!m || !m->bwrite) return -1;
    int r = m->bwrite(sh, buf, len);
    sync_flags(bio, sh);
    return r;
}

static int ad_read(BIO *bio, char *buf, int len) {
    void *sh;
    const struct n_bio_method *m = blob_of(bio, &sh);
    if (!m || !m->bread) return -1;
    int r = m->bread(sh, buf, len);
    sync_flags(bio, sh);
    return r;
}

static long ad_ctrl(BIO *bio, int cmd, long larg, void *parg) {
    void *sh;
    const struct n_bio_method *m = blob_of(bio, &sh);
    return (m && m->ctrl) ? m->ctrl(sh, cmd, larg, parg) : 0;
}

static int ad_create(BIO *bio) {
    (void)bio;  /* the shadow is attached in BIO_new, once the blob is known */
    return 1;
}

static int ad_destroy(BIO *bio) {
    void *sh;
    const struct n_bio_method *m = blob_of(bio, &sh);
    if (sh) {
        if (m && m->destroy) m->destroy(sh);
        free(sh);
    }
    return 1;
}

static int from_libcrypto(const void *p) {
    Dl_info info;
    return dladdr(p, &info) && info.dli_fname && strstr(info.dli_fname, "libcrypto");
}

BIO *BIO_new(const BIO_METHOD *method) {
    BIO *(*real)(const BIO_METHOD *) = next("BIO_new");
    if (real == NULL) return NULL;
    if (method == NULL || from_libcrypto(method)) return real(method);

    const struct n_bio_method *blob = (const struct n_bio_method *)method;
    BIO_METHOD *(*meth_new)(int, const char *) = next("BIO_meth_new");
    int (*set_write)(BIO_METHOD *, int (*)(BIO *, const char *, int)) = next("BIO_meth_set_write");
    int (*set_read)(BIO_METHOD *, int (*)(BIO *, char *, int)) = next("BIO_meth_set_read");
    int (*set_ctrl)(BIO_METHOD *, long (*)(BIO *, int, long, void *)) = next("BIO_meth_set_ctrl");
    int (*set_create)(BIO_METHOD *, int (*)(BIO *)) = next("BIO_meth_set_create");
    int (*set_destroy)(BIO_METHOD *, int (*)(BIO *)) = next("BIO_meth_set_destroy");
    void (*set_data)(BIO *, void *) = next("BIO_set_data");
    void (*set_init)(BIO *, int) = next("BIO_set_init");
    p_get_data = next("BIO_get_data");
    p_test_flags = next("BIO_test_flags");
    p_set_flags = next("BIO_set_flags");
    p_clear_retry = next("BIO_clear_retry_flags");
    if (!meth_new || !set_write || !set_read || !set_ctrl || !set_create || !set_destroy ||
        !set_data || !set_init || !p_get_data || !p_test_flags || !p_set_flags || !p_clear_retry)
        return real(method);

    BIO_METHOD *ours = NULL;
    for (int i = 0; i < n_adapters; ++i)
        if (adapters[i].blob == blob) ours = adapters[i].ours;
    if (ours == NULL && n_adapters < (int)(sizeof(adapters) / sizeof(adapters[0]))) {
        ours = meth_new(blob->type, blob->name);
        if (ours) {
            set_write(ours, ad_write);
            set_read(ours, ad_read);
            set_ctrl(ours, ad_ctrl);
            set_create(ours, ad_create);
            set_destroy(ours, ad_destroy);
            adapters[n_adapters].blob = blob;
            adapters[n_adapters].ours = ours;
            ++n_adapters;
            LOGI("adapting Nougat-layout BIO_METHOD %p (\"%s\")", (const void *)blob,
                 blob->name ? blob->name : "");
        }
    }
    if (ours == NULL) return real(method);

    BIO *bio = real(ours);
    if (bio == NULL) return NULL;
    /* Shadow: what the blob sees as its BIO, plus the blob method pointer
     * parked after it, out of reach of the 2016 layout. */
    char *sh = calloc(1, SHADOW_BYTES + sizeof(void *));
    if (sh == NULL) return bio;
    *(const struct n_bio_method **)(sh + SHADOW_BYTES) = blob;
    *(const void **)sh = blob;      /* bio->method in the blob's own layout */
    set_data(bio, sh);
    if (blob->create) blob->create(sh);
    set_init(bio, 1);
    return bio;
}

/* ---- Server authentication against the system trust store -------------------- */

#define SYSTEM_CA_DIR "/system/etc/security/cacerts"
#define SSL_VERIFY_PEER_ 0x01
#define SSL_VERIFY_FAIL_IF_NO_PEER_CERT_ 0x02

static int verify_enabled(void) {
    char v[PROP_VALUE_MAX] = "";
    __system_property_get("persist.vendor.m95.supl_verify", v);
    return strcmp(v, "0") != 0;
}

static SSL_CTX *armed[8];
static int n_armed;

static void arm(SSL_CTX *ctx) {
    for (int i = 0; i < n_armed; ++i)
        if (armed[i] == ctx) return;
    void (*set_verify)(SSL_CTX *, int, void *) = next("SSL_CTX_set_verify");
    int (*load)(SSL_CTX *, const char *, const char *) = next("SSL_CTX_load_verify_locations");
    if (!set_verify || !load) return;
    int ok = load(ctx, NULL, SYSTEM_CA_DIR);
    set_verify(ctx, SSL_VERIFY_PEER_ | SSL_VERIFY_FAIL_IF_NO_PEER_CERT_, NULL);
    LOGI("ctx %p: verifying servers against %s (%s)", (void *)ctx, SYSTEM_CA_DIR,
         ok ? "loaded" : "load failed");
    if (n_armed < (int)(sizeof(armed) / sizeof(armed[0]))) armed[n_armed++] = ctx;
}

SSL *SSL_new(SSL_CTX *ctx) {
    SSL *(*real)(SSL_CTX *) = next("SSL_new");
    if (real == NULL) return NULL;
    if (ctx && verify_enabled()) arm(ctx);
    return real(ctx);
}

void SSL_CTX_set_verify(SSL_CTX *ctx, int mode, void *cb) {
    void (*real)(SSL_CTX *, int, void *) = next("SSL_CTX_set_verify");
    if (real == NULL) return;
    if (verify_enabled()) {
        LOGI("ignoring SSL_CTX_set_verify(mode %d) from the blob", mode);
        return;
    }
    real(ctx, mode, cb);
}

void SSL_CTX_set_cert_verify_callback(SSL_CTX *ctx, void *cb, void *arg) {
    void (*real)(SSL_CTX *, void *, void *) = next("SSL_CTX_set_cert_verify_callback");
    if (real == NULL) return;
    if (verify_enabled()) {
        LOGI("ignoring the blob's certificate verify callback");
        return;
    }
    real(ctx, cb, arg);
}

int SSL_set_tlsext_host_name(SSL *ssl, const char *name) {
    int (*real)(SSL *, const char *) = next("SSL_set_tlsext_host_name");
    if (real == NULL) return 0;
    int ret = real(ssl, name);
    if (ret && name && verify_enabled()) {
        void *(*param)(SSL *) = next("SSL_get0_param");
        int (*set_host)(void *, const char *, size_t) = next("X509_VERIFY_PARAM_set1_host");
        if (param && set_host && set_host(param(ssl), name, strlen(name)))
            LOGI("certificate must match %s", name);
    }
    return ret;
}

/* addr="..." of <cur_supl_profile> in the daemon's profile file, or "". */
static void supl_host(char *out, size_t len) {
    static const char *files[] = {"/data/agps_supl/agps_profiles_conf2.xml",
                                  "/vendor/etc/agps_profiles_conf2.xml"};
    out[0] = '\0';
    for (size_t f = 0; f < sizeof(files) / sizeof(files[0]) && !out[0]; ++f) {
        FILE *fp = fopen(files[f], "re");
        if (fp == NULL) continue;
        static char buf[65536];
        size_t n = fread(buf, 1, sizeof(buf) - 1, fp);
        fclose(fp);
        buf[n] = '\0';
        char *p = strstr(buf, "<cur_supl_profile");
        char *a = p ? strstr(p, "addr=\"") : NULL;
        char *end = p ? strstr(p, "/>") : NULL;
        if (a && (!end || a < end)) {
            a += 6;
            char *q = strchr(a, '"');
            if (q && (size_t)(q - a) < len) {
                memcpy(out, a, q - a);
                out[q - a] = '\0';
            }
        }
    }
}

static void pin_host(SSL *ssl) {
    if (!verify_enabled()) return;
    const char *(*servername)(const SSL *, int) = next("SSL_get_servername");
    if (servername && servername(ssl, 0 /* TLSEXT_NAMETYPE_host_name */)) return;
    char host[256];
    supl_host(host, sizeof(host));
    if (!host[0]) {
        LOGW("no cur_supl_profile addr found; host name not pinned");
        return;
    }
    int (*sni)(SSL *, const char *) = next("SSL_set_tlsext_host_name");
    void *(*param)(SSL *) = next("SSL_get0_param");
    int (*set_host)(void *, const char *, size_t) = next("X509_VERIFY_PARAM_set1_host");
    if (sni) sni(ssl, host);
    if (param && set_host && set_host(param(ssl), host, strlen(host)))
        LOGI("SNI and certificate name pinned to %s", host);
}
