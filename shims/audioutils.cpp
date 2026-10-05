// libm95shim_audioutils — echo-reference stubs for audio.primary.mt6797.
//
// create/release_echo_reference were removed from R's libaudioutils.
// N-ABI signature (system/media/audio_utils/.../echo_reference.h, N era):
//   int create_echo_reference(audio_format_t, uint32_t, uint32_t,
//                             audio_format_t, uint32_t, uint32_t,
//                             echo_reference_itfe**);
//   void release_echo_reference(echo_reference_itfe*);
// They serve voice-call echo cancellation only. Stub returns -ENOSYS so the
// HAL takes its no-EC path (a null reference with success return would crash
// at first read/write through the itfe).
#include <errno.h>
#include <stdint.h>

extern "C" {

struct echo_reference_itfe;

int create_echo_reference(int /*rdFormat*/, uint32_t /*rdChannelCount*/,
                          uint32_t /*rdSamplingRate*/, int /*wrFormat*/,
                          uint32_t /*wrChannelCount*/,
                          uint32_t /*wrSamplingRate*/,
                          struct echo_reference_itfe** reference) {
    if (reference) *reference = 0;
    return -ENOSYS;
}

void release_echo_reference(struct echo_reference_itfe* /*reference*/) {
}

}  // extern "C"

// ---- android::AudioSystem::getDeviceConnectionState(audio_devices_t, const char*)

// The blob calls it inside adev_open() (headset/BT presence check). On R the
// HAL lives in android.hardware.audio.service: R libaudioclient resolves the
// call through the vendor libbinder -> /dev/vndbinder, where media.audio_policy
// / media.audio_flinger are never published, and AudioFlinger only publishes
// after loadHwModule() returns -> audioserver openDevice() and the HAL wait on
// each other forever; system_server's Watchdog then kills it in
// AudioService.<init> (vendor23: three system_server restarts, no boot).
// Report "unavailable": the policy manager pushes real connection state via
// set_parameters after the module is loaded, exactly as on a fresh boot.
// This library precedes libaudioclient in the blob's DT_NEEDED (wire-shims.py
// --add-needed prepends), so this definition wins the lookup.
extern "C" int _ZN7android11AudioSystem24getDeviceConnectionStateEjPKc(
        unsigned int /*device*/, const char* /*device_address*/) {
    return 0;  // AUDIO_POLICY_DEVICE_STATE_UNAVAILABLE
}

// ---- AudioSystem::getParameters / setParameters (audio_io_handle_t, String8)
// FACT (debuggerd on android.hardware.audio.service, vendor24): adev_open ->
// SpeechDriverLAD -> SpeechParamParser::InitAppParser -> libaudio_param_parser
// isCustXmlEnable() -> AudioSystem::getParameters() -> get_audio_flinger() ->
// "Service media.audio_flinger didn't start" forever on /dev/vndbinder. The
// same deadlock class as getDeviceConnectionState above. Both entry points
// are answered locally: getParameters returns an empty String8 (the parser
// then treats the custom-XML feature as disabled and uses NVRAM params),
// setParameters reports success. String8 is returned by value = sret; a
// one-pointer struct with a user-provided destructor is returned exactly like
// String8 (mString pointer), and the empty string is built by the real
// String8::String8() so the SharedBuffer accounting stays libutils' own.
// Consumers wired by wire-shims.py: libaudio_param_parser.so (32/64).
namespace { struct M95String8Ret { void* p; ~M95String8Ret() {} }; }
extern "C" void _ZN7android7String8C1Ev(void* self);
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wreturn-type-c-linkage"
extern "C" M95String8Ret _ZN7android11AudioSystem13getParametersEiRKNS_7String8E(
        int /*ioHandle*/, const void* /*keys*/) {
    M95String8Ret r;
    _ZN7android7String8C1Ev(&r);
    return r;
}
#pragma clang diagnostic pop
extern "C" int _ZN7android11AudioSystem13setParametersEiRKNS_7String8E(
        int /*ioHandle*/, const void* /*keyValuePairs*/) {
    return 0;  // NO_ERROR
}
