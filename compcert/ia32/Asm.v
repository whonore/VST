(* *********************************************************************)
(*                                                                     *)
(*              The Compcert verified compiler                         *)
(*                                                                     *)
(*          Xavier Leroy, INRIA Paris-Rocquencourt                     *)
(*                                                                     *)
(*  Copyright Institut National de Recherche en Informatique et en     *)
(*  Automatique.  All rights reserved.  This file is distributed       *)
(*  under the terms of the INRIA Non-Commercial License Agreement.     *)
(*                                                                     *)
(* *********************************************************************)

(** Abstract syntax and semantics for IA32 assembly language *)

Require Import Coqlib.
Require Import Maps.
Require Import AST.
Require Import Integers.
Require Import Floats.
Require Import Values.
Require Import Memory.
Require Import Events.
Require Import Globalenvs.
Require Import Smallstep.
Require Import Locations.
Require Import Stacklayout.
Require Import Conventions.

(** * Abstract syntax *)

(** ** Registers. *)

(** Integer registers. *)

Inductive ireg: Type :=
  | EAX: ireg  | EBX: ireg  | ECX: ireg  | EDX: ireg
  | ESI: ireg  | EDI: ireg  | EBP: ireg  | ESP: ireg.

(** Floating-point registers, i.e. SSE2 registers *)

Inductive freg: Type :=
  | XMM0: freg  | XMM1: freg  | XMM2: freg  | XMM3: freg
  | XMM4: freg  | XMM5: freg  | XMM6: freg  | XMM7: freg.

Lemma ireg_eq: forall (x y: ireg), {x=y} + {x<>y}.
Proof. decide equality. Defined.

Lemma freg_eq: forall (x y: freg), {x=y} + {x<>y}.
Proof. decide equality. Defined.

(** Bits of the flags register. *)

Inductive crbit: Type :=
  | ZF | CF | PF | SF | OF.

(** All registers modeled here. *)

Inductive preg: Type :=
  | PC: preg                            (**r program counter *)
  | IR: ireg -> preg                    (**r integer register *)
  | FR: freg -> preg                    (**r XMM register *)
  | ST0: preg                           (**r top of FP stack *)
  | CR: crbit -> preg                   (**r bit of the flags register *)
  | RA: preg.                   (**r pseudo-reg representing return address *)

Coercion IR: ireg >-> preg.
Coercion FR: freg >-> preg.
Coercion CR: crbit >-> preg.

(** Conventional names for stack pointer ([SP]) and return address ([RA]) *)

Notation SP := ESP (only parsing).

(** ** Instruction set. *)

Definition label := positive.

(** General form of an addressing mode. *)

Inductive addrmode: Type :=
  | Addrmode (base: option ireg)
             (ofs: option (ireg * int))
             (const: int + ident * int).

(** Testable conditions (for conditional jumps and more). *)

Inductive testcond: Type :=
  | Cond_e | Cond_ne
  | Cond_b | Cond_be | Cond_ae | Cond_a
  | Cond_l | Cond_le | Cond_ge | Cond_g
  | Cond_p | Cond_np.

(** Instructions.  IA32 instructions accept many combinations of
  registers, memory references and immediate constants as arguments.
  Here, we list only the combinations that we actually use.

  Naming conventions:
- [r]: integer register operand
- [f]: XMM register operand
- [m]: memory operand
- [i]: immediate integer operand
- [s]: immediate symbol operand
- [l]: immediate label operand
- [cl]: the [CL] register

  For two-operand instructions, the first suffix describes the result
  (and first argument), the second suffix describes the second argument.
*)

Inductive instruction: Type :=
  (** Moves *)
  | Pmov_rr (rd: ireg) (r1: ireg)       (**r [mov] (32-bit int) *)
  | Pmov_ri (rd: ireg) (n: int)
  | Pmov_ra (rd: ireg) (id: ident)
  | Pmov_rm (rd: ireg) (a: addrmode)
  | Pmov_mr (a: addrmode) (rs: ireg)
  | Pmovsd_ff (rd: freg) (r1: freg)     (**r [movsd] (single 64-bit float) *)
  | Pmovsd_fi (rd: freg) (n: float)     (**r (pseudo-instruction) *)
  | Pmovsd_fm (rd: freg) (a: addrmode)
  | Pmovsd_mf (a: addrmode) (r1: freg)
  | Pmovss_fi (rd: freg) (n: float32)   (**r [movss] (single 32-bit float) *)
  | Pmovss_fm (rd: freg) (a: addrmode)
  | Pmovss_mf (a: addrmode) (r1: freg)
  | Pfldl_m (a: addrmode)               (**r [fld] double precision *)
  | Pfstpl_m (a: addrmode)              (**r [fstp] double precision *)
  | Pflds_m (a: addrmode)               (**r [fld] simple precision *)
  | Pfstps_m (a: addrmode)              (**r [fstp] simple precision *)
  | Pxchg_rr (r1: ireg) (r2: ireg)      (**r register-register exchange *)
  (** Moves with conversion *)
  | Pmovb_mr (a: addrmode) (rs: ireg)   (**r [mov] (8-bit int) *)
  | Pmovw_mr (a: addrmode) (rs: ireg)   (**r [mov] (16-bit int) *)
  | Pmovzb_rr (rd: ireg) (rs: ireg)     (**r [movzb] (8-bit zero-extension) *)
  | Pmovzb_rm (rd: ireg) (a: addrmode)
  | Pmovsb_rr (rd: ireg) (rs: ireg)     (**r [movsb] (8-bit sign-extension) *)
  | Pmovsb_rm (rd: ireg) (a: addrmode)
  | Pmovzw_rr (rd: ireg) (rs: ireg)     (**r [movzw] (16-bit zero-extension) *)
  | Pmovzw_rm (rd: ireg) (a: addrmode)
  | Pmovsw_rr (rd: ireg) (rs: ireg)     (**r [movsw] (16-bit sign-extension) *)
  | Pmovsw_rm (rd: ireg) (a: addrmode)
  | Pcvtsd2ss_ff (rd: freg) (r1: freg)  (**r conversion to single float *)
  | Pcvtss2sd_ff (rd: freg) (r1: freg)  (**r conversion to double float *)
  | Pcvttsd2si_rf (rd: ireg) (r1: freg) (**r double to signed int *)
  | Pcvtsi2sd_fr (rd: freg) (r1: ireg)  (**r signed int to double *)
  | Pcvttss2si_rf (rd: ireg) (r1: freg) (**r single to signed int *)
  | Pcvtsi2ss_fr (rd: freg) (r1: ireg)  (**r signed int to single *)
  (** Integer arithmetic *)
  | Plea (rd: ireg) (a: addrmode)
  | Pneg (rd: ireg)
  | Psub_rr (rd: ireg) (r1: ireg)
  | Pimul_rr (rd: ireg) (r1: ireg)
  | Pimul_ri (rd: ireg) (n: int)
  | Pimul_r (r1: ireg)
  | Pmul_r (r1: ireg)
  | Pdiv (r1: ireg)
  | Pidiv (r1: ireg)
  | Pand_rr (rd: ireg) (r1: ireg)
  | Pand_ri (rd: ireg) (n: int)
  | Por_rr (rd: ireg) (r1: ireg)
  | Por_ri (rd: ireg) (n: int)
  | Pxor_r (rd: ireg)                  (**r [xor] with self = set to zero *)
  | Pxor_rr (rd: ireg) (r1: ireg)
  | Pxor_ri (rd: ireg) (n: int)
  | Pnot (rd: ireg)
  | Psal_rcl (rd: ireg)
  | Psal_ri (rd: ireg) (n: int)
  | Pshr_rcl (rd: ireg)
  | Pshr_ri (rd: ireg) (n: int)
  | Psar_rcl (rd: ireg)
  | Psar_ri (rd: ireg) (n: int)
  | Pshld_ri (rd: ireg) (r1: ireg) (n: int)
  | Pror_ri (rd: ireg) (n: int)
  | Pcmp_rr (r1 r2: ireg)
  | Pcmp_ri (r1: ireg) (n: int)
  | Ptest_rr (r1 r2: ireg)
  | Ptest_ri (r1: ireg) (n: int)
  | Pcmov (c: testcond) (rd: ireg) (r1: ireg)
  | Psetcc (c: testcond) (rd: ireg)
  (** Floating-point arithmetic *)
  | Paddd_ff (rd: freg) (r1: freg)
  | Psubd_ff (rd: freg) (r1: freg)
  | Pmuld_ff (rd: freg) (r1: freg)
  | Pdivd_ff (rd: freg) (r1: freg)
  | Pnegd (rd: freg)
  | Pabsd (rd: freg)
  | Pcomisd_ff (r1 r2: freg)
  | Pxorpd_f (rd: freg)	              (**r [xor] with self = set to zero *)
  | Padds_ff (rd: freg) (r1: freg)
  | Psubs_ff (rd: freg) (r1: freg)
  | Pmuls_ff (rd: freg) (r1: freg)
  | Pdivs_ff (rd: freg) (r1: freg)
  | Pnegs (rd: freg)
  | Pabss (rd: freg)
  | Pcomiss_ff (r1 r2: freg)
  | Pxorps_f (rd: freg)	              (**r [xor] with self = set to zero *)
  (** Branches and calls *)
  | Pjmp_l (l: label)
  | Pjmp_s (symb: ident) (sg: signature)
  | Pjmp_r (r: ireg) (sg: signature)
  | Pjcc (c: testcond)(l: label)
  | Pjcc2 (c1 c2: testcond)(l: label)   (**r pseudo *)
  | Pjmptbl (r: ireg) (tbl: list label) (**r pseudo *)
  | Pcall_s (symb: ident) (sg: signature)
  | Pcall_r (r: ireg) (sg: signature)
  | Pret
  (** Saving and restoring registers *)
  | Pmov_rm_a (rd: ireg) (a: addrmode)  (**r like [Pmov_rm], using [Many32] chunk *)
  | Pmov_mr_a (a: addrmode) (rs: ireg)  (**r like [Pmov_mr], using [Many32] chunk *)
  | Pmovsd_fm_a (rd: freg) (a: addrmode) (**r like [Pmovsd_fm], using [Many64] chunk *)
  | Pmovsd_mf_a (a: addrmode) (r1: freg) (**r like [Pmovsd_mf], using [Many64] chunk *)
  (** Pseudo-instructions *)
  | Plabel(l: label)
  | Pallocframe(sz: Z)(ofs_ra ofs_link: int)
  | Pfreeframe(sz: Z)(ofs_ra ofs_link: int)
  | Pbuiltin(ef: external_function)(args: list (builtin_arg preg))(res: builtin_res preg)
  (** Instructions not generated by [Asmgen] *)
  | Padc_ri (rd: ireg) (n: int)
  | Padc_rr (rd: ireg) (r2: ireg)
  | Padd_mi (a: addrmode) (n: int)
  | Padd_ri (rd: ireg) (n: int)
  | Padd_rr (rd: ireg) (r2: ireg)
  | Pbsf (rd: ireg) (r1: ireg)
  | Pbsr (rd: ireg) (r1: ireg)
  | Pbswap (rd: ireg)
  | Pbswap16 (rd: ireg)
  | Pcfi_adjust (n: int)
  | Pfmadd132 (rd: freg) (r2: freg) (r3: freg)
  | Pfmadd213 (rd: freg) (r2: freg) (r3: freg)
  | Pfmadd231 (rd: freg) (r2: freg) (r3: freg)
  | Pfmsub132 (rd: freg) (r2: freg) (r3: freg)
  | Pfmsub213 (rd: freg) (r2: freg) (r3: freg)
  | Pfmsub231 (rd: freg) (r2: freg) (r3: freg)
  | Pfnmadd132 (rd: freg) (r2: freg) (r3: freg)
  | Pfnmadd213 (rd: freg) (r2: freg) (r3: freg)
  | Pfnmadd231 (rd: freg) (r2: freg) (r3: freg)
  | Pfnmsub132 (rd: freg) (r2: freg) (r3: freg)
  | Pfnmsub213 (rd: freg) (r2: freg) (r3: freg)
  | Pfnmsub231 (rd: freg) (r2: freg) (r3: freg)
  | Pmaxsd (rd: freg) (r2: freg)
  | Pminsd (rd: freg) (r2: freg)
  | Pmovb_rm (rd: ireg) (a: addrmode)
  | Pmovq_mr  (a: addrmode) (rs: freg)
  | Pmovq_rm (rd: freg) (a: addrmode)
  | Pmovsb
  | Pmovsw
  | Pmovw_rm (rd: ireg) (ad: addrmode)
  | Prep_movsl
  | Psbb_rr (rd: ireg) (r2: ireg)
  | Psqrtsd (rd: freg) (r1: freg)
  | Psub_ri (rd: ireg) (n: int).

