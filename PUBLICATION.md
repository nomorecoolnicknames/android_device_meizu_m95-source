# Meizu MX6 / M95 — Android 13 device source

Real native LineageOS 20 integration for the MediaTek MT6797 MX6: product and
board configuration, init and SELinux integration, graphics/audio/network
compatibility shims, fingerprint and lights source, camera metadata adaptation,
Wi-Fi integration and carrier overlays.

This branch exports source `f2a12c98cdb8abb9b951a0f4542ee2c4e6d56eb8`.
It includes the 29 September GraphicBuffer ownership correction, which has
not yet been validated in a new flashed build. Hardware-observed build 23 used
`097e8a630754c6689524f4d627a5720a5585f569`; built-only build 24 used
`582ed4d131cad39e2fe5d77061caebae5d9425ba`. Their filtered equivalents are in
the history map; these three states must not be conflated.

Prebuilt kernel/firmware, stock-derived configuration/media/keymap payloads,
the private-host optional APK staging helper and private identifiers are
omitted or redacted throughout imported history. References to external inputs
remain so incomplete build dependencies are visible. Bring-up settings include
permissive SELinux; this is not a hardened production release.

## Demonstrated Android 13 result

MX6 has progressed beyond the earlier GSI experiments: native LineageOS 20
userdebug build 23 booted on the device. The retained 26 September 2026 capture
reports Android 13, SDK 33, `20.0-20260925-UNOFFICIAL-m95` and
`sys.boot_completed=1`. LTE data and IMS registration were observed. Incoming
IMS calls still crashed the IMS service; the fix was built in build 24 but
has not been accepted on hardware. Outgoing VoLTE, SMS over IMS, camera
lifecycle/frame delivery and full power/suspend testing remain open.

The compact [runtime summary](RUNTIME_SUMMARY.json) records source/artifact
identity and the hashes of retained private evidence. Raw logs contain device
and subscriber data and are intentionally not published. This publication
performed no new build, flash, readback or device test. Historical flash logs
are not a fresh partition-readback result.

## History, licensing and reproducibility

`PUBLICATION.json` maps every imported original commit to the filtered public
commit, with exclusions and redactions. Original authors, dates, parent graph
and commit subjects are retained; operational commit bodies are replaced by
source provenance. Original private repositories and active working trees
are unchanged. Existing per-file licenses and copyright notices remain;
public visibility is not a blanket license grant or an OSL eligibility review.

Full Android builds also need framework/compatibility changes, a matching
kernel configuration/toolchain, and separately supplied vendor components.
The device/kernel branches are reviewable source checkpoints, not a complete
proprietary-free ROM manifest. Missing inputs are not replaced with stubs or
allow-missing build flags. OSL work must use a separately reviewed complete
open-source input set; proprietary ROM builds/storage remain outside it.
