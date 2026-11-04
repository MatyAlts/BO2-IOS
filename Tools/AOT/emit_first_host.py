"""Finite AOT closure for MP's first actual host import.

Decode at build time. Unsupported reached PCs/encodings fail closed in emitted C.
The Android gateway is replaced by a typed, allowlisted host boundary.
"""
import hashlib
import struct
from pathlib import Path
def sx(value, bits):
    return value - (1 << bits) if value & (1 << (bits - 1)) else value

RANGES = ((0x1163910, 0x11639c8), (0x116a570, 0x116ab18),
          (0x116c6b0, 0x116dcfc), (0x1164818, 0x1164828))


def masks(n, s, r, bits):
    length = ((n << 6) | ((~s) & 63)).bit_length() - 1
    if length < 1 or (1 << length) > bits:
        raise ValueError('invalid bitmask')
    levels = (1 << length) - 1
    ss, rr = s & levels, r & levels
    esize = 1 << length
    mask = (1 << esize) - 1
    elem = (1 << (ss + 1)) - 1
    rot = ((elem >> rr) | (elem << ((esize - rr) % esize))) & mask
    top = (1 << (((ss - rr) & levels) + 1)) - 1
    return sum(rot << i for i in range(0, bits, esize)), sum(top << i for i in range(0, bits, esize))


