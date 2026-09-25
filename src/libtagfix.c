/*
 * libtagfix.c — Universal Disable for Android Bionic software TBI heap pointer tagging
 *
 * Background:
 *   Android bionic enables software Tag-Based Isolation (TBI) heap tagging by default:
 *   every malloc'd pointer has tag bits in its top byte.
 *   Bun/JavaScriptCore uses the top byte of pointers for NaN-boxing, zeroing it.
 *   When JSC later frees such a pointer, bionic's MaybeUntagAndCheckPointer sees
 *   a tag mismatch (expected non-zero tag, found 0x00) and calls async_safe_fatal:
 *     "Pointer tag for 0x... was truncated"
 *   This causes a SIGABRT at any free() after JSC allocates memory.
 *
 * Universal Fix:
 *   - Android 12+ (API 31+): mallopt(M_BIONIC_SET_HEAP_TAGGING_LEVEL, M_HEAP_TAGGING_LEVEL_NONE)
 *     where M_BIONIC_SET_HEAP_TAGGING_LEVEL is (-204) and M_HEAP_TAGGING_LEVEL_NONE is 0.
 *   - Android 11 (API 30): android_mallopt(M_SET_HEAP_TAGGING_LEVEL_ANDROID11, &level, sizeof(level))
 *     where M_SET_HEAP_TAGGING_LEVEL_ANDROID11 is 8 and level is 0.
 *     We check weak symbol android_mallopt and fallback to dynamic dlopen("libc.so").
 *   - Constructor priority 101 ensures execution before standard constructors (priority 65535).
 *
 * This shared object is LD_PRELOAD'd by the opencode wrapper script.
 */

#include <malloc.h>
#include <dlfcn.h>
#include <stddef.h>

#ifndef M_BIONIC_SET_HEAP_TAGGING_LEVEL
#define M_BIONIC_SET_HEAP_TAGGING_LEVEL (-204)
#endif

#ifndef M_HEAP_TAGGING_LEVEL_NONE
#define M_HEAP_TAGGING_LEVEL_NONE 0
#endif

#define M_SET_HEAP_TAGGING_LEVEL_ANDROID11 8

extern int mallopt(int, int) __attribute__((weak));
extern int android_mallopt(int, void*, size_t) __attribute__((weak));

__attribute__((constructor(101)))
static void disable_heap_tagging(void) {
    // 1. Try modern Android 12+ (API 31+) mallopt
    if (mallopt) {
        mallopt(M_BIONIC_SET_HEAP_TAGGING_LEVEL, M_HEAP_TAGGING_LEVEL_NONE);
    }

    // 2. Try Android 11 (API 30) android_mallopt
    int level = M_HEAP_TAGGING_LEVEL_NONE;
    if (android_mallopt) {
        android_mallopt(M_SET_HEAP_TAGGING_LEVEL_ANDROID11, &level, sizeof(level));
    } else {
        void *libc = dlopen("libc.so", RTLD_NOLOAD | RTLD_NOW);
        if (!libc) libc = dlopen("libc.so", RTLD_NOW);
        if (libc) {
            int (*fn)(int, void*, size_t) = (int (*)(int, void*, size_t))dlsym(libc, "android_mallopt");
            if (fn) {
                fn(M_SET_HEAP_TAGGING_LEVEL_ANDROID11, &level, sizeof(level));
            }
        }
    }
}
