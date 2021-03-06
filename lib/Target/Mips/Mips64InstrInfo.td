//===- Mips64InstrInfo.td - Mips64 Instruction Information -*- tablegen -*-===//
//
//                     The LLVM Compiler Infrastructure
//
// This file is distributed under the University of Illinois Open Source
// License. See LICENSE.TXT for details.
//
//===----------------------------------------------------------------------===//
//
// This file describes Mips64 instructions.
//
//===----------------------------------------------------------------------===//

//===----------------------------------------------------------------------===//
// Mips Operand, Complex Patterns and Transformations Definitions.
//===----------------------------------------------------------------------===//

// Instruction operand types
def shamt_64       : Operand<i64>;

// Unsigned Operand
def uimm16_64      : Operand<i64> {
  let PrintMethod = "printUnsignedImm";
}

// Transformation Function - get Imm - 32.
def Subtract32 : SDNodeXForm<imm, [{
  return getImm(N, (unsigned)N->getZExtValue() - 32);
}]>;

// shamt must fit in 6 bits.
def immZExt6 : ImmLeaf<i32, [{return Imm == (Imm & 0x3f);}]>;

// Is a 32-bit int.
def immSExt32 : ImmLeaf<i64, [{return isInt<32>(Imm);}]>;

// Transformation Function - get the higher 16 bits.
def HIGHER : SDNodeXForm<imm, [{
  return getImm(N, (N->getZExtValue() >> 32) & 0xFFFF);
}]>;

// Transformation Function - get the highest 16 bits.
def HIGHEST : SDNodeXForm<imm, [{
  return getImm(N, (N->getZExtValue() >> 48) & 0xFFFF);
}]>;

//===----------------------------------------------------------------------===//
// Instructions specific format
//===----------------------------------------------------------------------===//
// Shifts
// 64-bit shift instructions.
class shift_rotate_imm64<bits<6> func, bits<5> isRotate, string instr_asm,
                         SDNode OpNode>:
  shift_rotate_imm<func, isRotate, instr_asm, OpNode, immZExt6, shamt,
                   CPU64Regs>;

// Jump and Link (Call)
let isCall=1, hasDelaySlot=1,
  // All calls clobber the non-callee saved registers...
  Defs = [AT, V0, V1, A0, A1, A2, A3, T0, T1, T2, T3, T4, T5, T6, T7, T8, T9,
          K0, K1, D0, D1, D2, D3, D4, D5, D6, D7, D8, D9], Uses = [GP] in {
  class JumpLink64<bits<6> op, string instr_asm>:
    FJ<op, (outs), (ins calltarget64:$target, variable_ops),
       !strconcat(instr_asm, "\t$target"), [(MipsJmpLink imm:$target)],
       IIBranch>;

  class JumpLinkReg64<bits<6> op, bits<6> func, string instr_asm>:
    FR<op, func, (outs), (ins CPU64Regs:$rs, variable_ops),
       !strconcat(instr_asm, "\t$rs"),
       [(MipsJmpLink CPU64Regs:$rs)], IIBranch> {
    let rt = 0;
    let rd = 31;
    let shamt = 0;
  }

  class BranchLink64<string instr_asm>:
    FI<0x1, (outs), (ins CPU64Regs:$rs, brtarget:$imm16, variable_ops),
       !strconcat(instr_asm, "\t$rs, $imm16"), [], IIBranch>;
}

// Mul, Div
class Mult64<bits<6> func, string instr_asm, InstrItinClass itin>:
  Mult<func, instr_asm, itin, CPU64Regs, [HI64, LO64]>;
class Div64<SDNode op, bits<6> func, string instr_asm, InstrItinClass itin>:
  Div<op, func, instr_asm, itin, CPU64Regs, [HI64, LO64]>;

multiclass Atomic2Ops64<PatFrag Op, string Opstr> {
  def #NAME# : Atomic2Ops<Op, Opstr, CPU64Regs, CPURegs>, Requires<[NotN64]>;
  def _P8    : Atomic2Ops<Op, Opstr, CPU64Regs, CPU64Regs>, Requires<[IsN64]>;
}

