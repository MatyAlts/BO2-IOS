#include "CProbe.h"
#include <errno.h>
#include <pthread.h>
#include <stddef.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>

uint64_t probe_page_size(void) { return (uint64_t)getpagesize(); }

#if defined(__aarch64__) && defined(__APPLE__)
typedef uint64_t (*Callback)(uint32_t, uint64_t);
typedef uint64_t (*SignedEntry)(uint32_t, Callback, uint64_t);
extern uint64_t probe_call_on_stack(void *, SignedEntry, uint32_t, Callback, uint64_t, uint32_t *);

typedef struct {
    uint64_t callback_pointer64;
    uint32_t context_pointer32;
    uint32_t calls;
    uint64_t stack_start;
    uint64_t stack_end;
    uint64_t callback_stack;
    pthread_t expected_thread;
    pthread_key_t tls_key;
    void *expected_tls;
    uint32_t tls_ok;
    uint32_t written;
} SyntheticContext;

static uint64_t callback(uint32_t input, uint64_t context_token) {
    SyntheticContext *ctx = (SyntheticContext *)(uintptr_t)context_token;
    uint64_t local = input;
    ctx->callback_stack = (uintptr_t)&local;
    ctx->calls += 1;
    ctx->written = input ^ UINT32_C(0xa5a5a5a5);
    ctx->tls_ok = pthread_equal(pthread_self(), ctx->expected_thread) &&
                  pthread_getspecific(ctx->tls_key) == ctx->expected_tls;
    return (uint64_t)input * 3 + 7;
}

// This code is compiled into the signed app. It is neither a BO2 guest nor JIT code.
__attribute__((noinline)) static uint64_t signed_entry(uint32_t input, Callback fn, uint64_t token) {
    return fn(input, token) + input + 11;
}

static bool low_range(uintptr_t address, size_t count) {
    return address != 0 && count != 0 && address < UINT64_C(0x100000000) &&
           count <= UINT64_C(0x100000000) - address;
}

static void *reserve(size_t bytes, bool low, int *error) {
    if (!low) {
        void *p = mmap(NULL, bytes, PROT_NONE, MAP_PRIVATE | MAP_ANON, -1, 0);
        if (p == MAP_FAILED) *error = errno;
        return p;
    }
    // Hints never replace existing mappings. Returned addresses are always checked.
    for (uintptr_t hint = UINT64_C(0x10000000); hint <= UINT64_C(0xf0000000); hint += UINT64_C(0x10000000)) {
        void *p = mmap((void *)hint, bytes, PROT_NONE, MAP_PRIVATE | MAP_ANON, -1, 0);
        if (p == MAP_FAILED) { *error = errno; continue; }
        if (low_range((uintptr_t)p, bytes)) return p;
        munmap(p, bytes);
        *error = ENOMEM;
    }
    return MAP_FAILED;
}
#endif

NativeProbeResult probe_run(uint32_t input, bool require_low_memory) {
    NativeProbeResult r;
    memset(&r, 0, sizeof(r));
    r.page_size = probe_page_size();
    r.expected = (uint64_t)input * 4 + 18;
#if !defined(__aarch64__) || !defined(__APPLE__)
    (void)require_low_memory;
    r.status = 2;
    return r;
#else
    const size_t page = (size_t)r.page_size;
    // [guard][data][guard][64 stack pages][guard], all guards remain PROT_NONE.
    const size_t bytes = page * 68;
    int mapping_error = 0;
    void *mapping = reserve(bytes, require_low_memory, &mapping_error);
    if (mapping == MAP_FAILED) { r.status = 1; r.error_number = mapping_error; return r; }
    unsigned char *data = (unsigned char *)mapping + page;
    unsigned char *stack = (unsigned char *)mapping + 3 * page;
    unsigned char *top = stack + 64 * page;
    r.mapping_address = (uintptr_t)mapping;
    r.mapping_size = bytes;
    r.data_address = (uintptr_t)data;
    r.stack_start = (uintptr_t)stack;
    r.stack_end = (uintptr_t)top;
    r.signed_entry = (uintptr_t)&signed_entry;
    if (mprotect(data, page, PROT_READ | PROT_WRITE) != 0 ||
        mprotect(stack, 64 * page, PROT_READ | PROT_WRITE) != 0) {
        r.status = 3; r.error_number = errno; munmap(mapping, bytes); return r;
    }
    uint64_t *first = (uint64_t *)data;
    uint64_t *last = (uint64_t *)(data + page - sizeof(uint64_t));
    *first = UINT64_C(0x12345678abcdef01);
    *last = UINT64_C(0x10fedcba87654321);
    SyntheticContext *ctx = (SyntheticContext *)(data + 64);
    memset(ctx, 0, sizeof(*ctx));
    ctx->callback_pointer64 = (uintptr_t)&callback;
    ctx->context_pointer32 = require_low_memory ? (uint32_t)(uintptr_t)ctx : 0;
    ctx->stack_start = (uintptr_t)stack;
    ctx->stack_end = (uintptr_t)top;
    ctx->expected_thread = pthread_self();
    uint64_t tls_canary = UINT64_C(0x1122334455667788);
    ctx->expected_tls = &tls_canary;
    int err = pthread_key_create(&ctx->tls_key, NULL);
    if (err != 0) { r.status = 4; r.error_number = err; munmap(mapping, bytes); return r; }
    err = pthread_setspecific(ctx->tls_key, &tls_canary);
    if (err != 0) {
        r.status = 4; r.error_number = err; pthread_key_delete(ctx->tls_key); munmap(mapping, bytes); return r;
    }
    uint64_t token = require_low_memory ? ctx->context_pointer32 : (uintptr_t)ctx;
    uint32_t registers_ok = 0;
    uintptr_t frame_before = (uintptr_t)__builtin_frame_address(0);
    r.returned = probe_call_on_stack(top, &signed_entry, input,
        (Callback)(uintptr_t)ctx->callback_pointer64, token, &registers_ok);
    uintptr_t frame_after = (uintptr_t)__builtin_frame_address(0);
    r.callback_count = ctx->calls;
    r.callback_stack = ctx->callback_stack;
    r.tls_preserved = ctx->tls_ok && pthread_equal(pthread_self(), ctx->expected_thread) &&
        pthread_getspecific(ctx->tls_key) == &tls_canary;
    r.canaries_preserved = *first == UINT64_C(0x12345678abcdef01) &&
        *last == UINT64_C(0x10fedcba87654321) && ctx->written == (input ^ UINT32_C(0xa5a5a5a5));
    r.stack_preserved = frame_before == frame_after && ctx->callback_stack >= r.stack_start &&
        ctx->callback_stack < r.stack_end;
    r.register_preserved = registers_ok;
    r.context32 = require_low_memory && low_range((uintptr_t)ctx, sizeof(*ctx));
    r.status = r.callback_count == 1 && r.tls_preserved && r.canaries_preserved &&
        r.stack_preserved && r.register_preserved && r.returned == r.expected ? 0 : 4;
    pthread_setspecific(ctx->tls_key, NULL);
    pthread_key_delete(ctx->tls_key);
    munmap(mapping, bytes);
    return r;
#endif
}
