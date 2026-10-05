/*
 * Copyright (C) 2026 The LineageOS Project
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



#define LOG_TAG "lights.m95"

#include <log/log.h>

#include <errno.h>
#include <fcntl.h>
#include <malloc.h>
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

#include <hardware/hardware.h>
#include <hardware/lights.h>
#include <stdlib.h>
#include <sys/system_properties.h>

static pthread_mutex_t g_lock = PTHREAD_MUTEX_INITIALIZER;

/* last requested state per virtual light sharing mx-led */
static struct light_state_t g_battery;
static struct light_state_t g_notification;
static struct light_state_t g_attention;

#define LCD_BRIGHTNESS_FILE "/sys/class/leds/lcd-backlight/brightness"
#define MX_BRIGHTNESS_FILE  "/sys/class/leds/mx-led/brightness"
#define MX_DELAY_ON_FILE    "/sys/class/leds/mx-led/delay_on"
#define MX_DELAY_OFF_FILE   "/sys/class/leds/mx-led/delay_off"
#define MX_TRIGGER_FILE     "/sys/class/leds/mx-led/trigger"

static int write_int(const char *path, int value)
{
    char buffer[20];
    int fd, bytes, written;

    fd = open(path, O_WRONLY);
    if (fd < 0) {
        static int already_warned;
        if (!already_warned) {
            ALOGE("write_int failed to open %s (%s)", path, strerror(errno));
            already_warned = 1;
        }
        return -errno;
    }
    bytes = snprintf(buffer, sizeof(buffer), "%d\n", value);
    written = write(fd, buffer, bytes);
    close(fd);
    return written == bytes ? 0 : -errno;
}

/*
 * Make sure the ledtrig-timer delay attrs exist before a blink write.
 * They only exist while the timer trigger is active; init activates it at
 * boot, but that has been observed not to survive (see the file header), and
 * the attrs are then simply absent. Writing "timer" to the trigger (0664
 * system system by the m95 ueventd rules) re-creates them; ueventd chowns the
 * new attrs asynchronously, so the caller's first write may still lose the
 * race and fall back to solid light -- the next request gets blink.
 * Called with g_lock held.
 */
static void ensure_timer_trigger(void)
{
    int fd;

    if (access(MX_DELAY_ON_FILE, W_OK) == 0)
        return;

    fd = open(MX_TRIGGER_FILE, O_WRONLY);
    if (fd < 0) {
        ALOGW("mx-led trigger unwritable (%s)", strerror(errno));
        return;
    }
    if (write(fd, "timer\n", 6) != 6)
        ALOGW("mx-led trigger write failed (%s)", strerror(errno));
    else
        ALOGI("mx-led timer trigger re-armed");
    close(fd);
}

static int is_lit(const struct light_state_t *state)
{
    return state->color & 0x00ffffff;
}

static int rgb_to_brightness(const struct light_state_t *state)
{
    int color = state->color & 0x00ffffff;

    return ((77 * ((color >> 16) & 0xff)) + (150 * ((color >> 8) & 0xff)) +
            (29 * (color & 0xff))) >> 8;
}



#define FLYME_INT_MAX 3515u
#define FLYME_HAL_MAX_DEFAULT 4095u

static unsigned int flyme_raw_max(void)
{
    char v[PROP_VALUE_MAX];
    unsigned int halmax = FLYME_HAL_MAX_DEFAULT;

    if (__system_property_get("vendor.m95.brightness_hal_max", v) > 0) {
        unsigned int p = (unsigned int)strtoul(v, NULL, 10);
        if (p >= 3515u && p <= 65535u)
            halmax = p;
    }
    return FLYME_INT_MAX * FLYME_INT_MAX / halmax;   /* 3017 for 4095, 603 for 20480 */
}

static int backlight_level(const struct light_state_t *state)
{
    unsigned int color = (unsigned int)state->color;
    int level;

    if ((color & 0xff000000u) == 0 && color <= 8192u) {
        unsigned int raw_max = flyme_raw_max();
        level = (int)((color * 255u + raw_max / 2) / raw_max);
        if (level > 255)
            level = 255;
        if (color != 0 && level == 0)
            level = 1;
        ALOGV("backlight: flyme raw %u -> %d", color, level);
        return level;
    }
    return rgb_to_brightness(state);
}

