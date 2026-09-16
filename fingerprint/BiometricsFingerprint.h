/*
 * Copyright (C) 2017 The Android Open Source Project
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

#ifndef ANDROID_HARDWARE_BIOMETRICS_FINGERPRINT_V2_1_BIOMETRICSFINGERPRINT_H
#define ANDROID_HARDWARE_BIOMETRICS_FINGERPRINT_V2_1_BIOMETRICSFINGERPRINT_H

#include <stddef.h>

#include <log/log.h>
#include <android/log.h>
#include <hardware/hardware.h>
#include <hardware/fingerprint.h>
#include <hidl/MQDescriptor.h>
#include <hidl/Status.h>
#include <string>
#include <vector>
#include <android/hardware/biometrics/fingerprint/2.1/IBiometricsFingerprint.h>

namespace android {
namespace hardware {
namespace biometrics {
namespace fingerprint {
namespace V2_1 {
namespace implementation {

using ::android::hardware::biometrics::fingerprint::V2_1::IBiometricsFingerprint;
using ::android::hardware::biometrics::fingerprint::V2_1::IBiometricsFingerprintClientCallback;
using ::android::hardware::biometrics::fingerprint::V2_1::RequestStatus;
using ::android::hardware::Return;
using ::android::hardware::Void;
using ::android::hardware::hidl_vec;
using ::android::hardware::hidl_string;
using ::android::sp;

/*
 * ---------------------------------------------------------------------------
 * m95: the Goodix module's device structure is 32 bytes LONGER than AOSP's.
 * ---------------------------------------------------------------------------
 *
 * FACT (llvm-objdump of vendor/lib64/hw/fingerprint.default.so, the module's
 * own open() at 0x1608, re-verified on the 18.1 blob copy 2026-09-07):
 *
 *   1640: mov  x0, x21          ; x21 = #272
 *   1644: bl   malloc           ; the whole structure is 0x110 = 272 bytes
 *   ...   str/stur into x22 at offsets
 *         0, 8, 112, 120(=0), 128, 136, 144, 152, 160, 168, 176, 184,
 *         192, 200, 216, 224, 232          (208 is left NULL by the memset)
 *
 * AOSP's fingerprint_device_t is 240 bytes here (hw_device_t is 120 on LP64
 * because hardware.h declares uint64_t reserved[12] under __LP64__), so every
 * member from get_authenticator_id onwards sits 32 bytes further along than
 * <hardware/fingerprint.h> believes.
 *
 * The four inserted members are the vendor methods, and they name themselves:
 * each one logs through __android_log_print with a literal from .rodata
 *
 *   offset 160 -> 0x1A30 "fingerprint_lockout_reset"  (daemon vtable +176)
 *   offset 168 -> 0x1AD0 "fingerprint_lockout"        (daemon vtable +184)
 *   offset 176 -> 0x1B70 "fingerprint_screen_off"     (daemon vtable +200)
 *   offset 184 -> 0x1C10 "fingerprint_screen_on"      (daemon vtable +192)
 *
 * and the standard members identify themselves by shape:
 *   offset 224 -> 0x1E60 is the only one that does __strlen_chk + memcpy of a
 *                 string, i.e. set_active_group(dev, gid, store_path);
 *   offset 232 -> 0x1F50 keeps a 64-bit x1 and a w2, i.e.
 *                 authenticate(dev, operation_id, gid);
 *   offset 128 -> 0x1FF0 is four instructions: str x1,[x0,#120]; ret 0 —
 *                 set_notify, and it stores the callback at 120, which pins
 *                 the notify member (and therefore hw_device_t's size) exactly.
 *
 * Compiled against <hardware/fingerprint.h> this wrapper therefore called
 * cancel whenever it meant authenticate, screen_off whenever it meant
 * enumerate, and lockout_reset whenever it meant get_authenticator_id. That is
 * why matching never captured a frame on LOS 16.0: the daemon received a
 * cancel. Enrolment worked because everything up to post_enroll agrees.
 *
 * Slot 208 (enumerate) is NULL in this blob — the memset leaves it zero and
 * open() never writes it. enumerate() below must not call through it.
 */