Definition code := list instruction.
Record function : Type := mkfunction { fn_sig: signature; fn_code: code }.
Definition fundef := AST.fundef function.
Definition program := AST.program fundef unit.

(** * Operational semantics *)

Lemma preg_eq: forall (x y: preg), {x=y} + {x<>y}.
Proof. decide equality. apply ireg_eq. apply freg_eq. decide equality. Defined.

Module PregEq.
  Definition t := preg.
  Definition eq := preg_eq.
End PregEq.

Module Pregmap := EMap(PregEq).

Definition regset := Pregmap.t val.
Definition genv := Genv.t fundef unit.

Notation "a # b" := (a b) (at level 1, only parsing).
Notation "a # b <- c" := (Pregmap.set b c a) (at level 1, b at next level).

(** Undefining some registers *)

Fixpoint undef_regs (l: list preg) (rs: regset) : regset :=
  match l with
  | nil => rs
  | r :: l' => undef_regs l' (rs#r <- Vundef)
  end.

(** Assigning a register pair *)

Definition set_pair (p: rpair preg) (v: val) (rs: regset) : regset :=
  match p with
  | One r => rs#r <- v
  | Twolong rhi rlo => rs#rhi <- (Val.hiword v) #rlo <- (Val.loword v)
  end.

(** Assigning the result of a builtin *)

Fixpoint set_res (res: builtin_res preg) (v: val) (rs: regset) : regset :=
  match res with
  | BR r => rs#r <- v
  | BR_none => rs
  | BR_splitlong hi lo => set_res lo (Val.loword v) (set_res hi (Val.hiword v) rs)
  end.

Section RELSEM.

(** Looking up instructions in a code sequence by position. *)

Fixpoint find_instr (pos: Z) (c: code) {struct c} : option instruction :=
  match c with
  | nil => None
  | i :: il => if zeq pos 0 then Some i else find_instr (pos - 1) il
  end.

(** Position corresponding to a label *)

Definition is_label (lbl: label) (instr: instruction) : bool :=
  match instr with
  | Plabel lbl' => if peq lbl lbl' then true else false
  | _ => false
  end.

Lemma is_label_correct:
  forall lbl instr,
  if is_label lbl instr then instr = Plabel lbl else instr <> Plabel lbl.
Proof.
  intros.  destruct instr; simpl; try discriminate.
  case (peq lbl l); intro; congruence.
Qed.

Fixpoint label_pos (lbl: label) (pos: Z) (c: code) {struct c} : option Z :=
  match c with
  | nil => None
  | instr :: c' =>
      if is_label lbl instr then Some (pos + 1) else label_pos lbl (pos + 1) c'
  end.

Variable ge: genv.

(** Evaluating an addressing mode *)

Definition eval_addrmode (a: addrmode) (rs: regset) : val :=
  match a with Addrmode base ofs const =>
    Val.add (match base with
              | None => Vzero
              | Some r => rs r
             end)
    (Val.add (match ofs with
              | None => Vzero
              | Some(r, sc) =>
                  if Int.eq sc Int.one then rs r else Val.mul (rs r) (Vint sc)
              end)
             (match const with
              | inl ofs => Vint ofs
              | inr(id, ofs) => Genv.symbol_address ge id ofs
              end))
  end.

(** Performing a comparison *)

(** Integer comparison between x and y:
-       ZF = 1 if x = y, 0 if x != y
-       CF = 1 if x <u y, 0 if x >=u y
-       SF = 1 if x - y is negative, 0 if x - y is positive
-       OF = 1 if x - y overflows (signed), 0 if not
-       PF is undefined
*)

Definition compare_ints (x y: val) (rs: regset) (m: mem): regset :=
  rs #ZF  <- (Val.cmpu (Mem.valid_pointer m) Ceq x y)
     #CF  <- (Val.cmpu (Mem.valid_pointer m) Clt x y)
     #SF  <- (Val.negative (Val.sub x y))
     #OF  <- (Val.sub_overflow x y)
     #PF  <- Vundef.

(** Floating-point comparison between x and y:
-       ZF = 1 if x=y or unordered, 0 if x<>y
-       CF = 1 if x<y or unordered, 0 if x>=y
-       PF = 1 if unordered, 0 if ordered.
-       SF and 0F are undefined
*)

Definition compare_floats (vx vy: val) (rs: regset) : regset :=
  match vx, vy with
  | Vfloat x, Vfloat y =>
      rs #ZF  <- (Val.of_bool (negb (Float.cmp Cne x y)))
         #CF  <- (Val.of_bool (negb (Float.cmp Cge x y)))
         #PF  <- (Val.of_bool (negb (Float.cmp Ceq x y || Float.cmp Clt x y || Float.cmp Cgt x y)))
         #SF  <- Vundef
         #OF  <- Vundef
  | _, _ =>
      undef_regs (CR ZF :: CR CF :: CR PF :: CR SF :: CR OF :: nil) rs
  end.

Definition compare_floats32 (vx vy: val) (rs: regset) : regset :=
  match vx, vy with
  | Vsingle x, Vsingle y =>
      rs #ZF  <- (Val.of_bool (negb (Float32.cmp Cne x y)))
         #CF  <- (Val.of_bool (negb (Float32.cmp Cge x y)))
         #PF  <- (Val.of_bool (negb (Float32.cmp Ceq x y || Float32.cmp Clt x y || Float32.cmp Cgt x y)))
         #SF  <- Vundef
         #OF  <- Vundef
  | _, _ =>
      undef_regs (CR ZF :: CR CF :: CR PF :: CR SF :: CR OF :: nil) rs
  end.

(** Testing a condition *)

Definition eval_testcond (c: testcond) (rs: regset) : option bool :=
  match c with
  | Cond_e =>
      match rs ZF with
      | Vint n => Some (Int.eq n Int.one)
      | _ => None
      end
  | Cond_ne =>
      match rs ZF with
      | Vint n => Some (Int.eq n Int.zero)
      | _ => None
      end
  | Cond_b =>
      match rs CF with
      | Vint n => Some (Int.eq n Int.one)
      | _ => None
      end
  | Cond_be =>
      match rs CF, rs ZF with
      | Vint c, Vint z => Some (Int.eq c Int.one || Int.eq z Int.one)
      | _, _ => None
      end
  | Cond_ae =>
      match rs CF with
      | Vint n => Some (Int.eq n Int.zero)
      | _ => None
      end
  | Cond_a =>
      match rs CF, rs ZF with
      | Vint c, Vint z => Some (Int.eq c Int.zero && Int.eq z Int.zero)
      | _, _ => None
      end
  | Cond_l =>
      match rs OF, rs SF with
      | Vint o, Vint s => Some (Int.eq (Int.xor o s) Int.one)
      | _, _ => None
      end
  | Cond_le =>
      match rs OF, rs SF, rs ZF with
      | Vint o, Vint s, Vint z => Some (Int.eq (Int.xor o s) Int.one || Int.eq z Int.one)
      | _, _, _ => None
      end
  | Cond_ge =>
      match rs OF, rs SF with
      | Vint o, Vint s => Some (Int.eq (Int.xor o s) Int.zero)
      | _, _ => None
      end
  | Cond_g =>
      match rs OF, rs SF, rs ZF with
      | Vint o, Vint s, Vint z => Some (Int.eq (Int.xor o s) Int.zero && Int.eq z Int.zero)
      | _, _, _ => None
      end
  | Cond_p =>
      match rs PF with
      | Vint n => Some (Int.eq n Int.one)
      | _ => None
      end
  | Cond_np =>
      match rs PF with
      | Vint n => Some (Int.eq n Int.zero)
      | _ => None
      end
  end.

(** The semantics is purely small-step and defined as a function
  from the current state (a register set + a memory state)
  to either [Next rs' m'] where [rs'] and [m'] are the updated register
  set and memory state after execution of the instruction at [rs#PC],
  or [Stuck] if the processor is stuck. *)

Inductive outcome: Type :=
  | Next: regset -> mem -> outcome
  | Stuck: outcome.

(** Manipulations over the [PC] register: continuing with the next
  instruction ([nextinstr]) or branching to a label ([goto_label]).
  [nextinstr_nf] is a variant of [nextinstr] that sets condition flags
  to [Vundef] in addition to incrementing the [PC]. *)

Definition nextinstr (rs: regset) :=
  rs#PC <- (Val.add rs#PC Vone).

Definition nextinstr_nf (rs: regset) : regset :=
  nextinstr (undef_regs (CR ZF :: CR CF :: CR PF :: CR SF :: CR OF :: nil) rs).

Definition goto_label (f: function) (lbl: label) (rs: regset) (m: mem) :=
  match label_pos lbl 0 (fn_code f) with
  | None => Stuck
  | Some pos =>
      match rs#PC with
      | Vptr b ofs => Next (rs#PC <- (Vptr b (Int.repr pos))) m
      | _ => Stuck
    end
  end.

(** Auxiliaries for memory accesses. *)

Definition exec_load (chunk: memory_chunk) (m: mem)
                     (a: addrmode) (rs: regset) (rd: preg) :=
  match Mem.loadv chunk m (eval_addrmode a rs) with
  | Some v => Next (nextinstr_nf (rs#rd <- v)) m
  | None => Stuck
  end.

Definition exec_store (chunk: memory_chunk) (m: mem)
                      (a: addrmode) (rs: regset) (r1: preg)
                      (destroyed: list preg) :=
  match Mem.storev chunk m (eval_addrmode a rs) (rs r1) with
  | Some m' => Next (nextinstr_nf (undef_regs destroyed rs)) m'
  | None => Stuck
  end.

(** Execution of a single instruction [i] in initial state
    [rs] and [m].  Return updated state.  For instructions
    that correspond to actual IA32 instructions, the cases are
    straightforward transliterations of the informal descriptions
    given in the IA32 reference manuals.  For pseudo-instructions,
    refer to the informal descriptions given above.

    Note that we set to [Vundef] the registers used as temporaries by
    the expansions of the pseudo-instructions, so that the IA32 code
    we generate cannot use those registers to hold values that must
    survive the execution of the pseudo-instruction.

    Concerning condition flags, the comparison instructions set them
    accurately; other instructions (moves, [lea]) preserve them;
    and all other instruction set those flags to [Vundef], to reflect
    the fact that the processor updates some or all of those flags,
    but we do not need to model this precisely.
*)

Definition exec_instr (f: function) (i: instruction) (rs: regset) (m: mem) : outcome :=
  match i with
  (** Moves *)
  | Pmov_rr rd r1 =>
      Next (nextinstr (rs#rd <- (rs r1))) m
  | Pmov_ri rd n =>
      Next (nextinstr_nf (rs#rd <- (Vint n))) m
  | Pmov_ra rd id =>
      Next (nextinstr_nf (rs#rd <- (Genv.symbol_address ge id Int.zero))) m
  | Pmov_rm rd a =>
      exec_load Mint32 m a rs rd
  | Pmov_mr a r1 =>
      exec_store Mint32 m a rs r1 nil
  | Pmovsd_ff rd r1 =>
      Next (nextinstr (rs#rd <- (rs r1))) m
  | Pmovsd_fi rd n =>
      Next (nextinstr (rs#rd <- (Vfloat n))) m
  | Pmovsd_fm rd a =>
      exec_load Mfloat64 m a rs rd
  | Pmovsd_mf a r1 =>
      exec_store Mfloat64 m a rs r1 nil
  | Pmovss_fi rd n =>
      Next (nextinstr (rs#rd <- (Vsingle n))) m
  | Pmovss_fm rd a =>
      exec_load Mfloat32 m a rs rd
  | Pmovss_mf a r1 =>
      exec_store Mfloat32 m a rs r1 nil
  | Pfldl_m a =>
      exec_load Mfloat64 m a rs ST0
  | Pfstpl_m a =>
      exec_store Mfloat64 m a rs ST0 (ST0 :: nil)
  | Pflds_m a =>
      exec_load Mfloat32 m a rs ST0
  | Pfstps_m a =>
      exec_store Mfloat32 m a rs ST0 (ST0 :: nil)
  | Pxchg_rr r1 r2 =>
      Next (nextinstr (rs#r1 <- (rs r2) #r2 <- (rs r1))) m
  (** Moves with conversion *)
  | Pmovb_mr a r1 =>
      exec_store Mint8unsigned m a rs r1 nil
  | Pmovw_mr a r1 =>
      exec_store Mint16unsigned m a rs r1 nil
  | Pmovzb_rr rd r1 =>
      Next (nextinstr (rs#rd <- (Val.zero_ext 8 rs#r1))) m
  | Pmovzb_rm rd a =>
      exec_load Mint8unsigned m a rs rd
  | Pmovsb_rr rd r1 =>
      Next (nextinstr (rs#rd <- (Val.sign_ext 8 rs#r1))) m
  | Pmovsb_rm rd a =>
      exec_load Mint8signed m a rs rd
  | Pmovzw_rr rd r1 =>
      Next (nextinstr (rs#rd <- (Val.zero_ext 16 rs#r1))) m
  | Pmovzw_rm rd a =>
      exec_load Mint16unsigned m a rs rd
  | Pmovsw_rr rd r1 =>
      Next (nextinstr (rs#rd <- (Val.sign_ext 16 rs#r1))) m
  | Pmovsw_rm rd a =>
      exec_load Mint16signed m a rs rd
  | Pcvtsd2ss_ff rd r1 =>
      Next (nextinstr (rs#rd <- (Val.singleoffloat rs#r1))) m
  | Pcvtss2sd_ff rd r1 =>
      Next (nextinstr (rs#rd <- (Val.floatofsingle rs#r1))) m
  | Pcvttsd2si_rf rd r1 =>
      Next (nextinstr (rs#rd <- (Val.maketotal (Val.intoffloat rs#r1)))) m
  | Pcvtsi2sd_fr rd r1 =>
      Next (nextinstr (rs#rd <- (Val.maketotal (Val.floatofint rs#r1)))) m
  | Pcvttss2si_rf rd r1 =>
      Next (nextinstr (rs#rd <- (Val.maketotal (Val.intofsingle rs#r1)))) m
  | Pcvtsi2ss_fr rd r1 =>
      Next (nextinstr (rs#rd <- (Val.maketotal (Val.singleofint rs#r1)))) m
  (** Integer arithmetic *)
  | Plea rd a =>
      Next (nextinstr (rs#rd <- (eval_addrmode a rs))) m
  | Pneg rd =>
      Next (nextinstr_nf (rs#rd <- (Val.neg rs#rd))) m
  | Psub_rr rd r1 =>
      Next (nextinstr_nf (rs#rd <- (Val.sub rs#rd rs#r1))) m
  | Pimul_rr rd r1 =>
      Next (nextinstr_nf (rs#rd <- (Val.mul rs#rd rs#r1))) m
  | Pimul_ri rd n =>
      Next (nextinstr_nf (rs#rd <- (Val.mul rs#rd (Vint n)))) m
  | Pimul_r r1 =>
      Next (nextinstr_nf (rs#EAX <- (Val.mul rs#EAX rs#r1)
                            #EDX <- (Val.mulhs rs#EAX rs#r1))) m
  | Pmul_r r1 =>
      Next (nextinstr_nf (rs#EAX <- (Val.mul rs#EAX rs#r1)
                            #EDX <- (Val.mulhu rs#EAX rs#r1))) m
  | Pdiv r1 =>
      let vn := rs#EAX in let vd := (rs#EDX <- Vundef)#r1 in
      match Val.divu vn vd, Val.modu vn vd with
      | Some vq, Some vr => Next (nextinstr_nf (rs#EAX <- vq #EDX <- vr)) m
      | _, _ => Stuck
      end
  | Pidiv r1 =>
      let vn := rs#EAX in let vd := (rs#EDX <- Vundef)#r1 in
      match Val.divs vn vd, Val.mods vn vd with
      | Some vq, Some vr => Next (nextinstr_nf (rs#EAX <- vq #EDX <- vr)) m
      | _, _ => Stuck
      end
  | Pand_rr rd r1 =>
      Next (nextinstr_nf (rs#rd <- (Val.and rs#rd rs#r1))) m
  | Pand_ri rd n =>
      Next (nextinstr_nf (rs#rd <- (Val.and rs#rd (Vint n)))) m
  | Por_rr rd r1 =>
      Next (nextinstr_nf (rs#rd <- (Val.or rs#rd rs#r1))) m
  | Por_ri rd n =>
      Next (nextinstr_nf (rs#rd <- (Val.or rs#rd (Vint n)))) m
  | Pxor_r rd =>
      Next (nextinstr_nf (rs#rd <- Vzero)) m
  | Pxor_rr rd r1 =>
      Next (nextinstr_nf (rs#rd <- (Val.xor rs#rd rs#r1))) m
  | Pxor_ri rd n =>
      Next (nextinstr_nf (rs#rd <- (Val.xor rs#rd (Vint n)))) m
  | Pnot rd =>
      Next (nextinstr_nf (rs#rd <- (Val.notint rs#rd))) m
  | Psal_rcl rd =>
      Next (nextinstr_nf (rs#rd <- (Val.shl rs#rd rs#ECX))) m
  | Psal_ri rd n =>
      Next (nextinstr_nf (rs#rd <- (Val.shl rs#rd (Vint n)))) m
  | Pshr_rcl rd =>
      Next (nextinstr_nf (rs#rd <- (Val.shru rs#rd rs#ECX))) m
  | Pshr_ri rd n =>
      Next (nextinstr_nf (rs#rd <- (Val.shru rs#rd (Vint n)))) m
  | Psar_rcl rd =>
      Next (nextinstr_nf (rs#rd <- (Val.shr rs#rd rs#ECX))) m
  | Psar_ri rd n =>
      Next (nextinstr_nf (rs#rd <- (Val.shr rs#rd (Vint n)))) m
  | Pshld_ri rd r1 n =>
      Next (nextinstr_nf
              (rs#rd <- (Val.or (Val.shl rs#rd (Vint n))
                                (Val.shru rs#r1 (Vint (Int.sub Int.iwordsize n)))))) m
  | Pror_ri rd n =>
      Next (nextinstr_nf (rs#rd <- (Val.ror rs#rd (Vint n)))) m
  | Pcmp_rr r1 r2 =>
      Next (nextinstr (compare_ints (rs r1) (rs r2) rs m)) m
  | Pcmp_ri r1 n =>
      Next (nextinstr (compare_ints (rs r1) (Vint n) rs m)) m
  | Ptest_rr r1 r2 =>
      Next (nextinstr (compare_ints (Val.and (rs r1) (rs r2)) Vzero rs m)) m
  | Ptest_ri r1 n =>
      Next (nextinstr (compare_ints (Val.and (rs r1) (Vint n)) Vzero rs m)) m
  | Pcmov c rd r1 =>
      match eval_testcond c rs with
      | Some true => Next (nextinstr (rs#rd <- (rs#r1))) m
      | Some false => Next (nextinstr rs) m
      | None => Next (nextinstr (rs#rd <- Vundef)) m
      end
  | Psetcc c rd =>
      Next (nextinstr (rs#rd <- (Val.of_optbool (eval_testcond c rs)))) m
  (** Arithmetic operations over double-precision floats *)
  | Paddd_ff rd r1 =>
      Next (nextinstr (rs#rd <- (Val.addf rs#rd rs#r1))) m
  | Psubd_ff rd r1 =>
      Next (nextinstr (rs#rd <- (Val.subf rs#rd rs#r1))) m
  | Pmuld_ff rd r1 =>
      Next (nextinstr (rs#rd <- (Val.mulf rs#rd rs#r1))) m
  | Pdivd_ff rd r1 =>
      Next (nextinstr (rs#rd <- (Val.divf rs#rd rs#r1))) m
  | Pnegd rd =>
      Next (nextinstr (rs#rd <- (Val.negf rs#rd))) m
  | Pabsd rd =>
      Next (nextinstr (rs#rd <- (Val.absf rs#rd))) m
  | Pcomisd_ff r1 r2 =>
      Next (nextinstr (compare_floats (rs r1) (rs r2) rs)) m
  | Pxorpd_f rd =>
      Next (nextinstr_nf (rs#rd <- (Vfloat Float.zero))) m
  (** Arithmetic operations over single-precision floats *)
  | Padds_ff rd r1 =>
      Next (nextinstr (rs#rd <- (Val.addfs rs#rd rs#r1))) m
  | Psubs_ff rd r1 =>
      Next (nextinstr (rs#rd <- (Val.subfs rs#rd rs#r1))) m
  | Pmuls_ff rd r1 =>
      Next (nextinstr (rs#rd <- (Val.mulfs rs#rd rs#r1))) m
  | Pdivs_ff rd r1 =>
      Next (nextinstr (rs#rd <- (Val.divfs rs#rd rs#r1))) m
  | Pnegs rd =>
      Next (nextinstr (rs#rd <- (Val.negfs rs#rd))) m
  | Pabss rd =>
      Next (nextinstr (rs#rd <- (Val.absfs rs#rd))) m
  | Pcomiss_ff r1 r2 =>
      Next (nextinstr (compare_floats32 (rs r1) (rs r2) rs)) m
  | Pxorps_f rd =>
      Next (nextinstr_nf (rs#rd <- (Vsingle Float32.zero))) m
  (** Branches and calls *)
  | Pjmp_l lbl =>
      goto_label f lbl rs m
  | Pjmp_s id sg =>
      Next (rs#PC <- (Genv.symbol_address ge id Int.zero)) m
  | Pjmp_r r sg =>
      Next (rs#PC <- (rs r)) m
  | Pjcc cond lbl =>
      match eval_testcond cond rs with
      | Some true => goto_label f lbl rs m
      | Some false => Next (nextinstr rs) m
      | None => Stuck
      end
  | Pjcc2 cond1 cond2 lbl =>
      match eval_testcond cond1 rs, eval_testcond cond2 rs with
      | Some true, Some true => goto_label f lbl rs m
      | Some _, Some _ => Next (nextinstr rs) m
      | _, _ => Stuck
      end
  | Pjmptbl r tbl =>
      match rs#r with
      | Vint n =>
          match list_nth_z tbl (Int.unsigned n) with
          | None => Stuck
          | Some lbl => goto_label f lbl rs m
          end
      | _ => Stuck
      end
  | Pcall_s id sg =>
      Next (rs#RA <- (Val.add rs#PC Vone) #PC <- (Genv.symbol_address ge id Int.zero)) m
  | Pcall_r r sg =>
      Next (rs#RA <- (Val.add rs#PC Vone) #PC <- (rs r)) m
  | Pret =>
      Next (rs#PC <- (rs#RA)) m
  (** Saving and restoring registers *)
  | Pmov_rm_a rd a =>
      exec_load Many32 m a rs rd
  | Pmov_mr_a a r1 =>
      exec_store Many32 m a rs r1 nil
  | Pmovsd_fm_a rd a =>
      exec_load Many64 m a rs rd
  | Pmovsd_mf_a a r1 =>
      exec_store Many64 m a rs r1 nil
  (** Pseudo-instructions *)
  | Plabel lbl =>
      Next (nextinstr rs) m
  | Pallocframe sz ofs_ra ofs_link =>
      let (m1, stk) := Mem.alloc m 0 sz in
      let sp := Vptr stk Int.zero in
      match Mem.storev Mint32 m1 (Val.add sp (Vint ofs_link)) rs#ESP with
      | None => Stuck
      | Some m2 =>
          match Mem.storev Mint32 m2 (Val.add sp (Vint ofs_ra)) rs#RA with
          | None => Stuck
          | Some m3 => Next (nextinstr (rs #EDX <- (rs#ESP) #ESP <- sp)) m3
          end
      end
  | Pfreeframe sz ofs_ra ofs_link =>
      match Mem.loadv Mint32 m (Val.add rs#ESP (Vint ofs_ra)) with
      | None => Stuck
      | Some ra =>
          match Mem.loadv Mint32 m (Val.add rs#ESP (Vint ofs_link)) with
          | None => Stuck
          | Some sp =>
              match rs#ESP with
              | Vptr stk ofs =>
                  match Mem.free m stk 0 sz with
                  | None => Stuck
                  | Some m' => Next (nextinstr (rs#ESP <- sp #RA <- ra)) m'
                  end
              | _ => Stuck
              end
          end
      end
  | Pbuiltin ef args res =>
      Stuck                             (**r treated specially below *)
  (** The following instructions and directives are not generated
      directly by [Asmgen], so we do not model them. *)
  | Padc_ri _ _
  | Padc_rr _ _
  | Padd_mi _ _
  | Padd_ri _ _
  | Padd_rr _ _
  | Pbsf _ _
  | Pbsr _ _
  | Pbswap _
  | Pbswap16 _
  | Pcfi_adjust _
  | Pfmadd132 _ _ _
  | Pfmadd213 _ _ _
  | Pfmadd231 _ _ _
  | Pfmsub132 _ _ _
  | Pfmsub213 _ _ _
  | Pfmsub231 _ _ _
  | Pfnmadd132 _ _ _
  | Pfnmadd213 _ _ _
  | Pfnmadd231 _ _ _
  | Pfnmsub132 _ _ _
  | Pfnmsub213 _ _ _
  | Pfnmsub231 _ _ _
  | Pmaxsd _ _
  | Pminsd _ _
  | Pmovb_rm _ _
  | Pmovq_rm _ _
  | Pmovq_mr _ _
  | Pmovsb
  | Pmovsw
  | Pmovw_rm _ _
  | Prep_movsl
  | Psbb_rr _ _
  | Psqrtsd _ _
  | Psub_ri _ _ => Stuck
  end.

(** Translation of the LTL/Linear/Mach view of machine registers
  to the Asm view.  *)

Definition preg_of (r: mreg) : preg :=
  match r with
  | AX => IR EAX
  | BX => IR EBX
  | CX => IR ECX
  | DX => IR EDX
  | SI => IR ESI
  | DI => IR EDI
  | BP => IR EBP
  | X0 => FR XMM0
  | X1 => FR XMM1
  | X2 => FR XMM2
  | X3 => FR XMM3
  | X4 => FR XMM4
  | X5 => FR XMM5
  | X6 => FR XMM6
  | X7 => FR XMM7
  | FP0 => ST0
  end.

(** Extract the values of the arguments of an external call.
    We exploit the calling conventions from module [Conventions], except that
    we use machine registers instead of locations. *)

Inductive extcall_arg (rs: regset) (m: mem): loc -> val -> Prop :=
  | extcall_arg_reg: forall r,
      extcall_arg rs m (R r) (rs (preg_of r))
  | extcall_arg_stack: forall ofs ty bofs v,
      bofs = Stacklayout.fe_ofs_arg + 4 * ofs ->
      Mem.loadv (chunk_of_type ty) m
                (Val.add (rs (IR ESP)) (Vint (Int.repr bofs))) = Some v ->
      extcall_arg rs m (S Outgoing ofs ty) v.

Inductive extcall_arg_pair (rs: regset) (m: mem): rpair loc -> val -> Prop :=
  | extcall_arg_one: forall l v,
      extcall_arg rs m l v ->
      extcall_arg_pair rs m (One l) v
  | extcall_arg_twolong: forall hi lo vhi vlo,
      extcall_arg rs m hi vhi ->
      extcall_arg rs m lo vlo ->
      extcall_arg_pair rs m (Twolong hi lo) (Val.longofwords vhi vlo).

Definition extcall_arguments
    (rs: regset) (m: mem) (sg: signature) (args: list val) : Prop :=
  list_forall2 (extcall_arg_pair rs m) (loc_arguments sg) args.

Definition loc_external_result (sg: signature) : rpair preg :=
  map_rpair preg_of (loc_result sg).

(** Execution of the instruction at [rs#PC]. *)

Inductive state: Type :=
  | State: regset -> mem -> state.

Definition get_mem (s:state) :=
  match s with
  | State _ m => m
  end.

Inductive step: state -> trace -> state -> Prop :=
  | exec_step_internal:
      forall b ofs f i rs m rs' m',
      rs PC = Vptr b ofs ->
      Genv.find_funct_ptr ge b = Some (Internal f) ->
      find_instr (Int.unsigned ofs) f.(fn_code) = Some i ->
      exec_instr f i rs m = Next rs' m' ->
      step (State rs m) E0 (State rs' m')
  | exec_step_builtin:
      forall b ofs f ef args res rs m vargs t vres rs' m',
      rs PC = Vptr b ofs ->
      Genv.find_funct_ptr ge b = Some (Internal f) ->
      find_instr (Int.unsigned ofs) f.(fn_code) = Some (Pbuiltin ef args res) ->
      eval_builtin_args ge rs (rs ESP) m args vargs ->
      external_call ef ge vargs m t vres m' ->
      rs' = nextinstr_nf
             (set_res res vres
               (undef_regs (map preg_of (destroyed_by_builtin ef)) rs)) ->
      step (State rs m) t (State rs' m')
  | exec_step_external:
      forall b ef args res rs m t rs' m',
      rs PC = Vptr b Int.zero ->
      Genv.find_funct_ptr ge b = Some (External ef) ->
      extcall_arguments rs m (ef_sig ef) args ->
      external_call ef ge args m t res m' ->
      rs' = (set_pair (loc_external_result (ef_sig ef)) res rs) #PC <- (rs RA) ->
      step (State rs m) t (State rs' m').

End RELSEM.

(** Execution of whole programs. *)

Inductive initial_state (p: program): state -> Prop :=
  | initial_state_intro: forall m0,
      Genv.init_mem p = Some m0 ->
      let ge := Genv.globalenv p in
      let rs0 :=
        (Pregmap.init Vundef)
        # PC <- (Genv.symbol_address ge p.(prog_main) Int.zero)
        # RA <- Vzero
        # ESP <- Vzero in
      initial_state p (State rs0 m0).

Inductive final_state: state -> int -> Prop :=
  | final_state_intro: forall rs m r,
      rs#PC = Vzero ->
      rs#EAX = Vint r ->
      final_state (State rs m) r.

Definition semantics (p: program) :=
  Semantics step (initial_state p) final_state (Genv.globalenv p).

(** Determinacy of the [Asm] semantics. *)

Remark extcall_arguments_determ:
  forall rs m sg args1 args2,
  extcall_arguments rs m sg args1 -> extcall_arguments rs m sg args2 -> args1 = args2.
Proof.
  intros until m.
  assert (A: forall l v1 v2,
             extcall_arg rs m l v1 -> extcall_arg rs m l v2 -> v1 = v2).
  { intros. inv H; inv H0; congruence. }
  assert (B: forall p v1 v2,
             extcall_arg_pair rs m p v1 -> extcall_arg_pair rs m p v2 -> v1 = v2).
  { intros. inv H; inv H0. 
    eapply A; eauto.
    f_equal; eapply A; eauto. }
  assert (C: forall ll vl1, list_forall2 (extcall_arg_pair rs m) ll vl1 ->
             forall vl2, list_forall2 (extcall_arg_pair rs m) ll vl2 -> vl1 = vl2).
  {
    induction 1; intros vl2 EA; inv EA.
    auto.
    f_equal; eauto. }
  intros. eapply C; eauto.
Qed.

Lemma semantics_determinate: forall p, determinate (semantics p).
Proof.
Ltac Equalities :=
  match goal with
  | [ H1: ?a = ?b, H2: ?a = ?c |- _ ] =>
      rewrite H1 in H2; inv H2; Equalities
  | _ => idtac
  end.
  intros; constructor; simpl; intros.
- (* determ *)
  inv H; inv H0; Equalities.
+ split. constructor. auto.
+ discriminate.
+ discriminate.
+ assert (vargs0 = vargs) by (eapply eval_builtin_args_determ; eauto). subst vargs0.
  exploit external_call_determ. eexact H5. eexact H11. intros [A B].
  split. auto. intros. destruct B; auto. subst. auto.
+ assert (args0 = args) by (eapply extcall_arguments_determ; eauto). subst args0.
  exploit external_call_determ. eexact H4. eexact H9. intros [A B].
  split. auto. intros. destruct B; auto. subst. auto.
- (* trace length *)
  red; intros; inv H; simpl.
  omega.
  eapply external_call_trace_length; eauto.
  eapply external_call_trace_length; eauto.
- (* initial states *)
  inv H; inv H0. f_equal. congruence.
- (* final no step *)
  inv H. unfold Vzero in H0. red; intros; red; intros. inv H; congruence.
- (* final states *)
  inv H; inv H0. congruence.
Qed.

(** Classification functions for processor registers (used in Asmgenproof). *)

Definition data_preg (r: preg) : bool :=
  match r with
  | PC => false
  | IR _ => true
  | FR _ => true
  | ST0 => true
  | CR _ => false
  | RA => false
  end.

Module AxiomSem.

  Inductive event :=  
  | Alloc (block : positive) (ofs : Z)  (size : Z)
  | Read  (block : positive) (ofs : Z)  (chunk : memory_chunk) (mv : list memval) 
  | Write (block: positive) (ofs : Z) (chunk : memory_chunk) (mv : list memval) 
  | Mfence
  | Lock
  | Unlock
  | Spawn (n : nat)
  | tau.

  Definition isRead (e : event) :=
    match e with
    | Read _ _ _ _ => true
    | _ => false
    end.

  (* for now we don't allow reading directly
     from an allocation event*)
  Definition isWrite (e : event) :=
    match e with
    | Write _ _ _ _ => true
    | _ => false
    end.

  (** We consider the location accessed by the event to be the
      addresses between ofs and ofs+size_chunk_nat chunk.
      This allows for example storing a signed int16 and later
      reading it as unsigned *)
  Definition loc (e : event) :=
    match e with
    | Read b ofs chunk mv
    | Write b ofs chunk mv =>
      Some (b, ofs, length mv)
    | _ => None
    end.

  (** True if two events access at least one common byte*)
  Definition sameLoc ev1 ev2 :=
    match loc ev1, loc ev2 with
    | Some (b1, ofs1, size1), Some (b2, ofs2, size2) =>
      b1 = b2 /\ exists ofs, Intv.In ofs (ofs1, (ofs1 + Z.of_nat size1)%Z) /\
                       Intv.In ofs (ofs2, (ofs2 + Z.of_nat size2)%Z)
    | _,_ => False
    end.

  Definition mval (e : event) : option (list memval) :=
    match e with
    | Read _ _ _ mv
    | Write _ _ _ mv =>
      Some mv
    | _ => None
    end.
      
  Definition compare_ints (x y: val) (rs: regset): regset :=
    rs #ZF  <- (Val.cmpu (fun _ _ => true) Ceq x y)
       #CF  <- (Val.cmpu (fun _ _ => true) Clt x y)
       #SF  <- (Val.negative (Val.sub x y))
       #OF  <- (Val.sub_overflow x y)
       #PF  <- Vundef.
  
  Definition goto_label (f: function) (lbl: label) (rs: regset) (rs':regset) : Prop :=
    match label_pos lbl 0 (fn_code f) with
    | None => False
    | Some pos =>
      match rs#PC with
      | Vptr b ofs =>
        rs' = rs#PC <- (Vptr b (Int.repr pos)) 
      | _ => False
      end
    end.

  (** Auxiliaries for memory accesses. *)

  Inductive load (chunk: memory_chunk) (b: block) (ofs: Z) (mv: list memval): event -> Prop :=
  | LoadVal:
      forall (Hvalid_access: (align_chunk chunk | ofs)%Z)
        (Hsize: size_chunk_nat chunk = length mv),
        load chunk b ofs mv (Read b ofs chunk mv).

  Inductive store (chunk: memory_chunk) (b: block) (ofs: Z) (v:val): event -> Prop :=
  | StoreVal:
      forall (Hvalid_access: (align_chunk chunk | ofs)%Z),
        store chunk b ofs v (Write b ofs chunk (encode_val chunk v)).

  Inductive alloc (ofs : Z) (sz : Z) : event -> block -> Prop :=
  | AllocSuccess:
      forall b,
        alloc ofs sz (Alloc b ofs sz) b.


  Section AxiomSem.

    Variable ge : genv.

    Inductive load_nf (chunk: memory_chunk) (a: addrmode)
              (rs: regset) (rd: preg) : regset -> event -> Prop :=
    | LoadNF:
        forall b ofs mv o
          (Haddr: eval_addrmode ge a rs = Vptr b ofs)
          (Hload: load chunk b (Int.unsigned ofs) mv o),
          load_nf chunk a rs rd (nextinstr_nf (rs#rd <- (decode_val chunk mv))) o.

    Inductive store_nf (chunk: memory_chunk) (a: addrmode) (rs: regset) (r1: preg)
              (destroyed: list preg) : regset -> event -> Prop :=
    | StoreNF:
        forall b ofs o
          (Haddr: eval_addrmode ge a rs = Vptr b ofs)
          (Hstore: store chunk b (Int.unsigned ofs) (rs r1) o),
          store_nf chunk a rs r1 destroyed (nextinstr_nf (undef_regs destroyed rs)) o.

    Inductive step_instr (f: function) (rs: regset) : instruction ->
                                                      regset -> list event -> Prop :=
    (** Moves *)
    | Mov_rr:
        forall rd r1,
          step_instr f rs (Pmov_rr rd r1) (nextinstr (rs#rd <- (rs r1))) (tau :: nil) 
    | Mov_ri:
        forall rd n,
          step_instr f rs (Pmov_ri rd n) (nextinstr_nf (rs#rd <- (Vint n))) (tau :: nil)
    | Mov_ra:
        forall rd id,
          step_instr f rs (Pmov_ra rd id)
                     (nextinstr_nf (rs#rd <- (Genv.symbol_address ge id Int.zero))) (tau :: nil)
    | Mov_rm:
        forall (rd : ireg) a rs' o
          (Hload: load_nf Mint32 a rs rd rs' o),
          step_instr f rs (Pmov_rm rd a) rs' (o :: nil)
    | Mov_mr:
        forall a (r1:ireg) rs' o
          (Hstore: store_nf Mint32 a rs r1 nil rs' o),
          step_instr f rs (Pmov_mr a r1) rs' (o :: nil)
    | Movsd_ff:
        forall rd r1,
          step_instr f rs (Pmovsd_ff rd r1) (nextinstr (rs#rd <- (rs r1))) (tau :: nil)
    | Movsd_fi:
        forall rd n,
          step_instr f rs (Pmovsd_fi rd n) (nextinstr (rs#rd <- (Vfloat n))) (tau :: nil)
    | Movsd_fm:
        forall (rd:freg) a rs' o
          (Hload: load_nf Mfloat64 a rs rd rs' o),
          step_instr f rs (Pmovsd_fm rd a) rs' (o :: nil)
    | Movsd_mf:
        forall a (r1:freg) rs' o
          (Hstore: store_nf Mfloat64 a rs r1 nil rs' o),
          step_instr f rs (Pmovsd_mf a r1) rs' (o :: nil)
    | Movss_fi:
        forall rd n,
          step_instr f rs (Pmovss_fi rd n) (nextinstr (rs#rd <- (Vsingle n))) (tau :: nil)
    | Movss_fm:
        forall (rd:freg) a rs' o
          (Hload: load_nf Mfloat32 a rs rd rs' o),
          step_instr f rs (Pmovss_fm rd a) rs' (o :: nil)
    | Movss_mf:
        forall a (r1:freg) rs' o
          (Hstore: store_nf Mfloat32 a rs r1 nil rs' o),
          step_instr f rs (Pmovss_mf a r1) rs' (o :: nil)
    | Fldl_m:
        forall a rs' o
          (Hload: load_nf Mfloat64 a rs ST0 rs' o),
          step_instr f rs (Pfldl_m a) rs' (o :: nil)
    | Fstpl_m:
        forall a rs' o
          (Hstore: store_nf Mfloat64 a rs ST0 (ST0 :: nil) rs' o),
          step_instr f rs (Pfstpl_m a) rs' (o :: nil)
    | Flds_m:
        forall a rs' o
          (Hload: load_nf Mfloat32 a rs ST0 rs' o),
          step_instr f rs (Pflds_m a) rs' (o :: nil)
    | Fstps_m:
        forall a rs' o
          (Hstore: store_nf Mfloat32 a rs ST0 (ST0 :: nil) rs' o),
          step_instr f rs (Pfstps_m a) rs' (o :: nil)
    | Xchg_rr:
        forall r1 r2,
          step_instr f rs (Pxchg_rr r1 r2)
                     (nextinstr (rs#r1 <- (rs r2) #r2 <- (rs r1))) (tau :: nil)
    (** Moves with conversion *)
    | Movb_mr:
        forall a (r1:ireg) rs' o
          (Hstore: store_nf Mint8unsigned a rs r1 nil rs' o),
          step_instr f rs (Pmovb_mr a r1) rs' (o :: nil)
    | Movw_mr:
        forall a (r1:ireg) rs' o
          (Hstore: store_nf Mint16unsigned a rs r1 nil rs' o),
          step_instr f rs (Pmovw_mr a r1) rs' (o :: nil)
    | Movzb_rr:
        forall rd r1,
          step_instr f rs (Pmovzb_rr rd r1)
                     (nextinstr (rs#rd <- (Val.zero_ext 8 rs#r1))) (tau :: nil)
    | Movzb_rm:
        forall (rd:ireg) a rs' o
          (Hload: load_nf Mint8unsigned a rs rd rs' o),
          step_instr f rs (Pmovzb_rm rd a) rs' (o :: nil)
    | Movsb_rr:
        forall rd r1,
          step_instr f rs (Pmovsb_rr rd r1)
                     (nextinstr (rs#rd <- (Val.sign_ext 8 rs#r1))) (tau :: nil)
    | Movsb_rm:
        forall (rd:ireg) a rs' o
          (Hload: load_nf Mint8signed a rs rd rs' o),
          step_instr f rs (Pmovsb_rm rd a) rs' (o :: nil)
    | Movzw_rr:
        forall rd r1,
          step_instr f rs (Pmovzw_rr rd r1)
                     (nextinstr (rs#rd <- (Val.zero_ext 16 rs#r1))) (tau :: nil)
    | Movzw_rm:
        forall (rd:ireg) a rs' o
          (Hload: load_nf Mint16unsigned a rs rd rs' o),
          step_instr f rs (Pmovzw_rm rd a) rs' (o :: nil)
    | Movsw_rr:
        forall rd r1,
          step_instr f rs (Pmovsw_rr rd r1)
                     (nextinstr (rs#rd <- (Val.sign_ext 16 rs#r1))) (tau :: nil)
    | Movsw_rm:
        forall (rd:ireg) a rs' o
          (Hload: load_nf Mint16signed a rs rd rs' o),
          step_instr f rs (Pmovsw_rm rd a) rs' (o :: nil)
    | Cvtsd2ss_ff:
        forall rd r1,
          step_instr f rs (Pcvtsd2ss_ff rd r1)
                     (nextinstr (rs#rd <- (Val.singleoffloat rs#r1))) (tau :: nil)
    | Cvtss2sd_ff:
        forall rd r1,
          step_instr f rs (Pcvtsd2ss_ff rd r1)
                     (nextinstr (rs#rd <- (Val.floatofsingle rs#r1))) (tau :: nil)
    | Cvttsd2si_rf:
        forall rd r1,
          step_instr f rs (Pcvttsd2si_rf rd r1)
                     (nextinstr (rs#rd <- (Val.maketotal (Val.intoffloat rs#r1)))) (tau :: nil)
    | Cvtsi2sd_fr:
        forall rd r1,
          step_instr f rs (Pcvtsi2sd_fr rd r1)
                     (nextinstr (rs#rd <- (Val.maketotal (Val.floatofint rs#r1)))) (tau :: nil)
    | Cvttss2si_rf:
        forall rd r1,
          step_instr f rs (Pcvttss2si_rf rd r1)
                     (nextinstr (rs#rd <- (Val.maketotal (Val.intofsingle rs#r1)))) (tau :: nil)
    | Cvtsi2ss_fr:
        forall rd r1,
          step_instr f rs (Pcvtsi2ss_fr rd r1)
                     (nextinstr (rs#rd <- (Val.maketotal (Val.singleofint rs#r1)))) (tau :: nil)
    (** Integer arithmetic *)
    | Lea:
        forall rd a,
          step_instr f rs (Plea rd a)
                     (nextinstr (rs#rd <- (eval_addrmode ge a rs))) (tau :: nil)
    | Neg:
        forall rd,
          step_instr f rs (Pneg rd)
                     (nextinstr_nf (rs#rd <- (Val.neg rs#rd))) (tau :: nil)
    | Sub_rr:
        forall rd r1,
          step_instr f rs (Psub_rr rd r1)
                     (nextinstr_nf (rs#rd <- (Val.sub rs#rd rs#r1))) (tau :: nil)
    | Imul_rr:
        forall rd r1,
          step_instr f rs (Pimul_rr rd r1)
                     (nextinstr_nf (rs#rd <- (Val.mul rs#rd rs#r1))) (tau :: nil)
    | Imul_ri:
        forall rd n,
          step_instr f rs (Pimul_ri rd n)
                     (nextinstr_nf (rs#rd <- (Val.mul rs#rd (Vint n)))) (tau :: nil)
    | Imul_r:
        forall r1,
          step_instr f rs (Pimul_r r1)
                     (nextinstr_nf (rs#EAX <- (Val.mul rs#EAX rs#r1)
                                      #EDX <- (Val.mulhs rs#EAX rs#r1))) (tau :: nil)
    | Mul_r:
        forall r1,
          step_instr f rs (Pmul_r r1)
                     (nextinstr_nf (rs#EAX <- (Val.mul rs#EAX rs#r1)
                                      #EDX <- (Val.mulhu rs#EAX rs#r1))) (tau :: nil)
    | Div:
        forall (r1:ireg) vq vr,
          let vn := rs#EAX in
          let vd := (rs#EDX <- Vundef)#r1 in
          Val.divu vn vd = Some vq ->
          Val.modu vn vd = Some vr ->
          step_instr f rs (Pdiv r1) (nextinstr_nf (rs#EAX <- vq #EDX <- vr)) (tau :: nil)
    | And_rr:
        forall rd r1,
          step_instr f rs (Pand_rr rd r1) (nextinstr_nf (rs#rd <- (Val.and rs#rd rs#r1))) (tau :: nil)
    | And_ri:
        forall rd n,
          step_instr f rs (Pand_ri rd n) (nextinstr_nf (rs#rd <- (Val.and rs#rd (Vint n)))) (tau :: nil)
    | Or_rr:
        forall rd r1,
          step_instr f rs (Por_rr rd r1) (nextinstr_nf (rs#rd <- (Val.or rs#rd rs#r1))) (tau :: nil)
    | Or_ri:
        forall rd n,
          step_instr f rs (Por_ri rd n) (nextinstr_nf (rs#rd <- (Val.or rs#rd (Vint n)))) (tau :: nil)
    | Xor_r:
        forall rd,
          step_instr f rs (Pxor_r rd) (nextinstr_nf (rs#rd <- Vzero)) (tau :: nil)
    | Xor_rr:
        forall rd r1,
          step_instr f rs (Pxor_rr rd r1) (nextinstr_nf (rs#rd <- (Val.xor rs#rd rs#r1))) (tau :: nil)
    | Xor_ri:
        forall rd n,
          step_instr f rs (Pxor_ri rd n) (nextinstr_nf (rs#rd <- (Val.xor rs#rd (Vint n)))) (tau :: nil)
    | Not:
        forall rd,
          step_instr f rs (Pnot rd) (nextinstr_nf (rs#rd <- (Val.notint rs#rd))) (tau :: nil)
    | Sal_rcl:
        forall rd,
          step_instr f rs (Psal_rcl rd) (nextinstr_nf (rs#rd <- (Val.shl rs#rd rs#ECX))) (tau :: nil)
    | Sal_ri:
        forall rd n,
          step_instr f rs (Psal_ri rd n) (nextinstr_nf (rs#rd <- (Val.shl rs#rd (Vint n)))) (tau :: nil)
    | Shr_rcl:
        forall rd,
          step_instr f rs (Pshr_rcl rd) (nextinstr_nf (rs#rd <- (Val.shru rs#rd rs#ECX))) (tau :: nil)
    | Shr_ri:
        forall rd n,
          step_instr f rs (Pshr_ri rd n) (nextinstr_nf (rs#rd <- (Val.shru rs#rd (Vint n)))) (tau :: nil)
    | Sar_rcl:
        forall rd,
          step_instr f rs (Psar_rcl rd) (nextinstr_nf (rs#rd <- (Val.shr rs#rd rs#ECX))) (tau :: nil)
    | Sar_ri:
        forall rd n,
          step_instr f rs (Psar_ri rd n) (nextinstr_nf (rs#rd <- (Val.shr rs#rd (Vint n)))) (tau :: nil)
    | Shld_ri:
        forall rd r1 n,
          step_instr f rs (Pshld_ri rd r1 n)
                     (nextinstr_nf (rs#rd <- (Val.or (Val.shl rs#rd (Vint n))
                                                    (Val.shru rs#r1 (Vint (Int.sub Int.iwordsize n))))))
                     (tau :: nil)
    | Ror_ri:
        forall rd n,
          step_instr f rs (Pror_ri rd n) (nextinstr_nf (rs#rd <- (Val.ror rs#rd (Vint n)))) (tau :: nil)
    | Cmp_rr:
        forall r1 r2,
          step_instr f rs (Pcmp_rr r1 r2) (nextinstr (compare_ints (rs r1) (rs r2) rs)) (tau :: nil)
    | Cmp_ri:
        forall r1 n,
          step_instr f rs (Pcmp_ri r1 n) (nextinstr (compare_ints (rs r1) (Vint n) rs)) (tau :: nil)
    | Test_rr:
        forall r1 r2,
          step_instr f rs (Ptest_rr r1 r2) (nextinstr (compare_ints (Val.and (rs r1) (rs r2)) Vzero rs)) (tau :: nil)
    | Test_ri:
        forall r1 n,
          step_instr f rs (Ptest_ri r1 n) (nextinstr (compare_ints (Val.and (rs r1) (Vint n)) Vzero rs)) (tau :: nil)
    | Cmov:
        forall c rd r1,
          step_instr f rs (Pcmov c rd r1)
                     (match eval_testcond c rs with
                      | Some true =>  nextinstr (rs#rd <- (rs#r1))
                      | Some false => nextinstr rs
                      | None => nextinstr (rs#rd <- Vundef)
                      end) (tau :: nil)
    | Setcc:
        forall c rd,
          step_instr f rs (Psetcc c rd) (nextinstr (rs#rd <- (Val.of_optbool (eval_testcond c rs)))) (tau :: nil)
    (** Arithmetic operations over double-precision floats *)
    | Addd_ff:
        forall rd r1,
          step_instr f rs (Paddd_ff rd r1) (nextinstr (rs#rd <- (Val.addf rs#rd rs#r1))) (tau :: nil)
    | Subd_ff:
        forall rd r1,
          step_instr f rs (Psubd_ff rd r1) (nextinstr (rs#rd <- (Val.subf rs#rd rs#r1))) (tau :: nil)
    | Muld_ff:
        forall rd r1,
          step_instr f rs (Pmuld_ff rd r1)  (nextinstr (rs#rd <- (Val.mulf rs#rd rs#r1))) (tau :: nil)
    | Divd_ff:
        forall rd r1,
          step_instr f rs (Pdivd_ff rd r1) (nextinstr (rs#rd <- (Val.divf rs#rd rs#r1))) (tau :: nil)
    | Negd:
        forall rd, 
          step_instr f rs (Pnegd rd) (nextinstr (rs#rd <- (Val.negf rs#rd))) (tau :: nil)
    | Absd:
        forall rd,
          step_instr f rs (Pabsd rd) (nextinstr (rs#rd <- (Val.absf rs#rd))) (tau :: nil)
    | Comisd_ff:
        forall r1 r2,
          step_instr f rs (Pcomisd_ff r1 r2) (nextinstr (compare_floats (rs r1) (rs r2) rs)) (tau :: nil)
    | Xorpd_f:
        forall rd,
          step_instr f rs (Pxorpd_f rd) (nextinstr_nf (rs#rd <- (Vfloat Float.zero))) (tau :: nil)
    (** Arithmetic operations over single-precision floats *)
    | Adds_ff:
        forall rd r1,
          step_instr f rs (Padds_ff rd r1) (nextinstr (rs#rd <- (Val.addfs rs#rd rs#r1))) (tau :: nil)
    | Subs_ff:
        forall rd r1,
          step_instr f rs (Psubs_ff rd r1) (nextinstr (rs#rd <- (Val.subfs rs#rd rs#r1))) (tau :: nil)
    | Muls_ff:
        forall rd r1,
          step_instr f rs (Pmuls_ff rd r1) (nextinstr (rs#rd <- (Val.mulfs rs#rd rs#r1))) (tau :: nil)
    | Divs_ff:
        forall rd r1,
          step_instr f rs (Pdivs_ff rd r1) (nextinstr (rs#rd <- (Val.divfs rs#rd rs#r1))) (tau :: nil)
    | Negs:
        forall rd,
          step_instr f rs (Pnegs rd) (nextinstr (rs#rd <- (Val.negfs rs#rd))) (tau :: nil)
    | Abss:
        forall rd,
          step_instr f rs (Pabss rd) (nextinstr (rs#rd <- (Val.absfs rs#rd))) (tau :: nil)
    | Comiss_ff:
        forall r1 r2,
          step_instr f rs (Pcomiss_ff r1 r2) (nextinstr (compare_floats32 (rs r1) (rs r2) rs)) (tau :: nil)
    | Xorps_f:
        forall rd,
          step_instr f rs (Pxorps_f rd) (nextinstr_nf (rs#rd <- (Vsingle Float32.zero))) (tau :: nil)
    (** Branches and calls *)
    | Jmp_l:
        forall lbl rs'
          (Hgoto: goto_label f lbl rs rs'),
          step_instr f rs (Pjmp_l lbl) rs' (tau :: nil)
    | Jmp_s:
        forall id sg,
          step_instr f rs (Pjmp_s id sg) (rs#PC <- (Genv.symbol_address ge id Int.zero)) (tau :: nil)
    | Jmp_r:
        forall r sg,
          step_instr f rs (Pjmp_r r sg)  (rs#PC <- (rs r)) (tau :: nil)
    | Jcc:
        forall cond lbl rs'
          (Heval_cond: match eval_testcond cond rs with
                       | Some true => goto_label f lbl rs rs'
                       | Some false => rs' = nextinstr rs
                       | None => False
                       end),
          step_instr f rs (Pjcc cond lbl) rs' (tau :: nil)
    | Jcc2:
        forall cond1 cond2 lbl rs'
          (Heval_cond: match eval_testcond cond1 rs, eval_testcond cond2 rs with
                       | Some true, Some true =>
                         goto_label f lbl rs rs'
                       | Some _, Some _ => rs' = nextinstr rs
                       | _, _ => False
                       end),
          step_instr f rs (Pjcc2 cond1 cond2 lbl) rs' (tau :: nil)
    | Jmptbl:
        forall (r:ireg) tbl n lbl rs'
          (Hrs: rs#r = Vint n)
          (Htbl: list_nth_z tbl (Int.unsigned n) = Some lbl)
          (Hgoto: goto_label f lbl rs rs'),
          step_instr f rs (Pjmptbl r tbl) rs' (tau :: nil)
    | Call_s:
        forall id sg,
          step_instr f rs (Pcall_s id sg) 
                     (rs#RA <- (Val.add rs#PC Vone) #PC <- (Genv.symbol_address ge id Int.zero)) (tau :: nil)
    | Call_r:
        forall r sg,
          step_instr f rs (Pcall_r r sg) (rs#RA <- (Val.add rs#PC Vone) #PC <- (rs r)) (tau :: nil)
    | Ret:
        step_instr f rs Pret (rs#PC <- (rs#RA)) (tau :: nil)
    (** Saving and restoring registers *)
    | Mov_rm_a:
        forall (rd:ireg) a rs' o
          (Hload: load_nf Many32 a rs rd rs' o),
          step_instr f rs (Pmov_rm_a rd a) rs' (o :: nil)
    | Mov_mr_a:
        forall a (r1:ireg) rs' o
          (Hstore: store_nf Many32 a rs r1 nil rs' o),
          step_instr f rs (Pmov_mr_a a r1) rs' (o :: nil)
    | Movsd_fm_a:
        forall (rd:freg) a rs' o
          (Hload: load_nf Many64 a rs rd rs' o),
          step_instr f rs (Pmovsd_fm_a rd a) rs' (o :: nil)
    | Movsd_mf_a:
        forall a (r1:freg) rs' o
          (Hstore: store_nf Many64 a rs r1 nil rs' o),
          step_instr f rs (Pmovsd_mf_a a r1) rs' (o :: nil)
    (** Pseudo-instructions *)
    | Label:
        forall lbl,
          step_instr f rs (Plabel lbl) (nextinstr rs) (tau :: nil)
    | Allocframe:
        forall sz stk ofs_ra ofs_link b1 ofs1 b2 ofs2 oalloc ostore1 ostore2,
          let sp := Vptr stk Int.zero in
          forall (Halloc: alloc 0 sz oalloc stk)
            (Haddr1: Val.add sp (Vint ofs_link) = Vptr b1 ofs1)
            (Hstore1: store Mint32 b1 (Int.unsigned ofs1) rs#ESP ostore1)
            (Haddr2: Val.add sp (Vint ofs_ra) = Vptr b2 ofs2)
            (Hstore2: store Mint32 b2 (Int.unsigned ofs2) rs#RA ostore2),
            step_instr f rs (Pallocframe sz ofs_ra ofs_link)
                       (nextinstr (rs #EDX <- (rs#ESP) #ESP <- sp))
                       (oalloc :: ostore1 :: ostore2 :: nil)
    | Freeframe:
        forall sz ofs_ra ofs_link b1 ofs1 ra oload1 b2 ofs2 sp oload2 stk ofs
          (Haddr1: Val.add rs#ESP (Vint ofs_ra) = Vptr b1 ofs1)
          (Hload1: load Mint32 b1 (Int.unsigned ofs1) ra oload1)
          (Haddr2: Val.add rs#ESP (Vint ofs_link) = Vptr b2 ofs2)
          (Hload2: load Mint32 b2 (Int.unsigned ofs2) sp oload2)
          (Hesp: rs#ESP = Vptr stk ofs),
          (* free seems like a no-op*)
          step_instr f rs (Pfreeframe sz ofs_ra ofs_link)
                     (nextinstr (rs#ESP <- (decode_val Mint32 sp)
                                   #RA <- (decode_val Mint32 ra)))
                     (oload1 :: oload2 :: nil).

End AxiomSem.
End AxiomSem.