multiclass AtomicCmpSwap64<PatFrag Op, string Width>  {
  def #NAME# : AtomicCmpSwap<Op, Width, CPU64Regs, CPURegs>, Requires<[NotN64]>;
  def _P8    : AtomicCmpSwap<Op, Width, CPU64Regs, CPU64Regs>,
               Requires<[IsN64]>;
}

let usesCustomInserter = 1, Predicates = [HasMips64] in {
  defm ATOMIC_LOAD_ADD_I64  : Atomic2Ops64<atomic_load_add_64, "load_add_64">;
  defm ATOMIC_LOAD_SUB_I64  : Atomic2Ops64<atomic_load_sub_64, "load_sub_64">;
  defm ATOMIC_LOAD_AND_I64  : Atomic2Ops64<atomic_load_and_64, "load_and_64">;
  defm ATOMIC_LOAD_OR_I64   : Atomic2Ops64<atomic_load_or_64, "load_or_64">;
  defm ATOMIC_LOAD_XOR_I64  : Atomic2Ops64<atomic_load_xor_64, "load_xor_64">;
  defm ATOMIC_LOAD_NAND_I64 : Atomic2Ops64<atomic_load_nand_64, "load_nand_64">;
  defm ATOMIC_SWAP_I64      : Atomic2Ops64<atomic_swap_64, "swap_64">;
  defm ATOMIC_CMP_SWAP_I64  : AtomicCmpSwap64<atomic_cmp_swap_64, "64">;
}

//===----------------------------------------------------------------------===//
// Instruction definition
//===----------------------------------------------------------------------===//

/// Arithmetic Instructions (ALU Immediate)
def DADDiu   : ArithLogicI<0x19, "daddiu", add, simm16_64, immSExt16,
                           CPU64Regs>;
def DANDi    : ArithLogicI<0x0c, "andi", and, uimm16_64, immZExt16, CPU64Regs>;
def SLTi64   : SetCC_I<0x0a, "slti", setlt, simm16_64, immSExt16, CPU64Regs>;
def SLTiu64  : SetCC_I<0x0b, "sltiu", setult, simm16_64, immSExt16, CPU64Regs>;
def ORi64    : ArithLogicI<0x0d, "ori", or, uimm16_64, immZExt16, CPU64Regs>;
def XORi64   : ArithLogicI<0x0e, "xori", xor, uimm16_64, immZExt16, CPU64Regs>;
def LUi64    : LoadUpper<0x0f, "lui", CPU64Regs, uimm16_64>;

/// Arithmetic Instructions (3-Operand, R-Type)
def DADDu    : ArithLogicR<0x00, 0x2d, "daddu", add, IIAlu, CPU64Regs, 1>;
def DSUBu    : ArithLogicR<0x00, 0x2f, "dsubu", sub, IIAlu, CPU64Regs>;
def SLT64    : SetCC_R<0x00, 0x2a, "slt", setlt, CPU64Regs>;
def SLTu64   : SetCC_R<0x00, 0x2b, "sltu", setult, CPU64Regs>;
def AND64    : ArithLogicR<0x00, 0x24, "and", and, IIAlu, CPU64Regs, 1>;
def OR64     : ArithLogicR<0x00, 0x25, "or", or, IIAlu, CPU64Regs, 1>;
def XOR64    : ArithLogicR<0x00, 0x26, "xor", xor, IIAlu, CPU64Regs, 1>;
def NOR64    : LogicNOR<0x00, 0x27, "nor", CPU64Regs>;

/// Shift Instructions
def DSLL     : shift_rotate_imm64<0x38, 0x00, "dsll", shl>;
def DSRL     : shift_rotate_imm64<0x3a, 0x00, "dsrl", srl>;
def DSRA     : shift_rotate_imm64<0x3b, 0x00, "dsra", sra>;
def DSLLV    : shift_rotate_reg<0x24, 0x00, "dsllv", shl, CPU64Regs>;
def DSRLV    : shift_rotate_reg<0x26, 0x00, "dsrlv", srl, CPU64Regs>;
def DSRAV    : shift_rotate_reg<0x27, 0x00, "dsrav", sra, CPU64Regs>;

