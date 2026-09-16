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

#define LOG_TAG "fingerprint@2.0-service.m95"

#include <android/log.h>
#include <binder/IPCThreadState.h>
#include <binder/ProcessState.h>
#include <hidl/HidlSupport.h>
#include <hidl/HidlTransportSupport.h>
#include <android/hardware/biometrics/fingerprint/2.1/IBiometricsFingerprint.h>
#include <android/hardware/biometrics/fingerprint/2.1/types.h>
#include "BiometricsFingerprint.h"

using android::hardware::biometrics::fingerprint::V2_1::IBiometricsFingerprint;
using android::hardware::biometrics::fingerprint::V2_1::implementation::BiometricsFingerprint;
using android::hardware::configureRpcThreadpool;
using android::hardware::joinRpcThreadpool;
using android::sp;
using android::ProcessState;

int main() {
    android::sp<IBiometricsFingerprint> bio = BiometricsFingerprint::getInstance();

    /*
     * The Goodix module talks to /vendor/bin/goodixfingerprintd over FRAMEWORK
     * binder (libgoodixfingerprintd_binder, /dev/binder — measured live: the
     * daemon holds /dev/binder on fd 5 and maps /system/lib64/libbinder.so),
     * and the daemon delivers every enrol / acquire / error result by calling
     * BACK into this process on that same node.
     *
     * joinRpcThreadpool() below serves hwbinder only. Without a framework
     * binder threadpool those callbacks are queued in this process and never
     * read: on LOS 16.0 enrolment ran to completion inside the daemon
     * (image_quality 85, nine accepted touches) while the framework saw
     * acquire=0 and the wizard never moved off "touch the sensor". Starting
     * the pool took acquire from 0 to 11, 89, 214, 256 and let enrolment reach
     * rem=0.
     *
     * getInstance() above has already constructed the ProcessState (the blob's
     * open() does a getService()), so self() returns that existing one on
     * /dev/binder rather than opening a second driver.
     */
    ProcessState::self()->startThreadPool();

    configureRpcThreadpool(1, true /*callerWillJoin*/);

    if (bio != nullptr) {
        if (::android::OK != bio->registerAsService()) {
            return 1;
        }
    } else {
        ALOGE("Can't create instance of BiometricsFingerprint, nullptr");
    }

    joinRpcThreadpool();

    return 0; // should never get here
}