def translate(pc, w, allowed):
    rd, rn, rm = w & 31, (w >> 5) & 31, (w >> 16) & 31
    bits = 64 if w >> 31 else 32
    cast = 'uint64_t' if bits == 64 else 'uint32_t'
    def r(i, sp=False):
        return '*sp' if i == 31 and sp else ('0ULL' if i == 31 else f'r[{i}]')
    def put(i, val, sp=False):
        return f'{"*sp" if i == 31 else f"r[{i}]"}=({cast})({val});' if i != 31 or sp else '(void)0;'
    nxt = f'*pc={pc + 4}ULL; goto dispatch;'
    body = []
    if w & 0x7c000000 == 0x14000000:
        dest = pc + (sx(w & 0x3ffffff, 26) << 2)
        if dest not in allowed and dest != 0x11647b4:
            return f'*target={dest}ULL; return 1;'
        if w & 0x80000000:
            body.append(f'r[30]={pc+4}ULL;')
        body.append(f'*pc={dest}ULL; goto dispatch;')
    elif w & 0xfffffc1f in (0xd65f0000, 0xd61f0000, 0xd63f0000):
        if w & 0xfffffc1f == 0xd63f0000:
            body.append(f'a={r(rn)}; r[30]={pc+4}ULL; *pc=a; goto dispatch;')
        else:
            body.append(f'*pc={r(rn)}; goto dispatch;')
    elif w == 0xd503201f:
        body.append(nxt)
    elif w & 0x9f000000 in (0x90000000, 0x10000000):
        imm = sx((((w >> 5) & 0x7ffff) << 2) | ((w >> 29) & 3), 21)
        value = ((pc & ~4095) + (imm << 12)) if w & 0x80000000 else pc + imm
        body += [put(rd, str(value)), nxt]
    elif w & 0xff000010 == 0x54000000:
        dest = pc + (sx((w >> 5) & 0x7ffff, 19) << 2)
        body.append(f'*pc=condition({w&15},nzcv)?{dest}ULL:{pc+4}ULL; goto dispatch;')
    elif w & 0x7e000000 == 0x34000000:
        dest = pc + (sx((w >> 5) & 0x7ffff, 19) << 2)
        body.append(f'*pc=((({cast}){r(rd)}!=0)=={(w>>24)&1})?{dest}ULL:{pc+4}ULL; goto dispatch;')
    elif w & 0x7e000000 == 0x36000000:
        bit = ((w >> 31) << 5) | ((w >> 19) & 31)
        dest = pc + (sx((w >> 5) & 0x3fff, 14) << 2)
        body.append(f'*pc=((({r(rd)}>>{bit})&1)=={(w>>24)&1})?{dest}ULL:{pc+4}ULL; goto dispatch;')
    elif w & 0x3a000000 == 0x28000000:
        # Integer or opaque SIMD register pair. No float computation is assumed.
        simd = bool(w & 0x04000000)
        size = (4 << ((w >> 30) & 3)) if simd else (8 if w & 0x80000000 else 4)
        if size not in (4, 8, 16):
            raise ValueError('pair size')
        if simd and w & (1<<22) and size<16:
            raise ValueError('scalar SIMD load requires upper-vector semantics')
        mode = (w >> 23) & 3
        imm = sx((w >> 15) & 127, 7) * size
        rt2 = (w >> 10) & 31
        body.append(f'a={r(rn,True)};')
        if mode != 1:
            body.append(f'a+=(uint64_t)({imm}LL);')
        for index, regno in enumerate((rd, rt2)):
            addr = f'a+{index*size}ULL'
            if simd:
                fn = 'loadq' if w & (1 << 22) else 'storeq'
                body.append(f'if(!{fn}(m,n,{addr},q[{regno}],{size},fault)) return 2;')
            elif w & (1 << 22):
                body += [f'if(!load(m,n,{addr},{size},&v,fault))return 2;', put(regno,'v')]
            else:
                body.append(f'if(!store(m,n,{addr},{size},{r(regno)},fault))return 2;')
        if mode in (1, 3):
            body.append(put(rn, f'{r(rn,True)}+(uint64_t)({imm}LL)', True))
        body.append(nxt)
    elif w & 0x3b000000 in (0x39000000, 0x38000000):
        simd = bool(w & 0x04000000)
        opc = (w >> 22) & 3
        size = 1 << ((w >> 30) & 3)
        if simd and opc & 2:
            size = 16
        if simd and opc & 1 and size<16:
            raise ValueError('scalar SIMD load requires upper-vector semantics')
        unsigned = (w & 0x3b000000) == 0x39000000
        post = pre = False
        if unsigned:
            expr = f'{((w>>10)&4095)*size}ULL'
        elif w & 0x00200000:
            option = (w >> 13) & 7
            ext = {2:f'(uint32_t){r(rm)}',3:r(rm),6:f'(uint64_t)(int64_t)(int32_t){r(rm)}',7:f'(uint64_t)(int64_t){r(rm)}'}.get(option)
            if ext is None:
                raise ValueError('memory extension')
            shift = (size.bit_length()-1) if w & 0x1000 else 0
            expr = f'(({ext})<<{shift})'
        else:
            imm = sx((w >> 12) & 511, 9)
            mode = (w >> 10) & 3
            post, pre = mode == 1, mode == 3
            expr = f'(uint64_t)({imm}LL)'
        body.append(f'a={r(rn,True)}' + (';' if post else f'+{expr};'))
        if simd:
            fn = 'loadq' if opc & 1 else 'storeq'
            body.append(f'if(!{fn}(m,n,a,q[{rd}],{size},fault))return 2;')
        elif opc:
            body.append(f'if(!load(m,n,a,{size},&v,fault))return 2;')
            value = 'v'
            if opc >= 2:
                signed = {1:'int8_t',2:'int16_t',4:'int32_t',8:'int64_t'}[size]
                value = f'(uint64_t)(int64_t)({signed})v'
                if opc == 3:
                    value = f'(uint32_t)({value})'
            # A W load must zero-extend even when encoding size != register width.
            body.append(f'r[{rd}]={value};' if rd != 31 else '(void)0;')
        else:
            body.append(f'if(!store(m,n,a,{size},{r(rd)},fault))return 2;')
        if pre or post:
            body.append(f'{"*sp" if rn==31 else f"r[{rn}]"}={r(rn,True)}+{expr};')
        body.append(nxt)
    elif w & 0x1f000000 == 0x11000000:
        sub, flags = (w >> 30) & 1, (w >> 29) & 1
        imm = ((w >> 10) & 4095) << (12 if w & 0x400000 else 0)
        body += [f'a=({cast}){r(rn,True)}; b={imm}ULL;', f'v=({cast})(a {"-" if sub else "+"} b);']
        if flags:
            body.append(f'nzcv=flags_arith(a,b,v,{bits},{sub});')
        body += [put(rd,'v',not flags),nxt]
    elif w & 0x1f200000 == 0x0b000000:
        sub, flags = (w >> 30) & 1, (w >> 29) & 1
        shift, amount = (w >> 22) & 3, (w >> 10) & 63
        if shift == 3 or (bits == 32 and amount >= 32):
            raise ValueError('arithmetic shift')
        body += [f'a=({cast}){r(rn)}; b=shift_value({r(rm)},{bits},{shift},{amount});', f'v=({cast})(a {"-" if sub else "+"} b);']
        if flags:
            body.append(f'nzcv=flags_arith(a,b,v,{bits},{sub});')
        body += [put(rd,'v'),nxt]
    elif w & 0x1f000000 == 0x0a000000:
        opc, invert = (w >> 29) & 3, (w >> 21) & 1
        body.append(f'a=({cast}){r(rn)}; b=shift_value({r(rm)},{bits},{(w>>22)&3},{(w>>10)&63});')
        if invert:
            body.append(f'b=({cast})(~b);')
        operator = ('&','|','^','&')[opc]
        body.append(f'v=({cast})(a{operator}b);')
        if opc == 3:
            body.append(f'nzcv=((v>>{bits-1})?8:0)|(v==0?4:0);')
        body += [put(rd,'v'),nxt]
    elif w & 0x1f800000 == 0x12800000:
        opc, shift = (w >> 29) & 3, 16 * ((w >> 21) & 3)
        if shift >= bits or opc == 1:
            raise ValueError('movwide')
        val = ((w >> 5) & 65535) << shift
        expr = f'~{val}ULL' if opc == 0 else (f'({r(rd)}&~{65535<<shift}ULL)|{val}ULL' if opc == 3 else f'{val}ULL')
        body += [put(rd,expr),nxt]
    elif w & 0x1f800000 == 0x12000000:
        opc = (w >> 29) & 3
        mask, _ = masks((w >> 22) & 1, (w >> 10) & 63, (w >> 16) & 63, bits)
        operator = ('&','|','^','&')[opc]
        body.append(f'v=({cast})({r(rn)}{operator}{mask}ULL);')
        if opc == 3:
            body.append(f'nzcv=((v>>{bits-1})?8:0)|(v==0?4:0);')
        body += [put(rd,'v'),nxt]
    elif w & 0x1f800000 == 0x13000000:
        opc, s, rot = (w >> 29) & 3, (w >> 10) & 63, (w >> 16) & 63
        wm, tm = masks((w >> 22) & 1, s, rot, bits)
        body += [f'a=({cast}){r(rn)}; b=rotate(a,{bits},{rot})&{wm}ULL;']
        if opc == 0:
            body.append(f'v=(((a>>{s})&1)?~{tm}ULL:0)|(b&{tm}ULL);')
        elif opc == 2:
            body.append(f'v=b&{tm}ULL;')
        else:
            raise ValueError('BFM not implemented')
        body += [put(rd,'v'),nxt]
    elif w & 0x7fe0fc00 in (0x1ac00800,0x1ac00c00):
        signed = bool(w & 0x400)
        if signed:
            ctype = 'int64_t' if bits == 64 else 'int32_t'
            body.append(f'v=divide_signed(({ctype}){r(rn)},({ctype}){r(rm)},{bits});')
        else:
            body.append(f'v=({cast}){r(rm)}?({cast}){r(rn)}/({cast}){r(rm)}:0;')
        body += [put(rd,'v'),nxt]
    elif w & 0x1fe00000 == 0x1b000000:
        ra = (w >> 10) & 31
        body += [put(rd,f'{r(ra)} {"-" if w&0x8000 else "+"} ({r(rn)}*{r(rm)})'),nxt]
    elif w & 0x1fe00000 == 0x1a800000:
        cond = (w >> 12) & 15
        expr = r(rm)
        if w & 0x40000000:
            expr = f'~({expr})'
        if w & 0x400:
            expr = f'({expr})+1'
        body += [put(rd,f'condition({cond},nzcv)?{r(rn)}:({expr})'),nxt]
    else:
        raise ValueError(f'unsupported {pc:x}: {w:08x}')
    return '\n'.join(body)