// Rotate Instructions
let Predicates = [HasMips64r2] in {
  def DROTR    : shift_rotate_imm64<0x3a, 0x01, "drotr", rotr>;
  def DROTRV   : shift_rotate_reg<0x16, 0x01, "drotrv", rotr, CPU64Regs>;
}

/// Load and Store Instructions
///  aligned 
defm LB64    : LoadM64<0x20, "lb",  sextloadi8>;
defm LBu64   : LoadM64<0x24, "lbu", zextloadi8>;
defm LH64    : LoadM64<0x21, "lh",  sextloadi16_a>;
defm LHu64   : LoadM64<0x25, "lhu", zextloadi16_a>;
defm LW64    : LoadM64<0x23, "lw",  sextloadi32_a>;
defm LWu64   : LoadM64<0x27, "lwu", zextloadi32_a>;
defm SB64    : StoreM64<0x28, "sb", truncstorei8>;
defm SH64    : StoreM64<0x29, "sh", truncstorei16_a>;
defm SW64    : StoreM64<0x2b, "sw", truncstorei32_a>;
defm LD      : LoadM64<0x37, "ld",  load_a>;
defm SD      : StoreM64<0x3f, "sd", store_a>;

///  unaligned
defm ULH64     : LoadM64<0x21, "ulh",  sextloadi16_u, 1>;
defm ULHu64    : LoadM64<0x25, "ulhu", zextloadi16_u, 1>;
defm ULW64     : LoadM64<0x23, "ulw",  sextloadi32_u, 1>;
defm USH64     : StoreM64<0x29, "ush", truncstorei16_u, 1>;
defm USW64     : StoreM64<0x2b, "usw", truncstorei32_u, 1>;
defm ULD       : LoadM64<0x37, "uld",  load_u, 1>;
defm USD       : StoreM64<0x3f, "usd", store_u, 1>;

/// Load-linked, Store-conditional
def LLD    : LLBase<0x34, "lld", CPU64Regs, mem>, Requires<[NotN64]>;
def LLD_P8 : LLBase<0x34, "lld", CPU64Regs, mem64>, Requires<[IsN64]>;
def SCD    : SCBase<0x3c, "scd", CPU64Regs, mem>, Requires<[NotN64]>;
def SCD_P8 : SCBase<0x3c, "scd", CPU64Regs, mem64>, Requires<[IsN64]>;

/// Jump and Branch Instructions
def JR64   : JumpFR<0x00, 0x08, "jr", CPU64Regs>;
def JAL64  : JumpLink64<0x03, "jal">;
def JALR64 : JumpLinkReg64<0x00, 0x09, "jalr">;
def BEQ64  : CBranch<0x04, "beq", seteq, CPU64Regs>;
def BNE64  : CBranch<0x05, "bne", setne, CPU64Regs>;
def BGEZ64 : CBranchZero<0x01, 1, "bgez", setge, CPU64Regs>;
def BGTZ64 : CBranchZero<0x07, 0, "bgtz", setgt, CPU64Regs>;
def BLEZ64 : CBranchZero<0x07, 0, "blez", setle, CPU64Regs>;
def BLTZ64 : CBranchZero<0x01, 0, "bltz", setlt, CPU64Regs>;

/// Multiply and Divide Instructions.
def DMULT    : Mult64<0x1c, "dmult", IIImul>;
def DMULTu   : Mult64<0x1d, "dmultu", IIImul>;
def DSDIV    : Div64<MipsDivRem, 0x1e, "ddiv", IIIdiv>;
def DUDIV    : Div64<MipsDivRemU, 0x1f, "ddivu", IIIdiv>;

def MTHI64 : MoveToLOHI<0x11, "mthi", CPU64Regs, [HI64]>;
def MTLO64 : MoveToLOHI<0x13, "mtlo", CPU64Regs, [LO64]>;
def MFHI64 : MoveFromLOHI<0x10, "mfhi", CPU64Regs, [HI64]>;
def MFLO64 : MoveFromLOHI<0x12, "mflo", CPU64Regs, [LO64]>;

/// Count Leading
def DCLZ : CountLeading0<0x24, "dclz", CPU64Regs>;
def DCLO : CountLeading1<0x25, "dclo", CPU64Regs>;

