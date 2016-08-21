Require Import compcert.lib.Coqlib. 
Require Import compcert.lib.Maps.
Require Import compcert.lib.Integers. 
Require Import compcert.common.Values.
Require Import compcert.common.Memory.
Require Import compcert.common.Events.
Require Import compcert.common.AST.
Require Import compcert.common.Globalenvs.

Require Import msl.Extensionality. 
Require Import sepcomp.mem_lemmas.
Require Import sepcomp.semantics.
Require Import sepcomp.semantics_lemmas.

(** * Semantics annotated with Owens-style trace*)
Inductive mem_event :=
  Write : forall (b : block) (ofs : Z) (bytes : list memval), mem_event
| Read : forall (b:block) (ofs n:Z) (bytes: list memval), mem_event
| Alloc: forall (b:block)(lo hi:Z), mem_event
(*| Lock: drf_event
| Unlock: drf_event  -- these events are not generated by core steps*)
| Free: forall (l: list (block * Z * Z)), mem_event.

Fixpoint ev_elim (m:mem) (T: list mem_event) (m':mem):Prop :=
  match T with
   nil => m'=m
 | (Read b ofs n bytes :: R) => Mem.loadbytes m b ofs n = Some bytes /\ ev_elim m R m'
 | (Write b ofs bytes :: R) => exists m'', Mem.storebytes m b ofs bytes = Some m'' /\ ev_elim m'' R m' /\ bytes <> nil
 | (Alloc b lo hi :: R) => exists m'', Mem.alloc m lo hi = (m'',b) /\ ev_elim m'' R m'
 | (Free l :: R) => exists m'', Mem.free_list m l = Some m'' /\ ev_elim m'' R m'
  end.

Definition pmax (popt qopt: option permission): option permission :=
  match popt, qopt with
    _, None => popt
  | None, _ => qopt
  | Some p, Some q => if Mem.perm_order_dec p q then Some p else Some q
  end.

Lemma po_pmax_I p q1 q2:
  Mem.perm_order'' p q1 -> Mem.perm_order'' p q2 -> Mem.perm_order'' p (pmax q1 q2).
Proof.
  intros. destruct q1; destruct q2; simpl in *; trivial.
  destruct (Mem.perm_order_dec p0 p1); trivial.
Qed.

Fixpoint cur_perm (l: block * Z) (T: list mem_event): option permission := 
  match T with 
      nil => None
    | (mu :: R) => 
          let popt := cur_perm l R in
          match mu, l with 
            | (Read b ofs n bytes), (b',ofs') => 
                 pmax (if eq_block b b' && zle ofs ofs' && zlt ofs' (ofs+n)
                       then Some Readable else None) popt
            | (Write b ofs bytes), (b',ofs') => 
                 pmax (if eq_block b b' && zle ofs ofs' && zlt ofs' (ofs+ Zlength bytes)
                       then Some Writable else None) popt
            | (Alloc b lo hi), (b',ofs') =>  (*we don't add a constraint relating lo/hi/ofs*)
                 if eq_block b b' then None else popt
            | (Free l), (b',ofs') => 
                 List.fold_right (fun tr qopt => match tr with (b,lo,hi) => 
                                                   if eq_block b b' && zle lo ofs' && zlt ofs' hi
                                                   then Some Freeable else qopt
                                                end)
                                 popt l
          end
  end.

Lemma po_None popt: Mem.perm_order'' popt None.
Proof. destruct popt; simpl; trivial. Qed.

Lemma ev_perm b ofs: forall T m m', ev_elim m T m' -> 
      Mem.perm_order'' ((Mem.mem_access m) !! b ofs Cur) (cur_perm (b,ofs) T).
Proof.
induction T; simpl; intros.
+ subst. apply po_None. 
+ destruct a.
  - (*Store*)
     destruct H as [m'' [SB [EV BYTES]]]. specialize (IHT _ _ EV); clear EV. 
     rewrite (Mem.storebytes_access _ _ _ _ _ SB) in *.
     eapply po_pmax_I; try eassumption.
     remember (eq_block b0 b && zle ofs0 ofs && zlt ofs (ofs0 + Zlength bytes)) as d.
     destruct d; try solve [apply po_None].
     destruct (eq_block b0 b); simpl in *; try discriminate.
     destruct (zle ofs0 ofs); simpl in *; try discriminate.
     destruct (zlt ofs (ofs0 + Zlength bytes)); simpl in *; try discriminate.
     rewrite Zlength_correct in *.
     apply Mem.storebytes_range_perm in SB. 
     exploit (SB ofs); try omega.
     intros; subst; assumption. 
  - (*Load*)
     destruct H as [LB EV]. specialize (IHT _ _ EV); clear EV. 
     eapply po_pmax_I; try eassumption.
     remember (eq_block b0 b && zle ofs0 ofs && zlt ofs (ofs0 + n)) as d.
     destruct d; try solve [apply po_None].
     destruct (eq_block b0 b); simpl in *; try discriminate.
     destruct (zle ofs0 ofs); simpl in *; try discriminate.
     destruct (zlt ofs (ofs0 + n)); simpl in *; try discriminate.
     apply Mem.loadbytes_range_perm in LB. 
     exploit (LB ofs); try omega.
     intros; subst; assumption. 
  - (*Alloc*)
     destruct H as [m'' [ALLOC EV]]. specialize (IHT _ _ EV); clear EV. 
     destruct (eq_block b0 b); subst; try solve [apply po_None].
     eapply po_trans; try eassumption.
     remember ((Mem.mem_access m'') !! b ofs Cur) as d.
     destruct d; try solve [apply po_None].
     symmetry in Heqd.
     apply (Mem.perm_alloc_4 _ _ _ _ _ ALLOC b ofs Cur p).
     * unfold Mem.perm; rewrite Heqd. destruct p; simpl; constructor.
     * intros N; subst; elim n; trivial.
  - (*Free*)
     destruct H as [m'' [FR EV]]. specialize (IHT _ _ EV); clear EV. 
     generalize dependent m.
     induction l; simpl; intros.
     * inv FR. assumption.
     * destruct a as [[bb lo] hi].
       remember (Mem.free m bb lo hi) as p.
       destruct p; inv FR; symmetry in Heqp. specialize (IHl _ H0).
       remember (eq_block bb b && zle lo ofs && zlt ofs hi) as d.
       destruct d.
       { clear - Heqp Heqd. apply Mem.free_range_perm in Heqp.
         destruct (eq_block bb b); simpl in Heqd; inv Heqd.
         exploit (Heqp ofs); clear Heqp; trivial.
         destruct (zle lo ofs); try discriminate.
         destruct (zlt ofs hi); try discriminate. omega. }
       { eapply po_trans; try eassumption. clear - Heqp.
         remember ((Mem.mem_access m0) !! b ofs Cur) as perm2.
         destruct perm2; try solve [apply po_None].
         exploit (Mem.perm_free_3 _ _ _ _ _ Heqp); unfold Mem.perm.
            rewrite <- Heqperm2. apply perm_refl.
         simpl; trivial. }
Qed.

Lemma ev_elim_app: forall T1 m1 m2 (EV1:ev_elim m1 T1 m2) T2 m3  (EV2: ev_elim m2 T2 m3), ev_elim m1 (T1++T2) m3.
Proof.
  induction T1; simpl; intros; subst; trivial.
  destruct a.
+ destruct EV1 as [mm [SB [EV BYTES]]]. specialize (IHT1 _ _ EV _ _ EV2).
  exists mm; split; trivial; split; trivial.
+ destruct EV1 as [LB EV]. specialize (IHT1 _ _ EV _ _ EV2).
  split; trivial.
+ destruct EV1 as [mm [AL EV]]. specialize (IHT1 _ _ EV _ _ EV2).
  exists mm; split; trivial.
+ destruct EV1 as [mm [FL EV]]. specialize (IHT1 _ _ EV _ _ EV2).
  exists mm; split; trivial.
Qed.

Lemma ev_elim_split: forall T1 T2 m1 m3 (EV1:ev_elim m1 (T1++T2) m3),
      exists m2, ev_elim m1 T1 m2 /\ ev_elim m2 T2 m3.
Proof.
  induction T1; simpl; intros.
+ exists m1; split; trivial.
+ destruct a.
  - destruct EV1 as [mm [SB [EV BYTES]]]. destruct (IHT1 _ _ _ EV) as [m2 [EV1 EV2]].
    exists m2; split; trivial. exists mm; split; trivial; split; trivial.
  - destruct EV1 as [LB EV]. destruct (IHT1 _ _ _ EV) as [m2 [EV1 EV2]].
    exists m2; split; trivial. split; trivial.
  - destruct EV1 as [mm [AL EV]]. destruct (IHT1 _ _ _ EV) as [m2 [EV1 EV2]].
    exists m2; split; trivial. exists mm; split; trivial.
  - destruct EV1 as [mm [SB EV]]. destruct (IHT1 _ _ _ EV) as [m2 [EV1 EV2]].
    exists m2; split; trivial. exists mm; split; trivial.
Qed.

(** Similar to effect semantics, event semantics augment memory semantics with suitable effects, in the form 
    of a set of memory access traces associated with each internal 
    step of the semantics. *)

Record EvSem {G C} :=
  { (** [sem] is a memory semantics. *)
    msem :> MemSem G C

    (** The step relation of the new semantics. *)
  ; ev_step: G -> C -> mem -> list mem_event -> C -> mem -> Prop

    (** The next four fields axiomatize [drfstep] and its relation to the
        underlying step relation of [msem]. *)
  ; ev_step_ax1: forall g c m T c' m',
       ev_step g c m T c' m' ->
            corestep msem g c m c' m' 
  ; ev_step_ax2: forall g c m c' m',
       corestep msem g c m c' m' ->
       exists T, ev_step g c m T c' m'
  ; ev_step_fun: forall g c m T' c' m' T'' c'' m'',
       ev_step g c m T' c' m' -> ev_step g c m T'' c'' m'' -> T'=T''
(*  ; ev_step_elim: forall g c m T c' m',
       ev_step g c m T c' m' -> ev_elim m T m'*)
  ; ev_step_elim: forall g c m T c' m' (STEP: ev_step g c m T c' m'),
       ev_elim m T m' /\ 
       (forall mm mm', ev_elim mm T mm' -> exists cc', ev_step g c mm T cc' mm')
  }.

Lemma Ev_sem_cur_perm {G C} (R: @EvSem G C) g c m T c' m' b ofs (D: ev_step R g c m T c' m'): 
      Mem.perm_order'' ((Mem.mem_access m) !! b ofs Cur) (cur_perm (b,ofs) T).
Proof. eapply ev_perm. eapply ev_step_elim; eassumption. Qed.

Implicit Arguments EvSem [].