HELPERS = r'''
#include <stdint.h>
#include <stddef.h>
#include <limits.h>
static int range(size_t n,uint64_t a,unsigned width,uint64_t*f){
 if(a<0x4000ULL||a>0xffffffffULL||width>n||a>(uint64_t)n-width||a+width>0x100000000ULL){*f=a;return 0;}return 1;}
static int load(const uint8_t*m,size_t n,uint64_t a,unsigned width,uint64_t*v,uint64_t*f){
 if(!range(n,a,width,f))return 0;*v=0;for(unsigned i=0;i<width;i++)*v|=(uint64_t)m[(size_t)a+i]<<(8*i);return 1;}
static int store(uint8_t*m,size_t n,uint64_t a,unsigned width,uint64_t v,uint64_t*f){
 if(!range(n,a,width,f))return 0;for(unsigned i=0;i<width;i++)m[(size_t)a+i]=(uint8_t)(v>>(8*i));return 1;}
static int loadq(const uint8_t*m,size_t n,uint64_t a,uint8_t*q,unsigned width,uint64_t*f){if(!range(n,a,width,f))return 0;for(unsigned i=0;i<width;i++)q[i]=m[(size_t)a+i];return 1;}
static int storeq(uint8_t*m,size_t n,uint64_t a,uint8_t*q,unsigned width,uint64_t*f){if(!range(n,a,width,f))return 0;for(unsigned i=0;i<width;i++)m[(size_t)a+i]=q[i];return 1;}
static uint64_t rotate(uint64_t a,unsigned bits,unsigned amount){uint64_t mask=bits==64?UINT64_MAX:UINT32_MAX;a&=mask;amount%=bits;return amount?((a>>amount)|(a<<(bits-amount)))&mask:a;}
static uint64_t shift_value(uint64_t a,unsigned bits,unsigned kind,unsigned amount){a=bits==32?(uint32_t)a:a;amount%=bits;switch(kind){case 0:return a<<amount;case 1:return a>>amount;case 2:return bits==32?(uint64_t)(int64_t)((int32_t)a>>amount):(uint64_t)((int64_t)a>>amount);default:return rotate(a,bits,amount);}}
static unsigned flags_arith(uint64_t a,uint64_t b,uint64_t v,unsigned bits,unsigned sub){uint64_t mask=bits==64?UINT64_MAX:UINT32_MAX,sign=1ULL<<(bits-1);a&=mask;b&=mask;v&=mask;unsigned c=sub?(a>=b):(v<a);unsigned of=sub?(((a^b)&(a^v)&sign)!=0):(((~(a^b))&(a^v)&sign)!=0);return ((v&sign)?8:0)|(v==0?4:0)|(c?2:0)|of;}
static int condition(unsigned c,unsigned f){unsigned n=(f>>3)&1,z=(f>>2)&1,cc=(f>>1)&1,v=f&1;switch(c){case 0:return z;case 1:return !z;case 2:return cc;case 3:return !cc;case 4:return n;case 5:return !n;case 6:return v;case 7:return !v;case 8:return cc&&!z;case 9:return !cc||z;case 10:return n==v;case 11:return n!=v;case 12:return !z&&(n==v);case 13:return z||(n!=v);default:return 1;}}
static uint64_t divide_signed(int64_t a,int64_t b,unsigned bits){if(!b)return 0;if(bits==32){int32_t aa=(int32_t)a,bb=(int32_t)b;if(aa==INT32_MIN&&bb==-1)return(uint32_t)aa;return(uint32_t)(aa/bb);}if(a==INT64_MIN&&b==-1)return(uint64_t)a;return(uint64_t)(a/b);}
int aot_first_host(uint8_t*m,size_t n,uint64_t*r,uint64_t*sp,uint64_t*pc,unsigned*steps,uint64_t*fault,uint64_t*target,uint64_t*stub,uint64_t*trace,unsigned*trace_count,unsigned q_pattern){
 uint64_t a=0,b=0,v=0;unsigned nzcv=0;uint8_t q[32][16]={{0}};
 if(!m||!r||!sp||!pc||!steps||!fault||!target||!stub||!trace||!trace_count)return 5;
 for(unsigned qi=0;qi<32;qi++)for(unsigned qb=0;qb<16;qb++)q[qi][qb]=(uint8_t)q_pattern;
 dispatch:
 if(*steps>=500000){return 4;}
 trace[*trace_count%32]=*pc;++*trace_count;
 if(*pc==0x11647b4ULL){*target=r[17];if(r[17]!=0x4853540000000000ULL)return 7;return 6;}
 ++*steps;
 switch(*pc){
'''


def generate(data):
    allowed = {pc for begin,end in RANGES for pc in range(begin,end,4)}
    cases, unknown = [], []
    for pc in sorted(allowed):
        word = struct.unpack_from('<I', data, pc)[0]
        try:
            body = translate(pc,word,allowed)
        except ValueError as exc:
            unknown.append({'pc':pc,'word':hex(word),'reason':str(exc)})
            body = f'*fault={word}ULL; return 3;'
        if pc == 0x1164818:
            body = f'*stub={pc}ULL;\n' + body
        cases.append(f'case {pc}ULL:{{ /* {word:08x} */\n{body}\n}}')
    text = '/* Generated finite AOT, guest SHA256 '+hashlib.sha256(data).hexdigest()+' */\n'+HELPERS+'\n'.join(cases)+'\ndefault:*fault=*pc;return 3;\n}\n}\n'
    return text, unknown


if __name__ == '__main__':
    import argparse,json
    p=argparse.ArgumentParser();p.add_argument('--input',type=Path,required=True);p.add_argument('--output',type=Path,required=True)
    args=p.parse_args();text,unknown=generate(args.input.read_bytes());args.output.write_text(text)
    args.output.with_suffix('.unsupported.json').write_text(json.dumps(unknown,indent=2))