static int set_light_backlight(struct light_device_t *dev __unused,
                               const struct light_state_t *state)
{
    int err;
    int brightness = backlight_level(state);

    pthread_mutex_lock(&g_lock);
    err = write_int(LCD_BRIGHTNESS_FILE, brightness);
    pthread_mutex_unlock(&g_lock);
    return err;
}

/* apply one state to the mono mx-led; caller holds g_lock */
static int apply_mx_led_locked(const struct light_state_t *state)
{
    int brightness = rgb_to_brightness(state);
    int blink = 0;
    int on_ms = 0, off_ms = 0;

    ensure_timer_trigger();

    switch (state->flashMode) {
    case LIGHT_FLASH_TIMED:
    case LIGHT_FLASH_HARDWARE:
        on_ms = state->flashOnMS;
        off_ms = state->flashOffMS;
        blink = brightness > 0 && on_ms > 0 && off_ms > 0;
        break;
    default:
        break;
    }

    if (blink) {
        /* delay writes fail gracefully into solid light if the attrs are
         * missing (timer trigger not activated by init) */
        if (write_int(MX_DELAY_ON_FILE, on_ms) ||
            write_int(MX_DELAY_OFF_FILE, off_ms))
            ALOGW("mx-led blink attrs unwritable, falling back to solid");
    } else {
        /* delay_off 0 = solid on in the LED core's software blink */
        write_int(MX_DELAY_ON_FILE, 1000);
        write_int(MX_DELAY_OFF_FILE, 0);
    }
    return write_int(MX_BRIGHTNESS_FILE, brightness);
}

static int refresh_mx_led_locked(void)
{
    /* attention > notifications > battery, the classic liblight priority */
    if (is_lit(&g_attention))
        return apply_mx_led_locked(&g_attention);
    if (is_lit(&g_notification))
        return apply_mx_led_locked(&g_notification);
    return apply_mx_led_locked(&g_battery);
}

static int set_light_battery(struct light_device_t *dev __unused,
                             const struct light_state_t *state)
{
    int err;

    pthread_mutex_lock(&g_lock);
    g_battery = *state;
    err = refresh_mx_led_locked();
    pthread_mutex_unlock(&g_lock);
    return err;
}

static int set_light_notifications(struct light_device_t *dev __unused,
                                   const struct light_state_t *state)
{
    int err;

    pthread_mutex_lock(&g_lock);
    g_notification = *state;
    err = refresh_mx_led_locked();
    pthread_mutex_unlock(&g_lock);
    return err;
}

static int set_light_attention(struct light_device_t *dev __unused,
                               const struct light_state_t *state)
{
    int err;

    pthread_mutex_lock(&g_lock);
    g_attention = *state;
    err = refresh_mx_led_locked();
    pthread_mutex_unlock(&g_lock);
    return err;
}

static int close_lights(struct light_device_t *dev)
{
    free(dev);
    return 0;
}

static int open_lights(const struct hw_module_t *module, const char *name,
                       struct hw_device_t **device)
{
    int (*set_light)(struct light_device_t *dev,
                     const struct light_state_t *state);
    struct light_device_t *dev;

    if (!strcmp(LIGHT_ID_BACKLIGHT, name))
        set_light = set_light_backlight;
    else if (!strcmp(LIGHT_ID_BATTERY, name))
        set_light = set_light_battery;
    else if (!strcmp(LIGHT_ID_NOTIFICATIONS, name))
        set_light = set_light_notifications;
    else if (!strcmp(LIGHT_ID_ATTENTION, name))
        set_light = set_light_attention;
    else
        return -EINVAL;

    dev = calloc(1, sizeof(*dev));
    if (!dev)
        return -ENOMEM;

    dev->common.tag = HARDWARE_DEVICE_TAG;
    dev->common.version = LIGHTS_DEVICE_API_VERSION_2_0;
    dev->common.module = (struct hw_module_t *)module;
    dev->common.close = (int (*)(struct hw_device_t *))close_lights;
    dev->set_light = set_light;

    *device = (struct hw_device_t *)dev;
    return 0;
}

static struct hw_module_methods_t lights_module_methods = {
    .open = open_lights,
};

struct hw_module_t HAL_MODULE_INFO_SYM = {
    .tag = HARDWARE_MODULE_TAG,
    .version_major = 1,
    .version_minor = 0,
    .id = LIGHTS_HARDWARE_MODULE_ID,
    .name = "m95 lights module",
    .author = "The LineageOS Project",
    .methods = &lights_module_methods,
};
