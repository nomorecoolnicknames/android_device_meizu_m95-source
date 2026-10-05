// libm95probe — empty on purpose; kept only because blobs NEED it.
//
// It was a bring-up dlopen probe: a constructor that wrote one line to
// /dev/kmsg, /cache/probe.log and /data/misc/probe.log whenever a blob wired
// with `patchelf --add-needed libm95probe.so` (vendor-18.1/wire-shims.py) was
// loaded -- "does the linker reach our blob?" without logd. The question is
// long answered, but six blobs still carry the DT_NEEDED entry
// (vendor/lib{,64}/hw/{gralloc,hwcomposer,audio.primary}.mt6797.so, FACT

// draws, so the constructor ran in every app and wrote files on each start.
// Now the library is empty: the entries still resolve, nothing runs.
//
// To remove it for good: drop the NEEDED entry in the blob pipeline
// (wire-shims.py, then re-copy proprietary/ -- the blob copy is not in git),
// then delete this module and its PRODUCT_PACKAGES line.
