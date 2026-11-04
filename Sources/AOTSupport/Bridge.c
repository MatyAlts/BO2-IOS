#include "CAOTEngine.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "engine.inc"

#define VM_SIZE 0x5000000u
static int overlap(uint64_t a,uint64_t n,uint64_t b,uint64_t end){return a<end&&a+n>b;}
static void put32(uint8_t*m,uint32_t a,uint32_t v){memcpy(m+a,&v,4);}
static void put64(uint8_t*m,uint32_t a,uint64_t v){memcpy(m+a,&v,8);}
static uint32_t read32(const uint8_t*m,uint32_t a){uint32_t v;memcpy(&v,m+a,4);return v;}
static int32_t fail(BO2AOTResult*out,int32_t code,const char*why){out->status=code;snprintf(out->detail,sizeof(out->detail),"%s",why);return code;}
int32_t bo2_aot_run(const uint8_t*snapshot,size_t length,uint32_t image_end,
                   uint32_t base,uint32_t size,BO2AOTResult*out){
 if(!out)return -1;
 memset(out,0,sizeof(*out));out->slot=UINT32_MAX;
 if(!snapshot||length!=VM_SIZE||image_end>=VM_SIZE)return fail(out,2,"Invalid generated image extent");
 uint64_t end=(uint64_t)base+size;
 if(!size||base<0x4000||end>VM_SIZE)return fail(out,1,"Heap outside finite virtual arena");
 if(overlap(base,size,0,image_end)||overlap(base,size,0x4b00000,0x4b00090)||
    overlap(base,size,0x4c00000,0x4c002f8)||overlap(base,size,0x4ee0000,0x4f00000))
    return fail(out,1,"Heap overlap with image or bootstrap fixture");
 uint8_t*m=malloc(VM_SIZE);if(!m)return fail(out,2,"Host arena allocation failed");
 memcpy(m,snapshot,VM_SIZE);out->host_arena=(uint64_t)(uintptr_t)m;
 const uint32_t boot=0x4b00000,table=0x4c00000;
 put32(m,boot,2);put32(m,boot+4,144);put64(m,boot+8,table);put32(m,boot+16,95);
 put32(m,boot+0x14,0);put32(m,boot+0x18,image_end);
 put32(m,boot+0x1c,base);put32(m,boot+0x20,size);
 put32(m,boot+0x34,0x4ee0000);put32(m,boot+0x38,0x20000);
 for(unsigned i=0;i<95;i++)put64(m,table+i*8,0x4853540000000000ULL+i);
 uint64_t r[31]={0},sp=0x4f00000,pc=0x1163910,fault=0,target=0,stub=0,trace[32]={0};
 unsigned steps=0,trace_count=0;r[0]=boot;r[30]=0xdeadbeef;
 int status=aot_first_host(m,VM_SIZE,r,&sp,&pc,&steps,&fault,&target,&stub,trace,&trace_count,0);
 out->steps=steps;out->pc=pc;out->fault=fault;out->arena_bytes=read32(m,0x48c3ca4);
 unsigned retained=trace_count<32?trace_count:32;
 for(unsigned i=0;i<retained;i++){uint64_t event=trace[(trace_count-retained+i)%32];if(event>=0x1164818&&event<0x1164828)out->stub_instructions++;}
 if(status==6){
  uint64_t address=r[0],n=r[1];
  if(target!=0x4853540000000000ULL||address<0x4000||address>UINT32_MAX||n>4096||address>VM_SIZE||n>VM_SIZE-address){
   status=8;snprintf(out->detail,sizeof(out->detail),"Typed logging boundary rejected a token or buffer");
  }else{
   memcpy(out->message,m+(size_t)address,(size_t)n);out->message[n]=0;
   out->message_length=(uint32_t)n;out->host_calls=1;out->slot=0;
   snprintf(out->detail,sizeof(out->detail),"Finite signed AOT reached the real MP logging import");
  }
 }else snprintf(out->detail,sizeof(out->detail),"Stopped at a finite translation boundary (status %d)",status);
 out->status=status;free(m);return status;
}
