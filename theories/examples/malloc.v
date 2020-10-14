From iris.algebra Require Import frac.
From iris.proofmode Require Import tactics.
From cap_machine Require Import rules logrel addr_reg_sample fundamental.
From cap_machine.examples Require Import contiguous.

(* A toy malloc implementation *)

(* The routine is initially provided a capability to a contiguous range of
   memory. It implements a bump-pointer allocator, where all memory before the
   pointer of the capability has been allocated, and all memory after is free.
   Allocating corresponds to increasing the pointer and returning the
   corresponding sub-slice.

   There is no free: when all the available memory has been allocated, the
   routine cannot allocate new memory and will fail instead.

   This is obviously not very realistic, but is good enough for our simple case
   studies. *)

(* TODO: move to iris_extra *)
Lemma big_sepL2_to_big_sepL_replicate {Σ : gFunctors} {A B: Type} (l1: list A) (b : B) (Φ: A -> B -> iProp Σ) :
  ([∗ list] a;b' ∈ l1;replicate (length l1) b, Φ a b')%I -∗
  ([∗ list] a ∈ l1, Φ a b).
Proof.
  iIntros "Hl".
  iInduction l1 as [|a l1] "IH". 
  - done.
  - simpl. iDestruct "Hl" as "[$ Hl]". 
    iApply "IH". iFrame.
Qed.   