/// Double Word Swap Bytes/HalfWords
def DSBH : SubwordSwap<0x24, 0x2, "dsbh", CPU64Regs>;
def DSHD : SubwordSwap<0x24, 0x5, "dshd", CPU64Regs>;

def LEA_ADDiu64 : EffectiveAddress<"daddiu\t$rt, $addr", CPU64Regs, mem_ea_64>;

let Uses = [SP_64] in
def DynAlloc64 : EffectiveAddress<"daddiu\t$rt, $addr", CPU64Regs, mem_ea_64>,
                 Requires<[IsN64]>;

def RDHWR64 : ReadHardware<CPU64Regs, HWRegs64>;

def DEXT : ExtBase<3, "dext", CPU64Regs>;
def DINS : InsBase<7, "dins", CPU64Regs>;

def DSLL64_32 : FR<0x3c, 0x00, (outs CPU64Regs:$rd), (ins CPURegs:$rt),
                   "dsll\t$rd, $rt, 32", [], IIAlu>;

def SLL64_32 : FR<0x0, 0x00, (outs CPU64Regs:$rd), (ins CPURegs:$rt),
                  "sll\t$rd, $rt, 0", [], IIAlu>;
def SLL64_64 : FR<0x0, 0x00, (outs CPU64Regs:$rd), (ins CPU64Regs:$rt),
                  "sll\t$rd, $rt, 0", [], IIAlu>;

//===----------------------------------------------------------------------===//
//  Arbitrary patterns that map to one or more instructions
//===----------------------------------------------------------------------===//

// Small immediates
def : Pat<(i64 immSExt16:$in),
          (DADDiu ZERO_64, imm:$in)>;
def : Pat<(i64 immZExt16:$in),
          (ORi64 ZERO_64, imm:$in)>;
def : Pat<(i64 immLUiOpnd:$in),
          (LUi64 (HI16 imm:$in))>;

// 32-bit immediates
def : Pat<(i64 immSExt32:$imm),
          (ORi64 (LUi64 (HI16 imm:$imm)), (LO16 imm:$imm))>;

// Arbitrary immediates
def : Pat<(i64 imm:$imm),
          (ORi64 (DSLL (ORi64 (DSLL (ORi64 (LUi64 (HIGHEST imm:$imm)),
           (HIGHER imm:$imm)), 16), (HI16 imm:$imm)), 16),
           (LO16 imm:$imm))>;

// extended loads
let Predicates = [NotN64] in {
  def : Pat<(i64 (extloadi1  addr:$src)), (LB64 addr:$src)>;
  def : Pat<(i64 (extloadi8  addr:$src)), (LB64 addr:$src)>;
  def : Pat<(i64 (extloadi16_a addr:$src)), (LH64 addr:$src)>;
  def : Pat<(i64 (extloadi16_u addr:$src)), (ULH64 addr:$src)>;
  def : Pat<(i64 (extloadi32_a addr:$src)), (LW64 addr:$src)>;
  def : Pat<(i64 (extloadi32_u addr:$src)), (ULW64 addr:$src)>;
  def : Pat<(zextloadi32_u addr:$a), (DSRL (DSLL (ULW64 addr:$a), 32), 32)>;
}
let Predicates = [IsN64] in {
  def : Pat<(i64 (extloadi1  addr:$src)), (LB64_P8 addr:$src)>;
  def : Pat<(i64 (extloadi8  addr:$src)), (LB64_P8 addr:$src)>;
  def : Pat<(i64 (extloadi16_a addr:$src)), (LH64_P8 addr:$src)>;
  def : Pat<(i64 (extloadi16_u addr:$src)), (ULH64_P8 addr:$src)>;
  def : Pat<(i64 (extloadi32_a addr:$src)), (LW64_P8 addr:$src)>;
  def : Pat<(i64 (extloadi32_u addr:$src)), (ULW64_P8 addr:$src)>;
  def : Pat<(zextloadi32_u addr:$a), (DSRL (DSLL (ULW64_P8 addr:$a), 32), 32)>;
}

