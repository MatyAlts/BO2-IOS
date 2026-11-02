#ifndef CPROBE_H
#define CPROBE_H
#include <stdint.h>
#include <stdbool.h>

typedef struct {
    int32_t status;
    int32_t error_number;
    uint32_t callback_count;
    uint32_t tls_preserved;
    uint32_t canaries_preserved;
    uint32_t stack_preserved;
    uint32_t register_preserved;
    uint32_t context32;
    uint64_t page_size;
    uint64_t mapping_address;
    uint64_t mapping_size;
    uint64_t data_address;
    uint64_t stack_start;
    uint64_t stack_end;
    uint64_t signed_entry;
    uint64_t returned;
    uint64_t expected;
    uint64_t callback_stack;
} NativeProbeResult;

uint64_t probe_page_size(void);
NativeProbeResult probe_run(uint32_t input, bool require_low_memory);
#endif
