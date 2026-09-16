// android::AndroidRuntime::{getJNIEnv, registerNativeMethods} for
// libmeizucamera.so -- a Meizu camera app library that sits in the camera HAL
// closure (camera.mt6797.so -> libcam.paramsmgr -> libcam.common.meizu ->
// libmeizucamera). Both are JNI helpers and the native HAL process has no
// JavaVM, so null/-1 returns are safe. The signatures reproduce the real class
// so the C++ mangled names match. Unique SONAME (wire-shims.py
// --replace-needed); the empty overlink consumers of this stub need no symbols.
// Evidence: VNDK_FULL_PREFLIP_BOOT_AUDIT.md.
struct _JNIEnv;
struct JNINativeMethod;

namespace android {
class AndroidRuntime {
 public:
  static int registerNativeMethods(_JNIEnv* env, const char* className,
                                   const JNINativeMethod* methods, int numMethods);
  static _JNIEnv* getJNIEnv();
};

int AndroidRuntime::registerNativeMethods(_JNIEnv*, const char*, const JNINativeMethod*, int) {
  return -1;
}

_JNIEnv* AndroidRuntime::getJNIEnv() {
  return nullptr;
}
}  // namespace android
