// Empty DT_NEEDED placebo for vendor blobs whose link against a system-only
// library is pure overlink: readelf shows zero imported symbols from it.
//
// Installing an empty library under the REAL soname would shadow the system
// library for the vendor blobs that DO import real symbols (libcam.paramsmgr
// alone takes 139 CameraParameters entries), so these stubs keep unique names
// and wire-shims.py redirects only the zero-import consumers to them
// (patchelf --replace-needed). Evidence, both architectures:
// captures/a11-20260909/vndk-full/overlink-true.txt (__aeabi_* compiler-rt
// false positives excluded).
//
// 2026-09-09, stage 1 of VNDK_FULL_MIGRATION_PLAN.md:
//   libcamera_client  -> 5 consumers (camera.mt6797.so and 4 more)
//   libmedia          -> 18 (32-bit) / 15 (64-bit) consumers
//   libmediautils     -> audio.primary.mt6797.so only
//   libandroid_runtime-> 3 (32-bit) / 2 (64-bit) consumers
extern "C" void __m95_stub_marker(void) {}
