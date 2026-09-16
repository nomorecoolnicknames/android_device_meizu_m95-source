// AndroidBitmap_* for the Meizu camera libraries in the camera HAL closure
// (libcam.common.meizu.so, libphoto_timestamp.so). They import the three JNI
// bitmap helpers from libjnigraphics, which is system-only and invisible under
// strict VNDK. Both blobs are only loaded by the native camera HAL process,
// which has no JavaVM, so returning an error is safe. Unique SONAME on purpose
// (wire-shims.py --replace-needed) so the system libjnigraphics stays visible
// to everything else. Evidence: VNDK_FULL_PREFLIP_BOOT_AUDIT.md.
int AndroidBitmap_getInfo(void* env, void* jbitmap, void* info) {
    (void)env;
    (void)jbitmap;
    (void)info;
    return -1;
}

int AndroidBitmap_lockPixels(void* env, void* jbitmap, void** addrPtr) {
    (void)env;
    (void)jbitmap;
    (void)addrPtr;
    return -1;
}

int AndroidBitmap_unlockPixels(void* env, void* jbitmap) {
    (void)env;
    (void)jbitmap;
    return -1;
}