typedef struct meizu_fingerprint_device {
    /** 0 .. 119 */
    struct hw_device_t common;

    /* 120 */ fingerprint_notify_t notify;
    /* 128 */ int (*set_notify)(struct meizu_fingerprint_device *dev,
                                fingerprint_notify_t notify);
    /* 136 */ uint64_t (*pre_enroll)(struct meizu_fingerprint_device *dev);
    /* 144 */ int (*enroll)(struct meizu_fingerprint_device *dev,
                            const hw_auth_token_t *hat, uint32_t gid,
                            uint32_t timeout_sec);
    /* 152 */ int (*post_enroll)(struct meizu_fingerprint_device *dev);

    /* --- Meizu/Goodix vendor block, absent from AOSP --- */
    /* 160 */ int (*fingerprint_lockout_reset)(struct meizu_fingerprint_device *dev);
    /* 168 */ int (*fingerprint_lockout)(struct meizu_fingerprint_device *dev);
    /* 176 */ int (*fingerprint_screen_off)(struct meizu_fingerprint_device *dev);
    /* 184 */ int (*fingerprint_screen_on)(struct meizu_fingerprint_device *dev);

    /* 192 */ uint64_t (*get_authenticator_id)(struct meizu_fingerprint_device *dev);
    /* 200 */ int (*cancel)(struct meizu_fingerprint_device *dev);
    /* 208 */ int (*enumerate)(struct meizu_fingerprint_device *dev);   /* NULL here */
    /* 216 */ int (*remove)(struct meizu_fingerprint_device *dev, uint32_t gid,
                            uint32_t fid);
    /* 224 */ int (*set_active_group)(struct meizu_fingerprint_device *dev,
                                      uint32_t gid, const char *store_path);
    /* 232 */ int (*authenticate)(struct meizu_fingerprint_device *dev,
                                  uint64_t operation_id, uint32_t gid);

    /* 240 */ void *reserved[4];
} meizu_fingerprint_device_t;

/*
 * Pin the layout. If the blob is ever replaced by one with a different
 * structure these break the BUILD instead of silently calling the wrong
 * function, which is exactly the failure mode this file exists to fix.
 */
static_assert(sizeof(meizu_fingerprint_device_t) == 272,
              "m95 fingerprint device must match the blob's malloc(0x110)");
static_assert(offsetof(meizu_fingerprint_device_t, notify) == 120,
              "notify must sit where the blob's set_notify writes it");
static_assert(offsetof(meizu_fingerprint_device_t, set_active_group) == 224,
              "set_active_group offset does not match the blob");
static_assert(offsetof(meizu_fingerprint_device_t, authenticate) == 232,
              "authenticate offset does not match the blob");


struct BiometricsFingerprint : public IBiometricsFingerprint {
public:
    BiometricsFingerprint();
    ~BiometricsFingerprint();

    // Method to wrap legacy HAL with BiometricsFingerprint class
    static IBiometricsFingerprint* getInstance();

    // Methods from ::android::hardware::biometrics::fingerprint::V2_1::IBiometricsFingerprint follow.
    Return<uint64_t> setNotify(const sp<IBiometricsFingerprintClientCallback>& clientCallback) override;
    Return<uint64_t> preEnroll() override;
    Return<RequestStatus> enroll(const hidl_array<uint8_t, 69>& hat, uint32_t gid, uint32_t timeoutSec) override;
    Return<RequestStatus> postEnroll() override;
    Return<uint64_t> getAuthenticatorId() override;
    Return<RequestStatus> cancel() override;
    Return<RequestStatus> enumerate() override;
    Return<RequestStatus> remove(uint32_t gid, uint32_t fid) override;
    Return<RequestStatus> setActiveGroup(uint32_t gid, const hidl_string& storePath) override;
    Return<RequestStatus> authenticate(uint64_t operationId, uint32_t gid) override;

private:
    static meizu_fingerprint_device_t* openHal();
    static void notify(const fingerprint_msg_t *msg); /* Static callback for legacy HAL implementation */
    static Return<RequestStatus> ErrorFilter(int32_t error);
    static FingerprintError VendorErrorFilter(int32_t error, int32_t* vendorCode);
    static FingerprintAcquiredInfo VendorAcquiredFilter(int32_t error, int32_t* vendorCode);
    static BiometricsFingerprint* sInstance;

    std::mutex mClientCallbackMutex;
    sp<IBiometricsFingerprintClientCallback> mClientCallback;
    meizu_fingerprint_device_t *mDevice;

    /* Template ledger (see enumerate() in the .cpp): the blob has no
     * enumerate, so the HAL keeps the list of enrolled template ids itself,
     * in the framework-provided store path. */
    std::mutex mLedgerMutex;
    std::string mStorePath;
    uint32_t mGid = 0;
    std::vector<uint32_t> ledgerLoad();
    void ledgerSave(const std::vector<uint32_t>& ids);
    void ledgerAdd(uint32_t fid);
    void ledgerRemove(uint32_t fid);
};

}  // namespace implementation
}  // namespace V2_1
}  // namespace fingerprint
}  // namespace biometrics
}  // namespace hardware
}  // namespace android

#endif  // ANDROID_HARDWARE_BIOMETRICS_FINGERPRINT_V2_1_BIOMETRICSFINGERPRINT_H