// hi/lo relocs
def : Pat<(MipsHi tglobaladdr:$in), (LUi64 tglobaladdr:$in)>;
def : Pat<(MipsHi tblockaddress:$in), (LUi64 tblockaddress:$in)>;
def : Pat<(MipsHi tjumptable:$in), (LUi64 tjumptable:$in)>;
def : Pat<(MipsHi tconstpool:$in), (LUi64 tconstpool:$in)>;
def : Pat<(MipsHi tglobaltlsaddr:$in), (LUi64 tglobaltlsaddr:$in)>;

def : Pat<(MipsLo tglobaladdr:$in), (DADDiu ZERO_64, tglobaladdr:$in)>;
def : Pat<(MipsLo tblockaddress:$in), (DADDiu ZERO_64, tblockaddress:$in)>;
def : Pat<(MipsLo tjumptable:$in), (DADDiu ZERO_64, tjumptable:$in)>;
def : Pat<(MipsLo tconstpool:$in), (DADDiu ZERO_64, tconstpool:$in)>;
def : Pat<(MipsLo tglobaltlsaddr:$in), (DADDiu ZERO_64, tglobaltlsaddr:$in)>;

def : Pat<(add CPU64Regs:$hi, (MipsLo tglobaladdr:$lo)),
          (DADDiu CPU64Regs:$hi, tglobaladdr:$lo)>;
def : Pat<(add CPU64Regs:$hi, (MipsLo tblockaddress:$lo)),
          (DADDiu CPU64Regs:$hi, tblockaddress:$lo)>;
def : Pat<(add CPU64Regs:$hi, (MipsLo tjumptable:$lo)),
          (DADDiu CPU64Regs:$hi, tjumptable:$lo)>;
def : Pat<(add CPU64Regs:$hi, (MipsLo tconstpool:$lo)),
          (DADDiu CPU64Regs:$hi, tconstpool:$lo)>;
def : Pat<(add CPU64Regs:$hi, (MipsLo tglobaltlsaddr:$lo)),
          (DADDiu CPU64Regs:$hi, tglobaltlsaddr:$lo)>;

def : WrapperPat<tglobaladdr, DADDiu, GP_64>;
def : WrapperPat<tconstpool, DADDiu, GP_64>;
def : WrapperPat<texternalsym, DADDiu, GP_64>;
def : WrapperPat<tblockaddress, DADDiu, GP_64>;
def : WrapperPat<tjumptable, DADDiu, GP_64>;
def : WrapperPat<tglobaltlsaddr, DADDiu, GP_64>;

defm : BrcondPats<CPU64Regs, BEQ64, BNE64, SLT64, SLTu64, SLTi64, SLTiu64,
                  ZERO_64>;

// setcc patterns
defm : SeteqPats<CPU64Regs, SLTiu64, XOR64, SLTu64, ZERO_64>;
defm : SetlePats<CPU64Regs, SLT64, SLTu64>;
defm : SetgtPats<CPU64Regs, SLT64, SLTu64>;
defm : SetgePats<CPU64Regs, SLT64, SLTu64>;
defm : SetgeImmPats<CPU64Regs, SLTi64, SLTiu64>;

// select MipsDynAlloc
def : Pat<(MipsDynAlloc addr:$f), (DynAlloc64 addr:$f)>, Requires<[IsN64]>;

// truncate
def : Pat<(i32 (trunc CPU64Regs:$src)),
          (SLL (EXTRACT_SUBREG CPU64Regs:$src, sub_32), 0)>, Requires<[IsN64]>;
 
// 32-to-64-bit extension
def : Pat<(i64 (anyext CPURegs:$src)), (SLL64_32 CPURegs:$src)>;
def : Pat<(i64 (zext CPURegs:$src)), (DSRL (DSLL64_32 CPURegs:$src), 32)>;
def : Pat<(i64 (sext CPURegs:$src)), (SLL64_32 CPURegs:$src)>;

// Sign extend in register
def : Pat<(i64 (sext_inreg CPU64Regs:$src, i32)), (SLL64_64 CPU64Regs:$src)>;

// bswap pattern
def : Pat<(bswap CPU64Regs:$rt), (DSHD (DSBH CPU64Regs:$rt))>;
