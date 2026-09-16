// libskia (stub) — DT_NEEDED placebo for m95 Nougat blobs.
//
// Android P merged skia into libhwui; there is no /system/lib{,64}/libskia.so
// on a LOS 16.0 image, so every blob with DT_NEEDED [libskia.so] fails to
// load regardless of whether it actually calls into skia.
//
// readelf FACT (2026-07-27): of the blobs that DT_NEED libskia.so,
//   libcam.camadapter.so (32/64)  — 0 Sk* imports   <- CAMERA-critical
//   libem_wifi_jni.so (32/64)     — 0 Sk* imports
//   libimsma_socketwrapper.so,
//   libimsma_rtp.so (32/64)       — 0 Sk* imports
//   libjni_lomoeffect.so (32/64)  — 0 Sk* imports
// i.e. linker cruft only: an empty libskia.so satisfies them with zero ABI
// risk. libaal.so (14 Sk imports, 6 of them nonexistent in P) and 32-bit
// libvtmal.so still cannot load — see README "not shimmable".
//
// This stub intentionally exports nothing skia-shaped: resolving N-era Sk*
// symbols against P skia objects with different layouts would corrupt, and
// every loadable consumer imports none.
extern "C" void __m95_libskia_stub_marker(void) {}
