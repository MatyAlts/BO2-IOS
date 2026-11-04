#ifndef BO2_AOT_ENGINE_H
#define BO2_AOT_ENGINE_H
#include <stddef.h>
#include <stdint.h>
typedef struct {
    int32_t status;
    uint32_t steps, host_calls, slot, stub_instructions, message_length;
    uint64_t pc, fault, host_arena, arena_bytes;
    char detail[160];
    char message[4097];
} BO2AOTResult;
int32_t bo2_aot_run(const uint8_t *snapshot, size_t length, uint32_t image_end,
                   uint32_t heap_base, uint32_t heap_size, BO2AOTResult *result);
#endif