Section SimpleMalloc.
  Context {Σ:gFunctors} {memg:memG Σ} {regg:regG Σ}
          {nainv: logrel_na_invs Σ}
          `{MP: MachineParameters}.

  Definition malloc_subroutine_instrs' (offset: Z) :=
    [lt_z_r r_t3 0 r_t1;
     move_r r_t2 PC;
     lea_z r_t2 4; 
     jnz r_t2 r_t3;
     fail_end;
     move_r r_t2 PC;
     lea_z r_t2 offset;
     load_r r_t2 r_t2;
     geta r_t3 r_t2;
     lea_r r_t2 r_t1;
     geta r_t1 r_t2;
     move_r r_t4 r_t2;
     subseg_r_r r_t4 r_t3 r_t1;
     sub_r_r r_t3 r_t3 r_t1;
     lea_r r_t4 r_t3;
     move_r r_t3 r_t2;
     sub_z_r r_t1 0%Z r_t1;
     lea_r r_t3 r_t1;
     getb r_t1 r_t3;
     lea_r r_t3 r_t1;
     store_r r_t3 r_t2;
     move_r r_t1 r_t4;
     move_z r_t2 0%Z;
     move_z r_t3 0%Z;
     move_z r_t4 0%Z;
     jmp r_t0].

  Definition malloc_subroutine_instrs_length : Z :=
    Eval cbv in (length (malloc_subroutine_instrs' 0%Z)).

  Definition malloc_subroutine_instrs :=
    malloc_subroutine_instrs' (malloc_subroutine_instrs_length - 5).

  Ltac iPrologue_pre :=
    match goal with
    | Hlen : length ?a = ?n |- _ =>
      let a' := fresh "a" in
      destruct a as [| a' a]; inversion Hlen; simpl
    end.

  Ltac iPrologue prog :=
    (try iPrologue_pre);
    iDestruct prog as "[Hi Hprog]";
    iApply (wp_bind (fill [SeqCtx])).

  Ltac iEpilogue prog :=
    iNext; iIntros prog; iSimpl;
    iApply wp_pure_step_later;auto;iNext.

  Ltac iCorrectPC i j :=
    eapply isCorrectPC_contiguous_range with (a0 := i) (an := j); eauto; [];
    cbn; solve [ repeat constructor ].

  Ltac iContiguous_next Ha index :=
    apply contiguous_of_contiguous_between in Ha;
    generalize (contiguous_spec _ Ha index); auto.

  Definition malloc_inv (b e : Addr) : iProp Σ :=
    (∃ b_m a_m,
       [[b, b_m]] ↦ₐ [[ malloc_subroutine_instrs ]]
     ∗ b_m ↦ₐ (inr (RWX, b_m, e, a_m))
     ∗ [[a_m, e]] ↦ₐ [[ region_addrs_zeroes a_m e ]]
     ∗ ⌜(b_m < a_m)%a ∧ (a_m <= e)%a⌝
    )%I.


  (* TODO: move this to the rules_AddSubLt.v file. *)
  Lemma wp_AddSubLt_fail E ins dst n1 r2 w wdst cap pc_p pc_b pc_e pc_a :
    decodeInstrW w = ins
    → is_AddSubLt ins dst (inl n1) (inr r2)
      (* → (pc_a + 1)%a = Some pc_a' *)
        → isCorrectPC (inr (pc_p, pc_b, pc_e, pc_a))
          → {{{ PC ↦ᵣ inr (pc_p, pc_b, pc_e, pc_a) ∗ pc_a ↦ₐ w ∗ dst ↦ᵣ wdst ∗ r2 ↦ᵣ inr cap }}}
              Instr Executable
            @ E
      {{{ RET FailedV; True }}}.
  Proof.
    iIntros (Hdecode Hinstr Hvpc φ) "(HPC & Hpc_a & Hdst & Hr2) Hφ".
    iDestruct (map_of_regs_3 with "HPC Hdst Hr2") as "[Hmap (%&%&%)]".
    iApply (wp_AddSubLt with "[$Hmap Hpc_a]"); eauto; simplify_map_eq; eauto.
      by erewrite regs_of_is_AddSubLt; eauto; rewrite !dom_insert; set_solver+.
    iNext. iIntros (regs' retv) "(#Hspec & Hpc_a & Hmap)". iDestruct "Hspec" as %Hspec.
    destruct Hspec as [* Hsucc |].
    { (* Success (contradiction) *) simplify_map_eq. }
    { (* Failure, done *) by iApply "Hφ". }
  Qed.
  
  Lemma simple_malloc_subroutine_spec (wsize: Word) (cont: Word) b e rmap N E φ :
    dom (gset RegName) rmap = all_registers_s ∖ {[ PC; r_t0; r_t1 ]} →
    (* (size > 0)%Z → *)
    ↑N ⊆ E →
    (  na_inv logrel_nais N (malloc_inv b e)
     ∗ na_own logrel_nais E
     ∗ ([∗ map] r↦w ∈ rmap, r ↦ᵣ w)
     ∗ r_t0 ↦ᵣ cont
     ∗ PC ↦ᵣ inr (RX, b, e, b)
     ∗ r_t1 ↦ᵣ wsize
     ∗ ▷ ((na_own logrel_nais E
          ∗ [∗ map] r↦w ∈ <[r_t2 := inl 0%Z]>
                         (<[r_t3 := inl 0%Z]>
                         (<[r_t4 := inl 0%Z]>
                          rmap)), r ↦ᵣ w)
          ∗ r_t0 ↦ᵣ cont
          ∗ PC ↦ᵣ updatePcPerm cont
          ∗ (∃ (ba ea : Addr) size,
            ⌜wsize = inl size⌝
            ∗ ⌜(ba + size)%a = Some ea⌝
            ∗ r_t1 ↦ᵣ inr (RWX, ba, ea, ba)
            ∗ [[ba, ea]] ↦ₐ [[region_addrs_zeroes ba ea]])
          -∗ WP Seq (Instr Executable) {{ φ }}))
    ⊢ WP Seq (Instr Executable) {{ λ v, φ v ∨ ⌜v = FailedV⌝ }}%I.
  Proof.
    iIntros (Hrmap_dom (* Hsize *) HN) "(#Hinv & Hna & Hrmap & Hr0 & HPC & Hr1 & Hφ)".
    iMod (na_inv_open with "Hinv Hna") as "(>Hmalloc & Hna & Hinv_close)"; auto.
    rewrite /malloc_inv.
    iDestruct "Hmalloc" as (b_m a_m) "(Hprog & Hmemptr & Hmem & Hbounds)".
    iDestruct "Hbounds" as %[Hbm_am Ham_e].
    (* Get some registers *)
    assert (is_Some (rmap !! r_t2)) as [r2w Hr2w].
    { rewrite elem_of_gmap_dom Hrmap_dom. set_solver. }
    assert (is_Some (rmap !! r_t3)) as [r3w Hr3w].
    { rewrite elem_of_gmap_dom Hrmap_dom. set_solver. }
    assert (is_Some (rmap !! r_t4)) as [r4w Hr4w].
    { rewrite elem_of_gmap_dom Hrmap_dom. set_solver. }
    iDestruct (big_sepM_delete _ _ r_t2 with "Hrmap") as "[Hr2 Hrmap]".
      eassumption.
    iDestruct (big_sepM_delete _ _ r_t3 with "Hrmap") as "[Hr3 Hrmap]".
      by rewrite lookup_delete_ne //.
    iDestruct (big_sepM_delete _ _ r_t4 with "Hrmap") as "[Hr4 Hrmap]".
      by rewrite !lookup_delete_ne //.

    rewrite /(region_mapsto b b_m).
    set ai := region_addrs b b_m.
    assert (Hai: region_addrs b b_m = ai) by reflexivity.
    iDestruct (big_sepL2_length with "Hprog") as %Hprog_len.
    cbn in Hprog_len.
    assert ((b + malloc_subroutine_instrs_length)%a = Some b_m) as Hb_bm.
    { rewrite /malloc_subroutine_instrs_length.
      rewrite region_addrs_length /region_size in Hprog_len. solve_addr. }
    assert (contiguous_between ai b b_m) as Hcont.
    { apply contiguous_between_of_region_addrs; eauto.
      rewrite /malloc_subroutine_instrs_length in Hb_bm. solve_addr. }

    assert (HPC: ∀ a, a ∈ ai → isCorrectPC (inr (RX, b, e, a))).
    { intros a Ha.
      pose proof (contiguous_between_middle_bounds' _ _ _ _ Hcont Ha) as [? ?].
      constructor; eauto. solve_addr. }
    
    (* lt r_t3 0 r_t1 *)
    destruct ai as [|a l];[inversion Hprog_len|].
    destruct l as [|? l];[inversion Hprog_len|].
    pose proof (contiguous_between_cons_inv_first _ _ _ _ Hcont) as ->.
    iPrologue "Hprog".
    destruct (wsize) as [size|]. 
    2: { iApply (wp_AddSubLt_fail with "[$HPC $Hi $Hr3 $Hr1]");
         [apply decode_encode_instrW_inv|right;right;eauto|..].
         { apply HPC; repeat constructor. }
         iEpilogue "_". iApply wp_value. by iRight.
    }
    iApply (wp_add_sub_lt_success_z_r with "[$HPC $Hi $Hr3 $Hr1]");
      [apply decode_encode_instrW_inv|right;right;eauto|iContiguous_next Hcont 0| |..].
    { apply HPC; repeat constructor. }
    iEpilogue "(HPC & Hprog_done & Hr1 & Hr3)".
    (* move r_t2 PC *)
    destruct l as [|? l];[inversion Hprog_len|].    
    iPrologue "Hprog".
    iApply (wp_move_success_reg_fromPC with "[$HPC $Hi $Hr2]");
      [apply decode_encode_instrW_inv| |iContiguous_next Hcont 1| |..].
    { apply HPC; repeat constructor. }
    iEpilogue "(HPC & Hi & Hr2)". iCombine "Hi" "Hprog_done" as "Hprog_done".
    (* lea r_t2 4 *)
    do 3 (destruct l as [|? l];[inversion Hprog_len|]). 
    assert (a0 + 4 = Some a3)%a as Hlea1.
    { apply contiguous_between_incr_addr_middle with (i:=1) (j:=4) (ai:=a0) (aj:=a3) in Hcont;auto. }
    iPrologue "Hprog".
    iApply (wp_lea_success_z with "[$HPC $Hi $Hr2]");
      [apply decode_encode_instrW_inv| |iContiguous_next Hcont 2|done|done|..].
    { apply HPC; repeat constructor. }
    iEpilogue "(HPC & Hi & Hr2)". iCombine "Hi" "Hprog_done" as "Hprog_done".

    (* we need do destruct on the cases for the size *)
    destruct (decide (0 < size)%Z) as [Hsize | Hsize]. 
    2: {
      (* the program will not jump, and go to the fail instruction *)
      (* jnz  r_t2 r_t3 *)
      assert (rules_AddSubLt.denote (Lt r_t3 (inl 0%Z) (inr r_t1)) 0 size = 0) as ->.
      { simpl. clear -Hsize. apply Z.ltb_nlt in Hsize. rewrite Hsize. auto. }
      iPrologue "Hprog".
      iApply (wp_jnz_success_next with "[$HPC $Hi $Hr2 $Hr3]");
        [apply decode_encode_instrW_inv| |iContiguous_next Hcont 3|..]. 
      { apply HPC; repeat constructor. }
      iEpilogue "(HPC & Hi & Hr2 & Hr3)". iCombine "Hi" "Hprog_done" as "Hprog_done".
      (* fail *)
      iPrologue "Hprog".
      iApply (wp_fail with "[$HPC $Hi]");
        [apply decode_encode_instrW_inv|..].
      { apply HPC; repeat constructor. }
      iEpilogue "_". iApply wp_value. by iRight.
    }

    (* otherwise we continue malloc *)
    iPrologue "Hprog".
    assert (rules_AddSubLt.denote (Lt r_t3 (inl 0%Z) (inr r_t1)) 0 size = 1) as ->.
    { simpl. clear -Hsize. apply Z.ltb_lt in Hsize. rewrite Hsize. auto. }
    iApply (wp_jnz_success_jmp with "[$HPC $Hi $Hr2 $Hr3]");
        [apply decode_encode_instrW_inv| |iContiguous_next Hcont 3|..]. 
    { apply HPC; repeat constructor. }
    iEpilogue "(HPC & Hi & Hr2 & Hr3)". iCombine "Hi" "Hprog_done" as "Hprog_done".
    
    (* move r_t2 PC *)
    destruct l as [|? l];[inversion Hprog_len|].
    iPrologue "Hprog". iCombine "Hi" "Hprog_done" as "Hprog_done".
    iDestruct "Hprog" as "[Hi Hprog]". 
    iApply (wp_move_success_reg_fromPC with "[$HPC $Hi $Hr2]");
      [apply decode_encode_instrW_inv| |iContiguous_next Hcont 5| |..].
    { apply HPC; repeat constructor. }
    iEpilogue "(HPC & Hi & Hr2)".
    (* lea r_t2 malloc_instrs_length *)
    destruct l as [|? l];[inversion Hprog_len|]. iCombine "Hi" "Hprog_done" as "Hprog_done".
    iPrologue "Hprog".
    assert ((a3 + (malloc_subroutine_instrs_length - 5))%a = Some b_m) as Hlea.
    { assert (b + 5 = Some a3)%a. apply contiguous_between_incr_addr with (i:=5) (ai:=a3) in Hcont;auto.
      clear -H Hb_bm. solve_addr. }
    iApply (wp_lea_success_z with "[$HPC $Hi $Hr2]");
      [apply decode_encode_instrW_inv| |iContiguous_next Hcont 6|apply Hlea|done|..].
    { apply HPC; repeat constructor. }
    iEpilogue "(HPC & Hi & Hr2)". iCombine "Hi" "Hprog_done" as "Hprog_done".
    (* load r_t2 r_t2 *)
    destruct l as [|? l];[inversion Hprog_len|].
    iPrologue "Hprog".
    (* FIXME *)
    assert ((b_m =? a5)%a = false) as Hbm_a.
    { apply Z.eqb_neq. intro.
      pose proof (contiguous_between_middle_bounds _ 7 a5 _ _ Hcont eq_refl) as [? ?].
      solve_addr. }
    iApply (wp_load_success_same with "[$HPC $Hi $Hr2 Hmemptr]");
      [auto(*FIXME*)|apply decode_encode_instrW_inv| |split;try done
       |iContiguous_next Hcont 7|..].
    { apply HPC; repeat constructor. }
    { apply le_addr_withinBounds.
      - generalize (contiguous_between_length _ _ _ Hcont). cbn.
        clear; solve_addr.
      - revert Hbm_am Ham_e; solve_addr. }
    { rewrite Hbm_a; iFrame. }
    rewrite Hbm_a. iEpilogue "(HPC & Hr2 & Hi & Hmemptr)".
    iCombine "Hi" "Hprog_done" as "Hprog_done".
    (* geta r_t3 r_t2 *)
    destruct l as [|? l];[inversion Hprog_len|].
    iPrologue "Hprog".
    iApply (wp_Get_success with "[$HPC $Hi $Hr3 $Hr2]");
      [apply decode_encode_instrW_inv|done| |iContiguous_next Hcont 8|..].
    { apply HPC; repeat constructor. }
    iEpilogue "(HPC & Hi & Hr2 & Hr3)". iCombine "Hi" "Hprog_done" as "Hprog_done".
    cbn [rules_Get.denote].
    (* lea_r r_t2 r_t1 *)
    destruct l as [|? l];[inversion Hprog_len|].
    iPrologue "Hprog".
    destruct (a_m + size)%a as [a_m'|] eqn:Ha_m'; cycle 1.
    { iAssert ([∗ map] k↦x ∈ (∅:gmap RegName Word), k ↦ᵣ x)%I as "Hregs".
        by rewrite big_sepM_empty.
      iDestruct (big_sepM_insert with "[$Hregs $HPC]") as "Hregs".
        by apply lookup_empty.
      iDestruct (big_sepM_insert with "[$Hregs $Hr1]") as "Hregs".
        by rewrite lookup_insert_ne // lookup_empty.
      iDestruct (big_sepM_insert with "[$Hregs $Hr2]") as "Hregs".
        by rewrite !lookup_insert_ne // lookup_empty.
      iApply (wp_lea with "[$Hregs $Hi]");
        [apply decode_encode_instrW_inv| |done|..].
      { apply HPC; repeat constructor. }
      { rewrite /regs_of /regs_of_argument !dom_insert_L dom_empty_L. set_solver-. }
      iNext. iIntros (regs' retv) "(Hspec & ? & ?)". iDestruct "Hspec" as %Hspec.
      destruct Hspec as [| Hfail].
      { exfalso. simplify_map_eq. }
      { cbn. iApply wp_pure_step_later; auto. iNext.
        iApply wp_value. auto. } }
    iApply (wp_lea_success_reg with "[$HPC $Hi $Hr2 $Hr1]");
      [apply decode_encode_instrW_inv| |iContiguous_next Hcont 9|done|done|..].
    { apply HPC; repeat constructor. }
    iEpilogue "(HPC & Hi & Hr1 & Hr2)". iCombine "Hi" "Hprog_done" as "Hprog_done".
    (* geta r_t1 r_t2 *)
    destruct l as [|? l];[inversion Hprog_len|].
    iPrologue "Hprog".
    iApply (wp_Get_success with "[$HPC $Hi $Hr1 $Hr2]");
      [apply decode_encode_instrW_inv|done| |iContiguous_next Hcont 10|..].
    { apply HPC; repeat constructor. }
    iEpilogue "(HPC & Hi & Hr2 & Hr1)". iCombine "Hi" "Hprog_done" as "Hprog_done".
    cbn [rules_Get.denote].
    (* move r_t4 r_t2 *)
    destruct l as [|? l];[inversion Hprog_len|].
    iPrologue "Hprog".
    iApply (wp_move_success_reg with "[$HPC $Hi $Hr4 $Hr2]");
      [apply decode_encode_instrW_inv| |iContiguous_next Hcont 11|..].
    { apply HPC; repeat constructor. }
    iEpilogue "(HPC & Hi & Hr4 & Hr2)". iCombine "Hi" "Hprog_done" as "Hprog_done".
    (* subseg r_t4 r_t3 r_t1 *)
    destruct l as [|? l];[inversion Hprog_len|].
    iPrologue "Hprog".
    destruct (isWithin a_m a_m' b_m e) eqn:Ha_m'_within; cycle 1.
    { iAssert ([∗ map] k↦x ∈ (∅:gmap RegName Word), k ↦ᵣ x)%I as "Hregs".
        by rewrite big_sepM_empty.
      iDestruct (big_sepM_insert with "[$Hregs $HPC]") as "Hregs".
        by apply lookup_empty.
      iDestruct (big_sepM_insert with "[$Hregs $Hr1]") as "Hregs".
        by rewrite lookup_insert_ne // lookup_empty.
      iDestruct (big_sepM_insert with "[$Hregs $Hr3]") as "Hregs".
        by rewrite !lookup_insert_ne // lookup_empty.
      iDestruct (big_sepM_insert with "[$Hregs $Hr4]") as "Hregs".
        by rewrite !lookup_insert_ne // lookup_empty.
      iApply (wp_Subseg with "[$Hregs $Hi]");
        [apply decode_encode_instrW_inv| |done|..].
      { apply HPC; repeat constructor. }
      { rewrite /regs_of /regs_of_argument !dom_insert_L dom_empty_L. set_solver-. }
      iNext. iIntros (regs' retv) "(Hspec & ? & ?)". iDestruct "Hspec" as %Hspec.
      destruct Hspec as [| Hfail].
      { exfalso. unfold addr_of_argument in *. simplify_map_eq.
        repeat match goal with H:_ |- _ => apply z_to_addr_eq_inv in H end; subst.
        congruence. }
      { cbn. iApply wp_pure_step_later; auto. iNext. iApply wp_value. auto. } }
    iApply (wp_subseg_success with "[$HPC $Hi $Hr4 $Hr3 $Hr1]");
      [apply decode_encode_instrW_inv| |split;apply z_to_addr_z_of|done|done|..].
    { apply HPC; repeat constructor. }
    { iContiguous_next Hcont 12. }
    iEpilogue "(HPC & Hi & Hr3 & Hr1 & Hr4)". iCombine "Hi" "Hprog_done" as "Hprog_done".
    (* sub r_t3 r_t3 r_t1 *)
    destruct l as [|? l];[inversion Hprog_len|].
    iPrologue "Hprog".
    iApply (wp_add_sub_lt_success_dst_r with "[$HPC $Hi $Hr1 $Hr3]");
      [apply decode_encode_instrW_inv|done|iContiguous_next Hcont 13|..].
    { apply HPC; repeat constructor. }
    iEpilogue "(HPC & Hi & Hr1 & Hr3)". iCombine "Hi" "Hprog_done" as "Hprog_done".
    cbn [denote].
    (* lea r_t4 r_t3 *)
    destruct l as [|? l];[inversion Hprog_len|].
    iPrologue "Hprog".
    iApply (wp_lea_success_reg with "[$HPC $Hi $Hr4 $Hr3]");
      [apply decode_encode_instrW_inv| |iContiguous_next Hcont 14| |done|..].
    { apply HPC; repeat constructor. }
    { transitivity (Some a_m); auto. clear; solve_addr. }
    iEpilogue "(HPC & Hi & Hr3 & Hr4)". iCombine "Hi" "Hprog_done" as "Hprog_done".
    (* move r_t3 r_t2 *)
    destruct l as [|? l];[inversion Hprog_len|].
    iPrologue "Hprog".
    iApply (wp_move_success_reg with "[$HPC $Hi $Hr3 $Hr2]");
      [apply decode_encode_instrW_inv| |iContiguous_next Hcont 15|..].
    { apply HPC; repeat constructor. }
    iEpilogue "(HPC & Hi & Hr3 & Hr2)". iCombine "Hi" "Hprog_done" as "Hprog_done".
    (* sub r_t1 0 r_t1 *)
    destruct l as [|? l];[inversion Hprog_len|].
    iPrologue "Hprog".
    iApply (wp_add_sub_lt_success_z_dst with "[$HPC $Hi $Hr1]");
      [apply decode_encode_instrW_inv|done|iContiguous_next Hcont 16|..].
    { apply HPC; repeat constructor. }
    iEpilogue "(HPC & Hi & Hr1)". iCombine "Hi" "Hprog_done" as "Hprog_done".
    cbn [denote].
    (* lea r_t3 r_t1 *)
    destruct l as [|? l];[inversion Hprog_len|].
    iPrologue "Hprog".
    iApply (wp_lea_success_reg with "[$HPC $Hi $Hr3 $Hr1]");
      [apply decode_encode_instrW_inv| |iContiguous_next Hcont 17| |done|..].
    { apply HPC; repeat constructor. }
    { transitivity (Some 0)%a; auto. clear; solve_addr. }
    iEpilogue "(HPC & Hi & Hr1 & Hr3)". iCombine "Hi" "Hprog_done" as "Hprog_done".
    (* getb r_t1 r_t3 *)
    destruct l as [|? l];[inversion Hprog_len|].
    iPrologue "Hprog".
    iApply (wp_Get_success with "[$HPC $Hi $Hr1 $Hr3]");
      [apply decode_encode_instrW_inv|done| |iContiguous_next Hcont 18|..].
    { apply HPC; repeat constructor. }
    iEpilogue "(HPC & Hi & Hr3 & Hr1)". iCombine "Hi" "Hprog_done" as "Hprog_done".
    cbn [rules_Get.denote].
    (* lea r_t3 r_t1 *)
    destruct l as [|? l];[inversion Hprog_len|].
    iPrologue "Hprog".
    iApply (wp_lea_success_reg with "[$HPC $Hi $Hr3 $Hr1]");
      [apply decode_encode_instrW_inv| |iContiguous_next Hcont 19| |done|..].
    { apply HPC; repeat constructor. }
    { transitivity (Some b_m)%a; auto. clear; solve_addr. }
    iEpilogue "(HPC & Hi & Hr1 & Hr3)". iCombine "Hi" "Hprog_done" as "Hprog_done".
    (* store r_t3 r_t2 *)
    destruct l as [|? l];[inversion Hprog_len|].
    iPrologue "Hprog".
    iApply (wp_store_success_reg with "[$HPC $Hi $Hr2 $Hr3 $Hmemptr]");
      [apply decode_encode_instrW_inv| |iContiguous_next Hcont 20|split;try done|auto|..].
    { apply HPC; repeat constructor. }
    { apply le_addr_withinBounds.
      - generalize (contiguous_between_length _ _ _ Hcont). cbn.
        clear; solve_addr.
      - revert Hbm_am Ham_e; solve_addr. }
    iEpilogue "(HPC & Hi & Hr2 & Hr3 & Hmemptr)". iCombine "Hi" "Hprog_done" as "Hprog_done".
    (* move r_t1 r_t4 *)
    destruct l as [|? l];[inversion Hprog_len|].
    iPrologue "Hprog".
    iApply (wp_move_success_reg with "[$HPC $Hi $Hr1 $Hr4]");
      [apply decode_encode_instrW_inv| |iContiguous_next Hcont 21|..].
    { apply HPC; repeat constructor. }
    iEpilogue "(HPC & Hi & Hr1 & Hr4)". iCombine "Hi" "Hprog_done" as "Hprog_done".
    (* move r_t2 0 *)
    destruct l as [|? l];[inversion Hprog_len|].
    iPrologue "Hprog".
    iApply (wp_move_success_z with "[$HPC $Hi $Hr2]");
      [apply decode_encode_instrW_inv| |iContiguous_next Hcont 22|..].
    { apply HPC; repeat constructor. }
    iEpilogue "(HPC & Hi & Hr2)". iCombine "Hi" "Hprog_done" as "Hprog_done".
    (* move r_t3 0 *)
    destruct l as [|? l];[inversion Hprog_len|].
    iPrologue "Hprog".
    iApply (wp_move_success_z with "[$HPC $Hi $Hr3]");
      [apply decode_encode_instrW_inv| |iContiguous_next Hcont 23|..].
    { apply HPC; repeat constructor. }
    iEpilogue "(HPC & Hi & Hr3)". iCombine "Hi" "Hprog_done" as "Hprog_done".
    (* move r_t4 0 *)
    destruct l as [|? l];[inversion Hprog_len|].
    iPrologue "Hprog".
    iApply (wp_move_success_z with "[$HPC $Hi $Hr4]");
      [apply decode_encode_instrW_inv| |iContiguous_next Hcont 24|..].
    { apply HPC; repeat constructor. }
    iEpilogue "(HPC & Hi & Hr4)". iCombine "Hi" "Hprog_done" as "Hprog_done".
    (* jmp r_t0 *)
    iPrologue "Hprog".
    iApply (wp_jmp_success with "[$HPC $Hi $Hr0]");
      [apply decode_encode_instrW_inv|..].
    { apply HPC; repeat constructor. }
    iEpilogue "(HPC & Hi & Hr0)". iCombine "Hi" "Hprog_done" as "Hprog_done".
    (* continuation *)
    destruct l;[|inversion Hprog_len].
    assert ((a_m <= a_m')%a ∧ (a_m' <= e)%a).
    { unfold isWithin in Ha_m'_within. (* FIXME? *)
      rewrite andb_true_iff !Z.leb_le in Ha_m'_within |- *.
      revert Ha_m' Hsize; clear. solve_addr. }
    rewrite (region_addrs_zeroes_split _ a_m') //;[].
    iDestruct (region_mapsto_split _ _ a_m' with "Hmem") as "[Hmem_fresh Hmem]"; auto.
    { rewrite replicate_length //. }
    iDestruct ("Hinv_close" with "[Hprog_done Hmemptr Hmem $Hna]") as ">Hna".
    { iNext. iExists b_m, a_m'. iFrame.
      rewrite /malloc_subroutine_instrs /malloc_subroutine_instrs'.
      unfold region_mapsto. rewrite Hai. cbn.
      do 25 iDestruct "Hprog_done" as "[? Hprog_done]". iFrame.
      iPureIntro.
      unfold isWithin in Ha_m'_within. (* FIXME? *)
      rewrite andb_true_iff !Z.leb_le in Ha_m'_within |- *.
      revert Ha_m' Hsize; clear; solve_addr. }

    iApply (wp_wand with "[-]").
    { iApply "Hφ". iFrame.
      iDestruct (big_sepM_insert with "[$Hrmap $Hr4]") as "Hrmap".
      by rewrite lookup_delete. rewrite insert_delete.
      iDestruct (big_sepM_insert with "[$Hrmap $Hr3]") as "Hrmap".
      by rewrite lookup_insert_ne // lookup_delete //.
      rewrite insert_commute // insert_delete.
      iDestruct (big_sepM_insert with "[$Hrmap $Hr2]") as "Hrmap".
      by rewrite !lookup_insert_ne // lookup_delete //.
      rewrite (insert_commute _ r_t2 r_t4) // (insert_commute _ r_t2 r_t3) //.
      rewrite insert_delete.
      rewrite (insert_commute _ r_t3 r_t2) // (insert_commute _ r_t4 r_t2) //.
      rewrite (insert_commute _ r_t4 r_t3) //. iFrame.
      iExists a_m, a_m', size. iFrame. auto. }
    { auto. }
  Qed.

  Ltac consider_next_reg r1 r2 :=
    destruct (decide (r1 = r2));[subst;rewrite lookup_insert;eauto|rewrite lookup_insert_ne;auto].

  
  Lemma allocate_region_inv E ba ea :
    [[ba,ea]]↦ₐ[[region_addrs_zeroes ba ea]]
    ={E}=∗ [∗ list] a ∈ region_addrs ba ea, (inv (logN .@ a) (interp_ref_inv a interp)).
  Proof.
    iIntros "Hbae".
    iApply big_sepL_fupd.
    rewrite /region_mapsto /region_addrs_zeroes -region_addrs_length.
    iDestruct (big_sepL2_to_big_sepL_replicate with "Hbae") as "Hbae". 
    iApply (big_sepL_mono with "Hbae").
    iIntros (k y Hky) "Ha". 
    iApply inv_alloc. iNext. iExists (inl 0%Z). iFrame.
    rewrite fixpoint_interp1_eq. auto. 
  Qed. 
    
  Lemma simple_malloc_subroutine_valid N b e :
    na_inv logrel_nais N (malloc_inv b e) -∗
    interp (inr (E,b,e,b)). 
  Proof.
    iIntros "#Hmalloc".
    rewrite fixpoint_interp1_eq /=. iIntros (r). iNext. iAlways.
    iIntros "(#[% Hregs_valid] & Hregs & Hown)".
    iSplit;auto.
    iDestruct (big_sepM_delete _ _ PC with "Hregs") as "[HPC Hregs]";[rewrite lookup_insert;eauto|].
    destruct H with r_t0 as [? ?]. 
    iDestruct (big_sepM_delete _ _ r_t0 with "Hregs") as "[r_t0 Hregs]";[rewrite !lookup_delete_ne// !lookup_insert_ne//;eauto|].
    destruct H with r_t1 as [? ?]. 
    iDestruct (big_sepM_delete _ _ r_t1 with "Hregs") as "[r_t1 Hregs]";[rewrite !lookup_delete_ne// !lookup_insert_ne//;eauto|].
    iApply (wp_wand with "[-]").
    iApply (simple_malloc_subroutine_spec with "[- $Hown $Hmalloc $Hregs $r_t0 $HPC $r_t1]");[|solve_ndisj|]. 
    3: { iSimpl. iIntros (v) "[H | ->]". iExact "H". iIntros (Hcontr); done. }
    { rewrite !dom_delete_L dom_insert_L. apply regmap_full_dom in H as <-. set_solver. }
    iDestruct ("Hregs_valid" $! r_t0 with "[]") as "Hr0_valid";auto. 
    rewrite /RegLocate H0.
    iDestruct (jmp_or_fail_spec with "Hr0_valid") as "Hcont".
    destruct (decide (isCorrectPC (updatePcPerm x))).
    2: { iNext. iIntros "(_ & _ & HPC & _)". iApply "Hcont". iFrame. iIntros (Hcontr). done. } 
    iDestruct "Hcont" as (p b' e' a Heq) "Hcont". simplify_eq.
    iNext. iIntros "((Hown & Hregs) & Hr_t0 & HPC & Hres)".
    iDestruct "Hres" as (ba ea size Hsizeq Hsize) "[Hr_t1 Hbe]".
    (* Next is the interesting part of the spec: we must allocate the invariants making the malloced region valid *)
    iMod (allocate_region_inv with "Hbe") as "#Hbe".     
    rewrite -!(delete_insert_ne _ r_t1)//. 
    iDestruct (big_sepM_insert with "[$Hregs $Hr_t1]") as "Hregs";[apply lookup_delete|rewrite insert_delete].
    rewrite -!(delete_insert_ne _ r_t0)//. 
    iDestruct (big_sepM_insert with "[$Hregs $Hr_t0]") as "Hregs";[apply lookup_delete|rewrite insert_delete delete_insert_delete].
    rewrite -!(delete_insert_ne _ PC)//.
    iDestruct (big_sepM_insert with "[$Hregs $HPC]") as "Hregs";[apply lookup_delete|rewrite insert_delete].
    set regs := <[PC:=updatePcPerm (inr (p, b', e', a))]>
                            (<[r_t0:=inr (p, b', e', a)]> (<[r_t1:=inr (RWX, ba, ea, ba)]> (<[r_t2:=inl 0%Z]> (<[r_t3:=inl 0%Z]> (<[r_t4:=inl 0%Z]> r))))).  
    iDestruct ("Hcont" $! regs with "[$Hown Hregs Hbe]") as "[_ $]". 
    iSplitR "Hregs". 
    { rewrite /regs. iSplit. 
      - iPureIntro. intros x. consider_next_reg x PC. consider_next_reg x r_t0. consider_next_reg x r_t1.
        consider_next_reg x r_t2. consider_next_reg x r_t3. consider_next_reg x r_t4.
      - iIntros (x Hne). rewrite /RegLocate. consider_next_reg x PC;[contradiction|].
        consider_next_reg x r_t0.
        { iDestruct ("Hregs_valid" $! r_t0 with "[]") as "Hr0_valid";auto. rewrite H0. iFrame. }
        consider_next_reg x r_t1.
        { rewrite fixpoint_interp1_eq. iApply (big_sepL_mono with "Hbe").
          iIntros (k y Hky) "Ha". iExists interp. iFrame. rewrite /interp /fixpoint_interp1_eq /=. iSplit;auto. }
        consider_next_reg x r_t2. by rewrite fixpoint_interp1_eq.
        consider_next_reg x r_t3. by rewrite fixpoint_interp1_eq.
        consider_next_reg x r_t4. by rewrite fixpoint_interp1_eq.
        iApply "Hregs_valid". auto. 
    }
    { rewrite /regs. rewrite insert_insert. iFrame. }
  Qed. 

    
End SimpleMalloc.

