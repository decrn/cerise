From iris.algebra Require Import frac.
From iris.proofmode Require Import tactics.
From iris.base_logic Require Import invariants.
Require Import Eqdep_dec.
From cap_machine Require Import rules logrel fundamental. 
From cap_machine.examples Require Import macros malloc counter.
From stdpp Require Import countable.

Section counter_example_preamble.
  Context {Σ:gFunctors} {memg:memG Σ} {regg:regG Σ}
          {nainv: logrel_na_invs Σ}
          `{MP: MachineParameters}.

  Definition counter f_a a :=
    ([∗ list] a_i;w ∈ a;(incr_instrs ++ (read_instrs f_a) ++ reset_instrs), a_i ↦ₐ w )%I. 
  
  (* [f_m] is the offset of the malloc capability *)
  (* [offset_to_counter] is the offset between the [move_r r_t1 PC] instruction
  and the code of the counter, which will be the concatenation of: incr;read;reset *)
  Definition counter_preamble_instrs (f_m offset_to_counter: Z) :=
    malloc_instrs f_m 1%nat ++
    [store_z r_t1 0;
    move_r r_t2 r_t1;
    move_r r_t1 PC;
    move_r r_t8 r_t2; (* we keep a copy of the capability for the other closures *)
    move_r r_t9 r_t1; (* same for PC *)
    (* closure for incr *)
    lea_z r_t1 offset_to_counter] ++
    crtcls_instrs f_m ++
    [move_r r_t10 r_t1;
    move_r r_t2 r_t8;
    move_r r_t1 r_t9;
    (* closure for read *)
    lea_z r_t1 (offset_to_counter + (strings.length (incr_instrs)))] ++
    crtcls_instrs f_m ++
    [move_r r_t11 r_t1;
    move_r r_t2 r_t8;
    move_r r_t1 r_t9;
    (* closure for reset *)
    lea_z r_t1 (offset_to_counter + (strings.length (incr_instrs)) + (strings.length (read_instrs 0)))] ++
    crtcls_instrs f_m ++
    (* cleanup *)
    [move_r r_t2 r_t10;
    move_z r_t10 0;
    move_r r_t3 r_t11;
    move_z r_t11 0;
    jmp r_t0].
  
  Definition counter_preamble f_m offset_to_counter ai :=
    ([∗ list] a_i;w_i ∈ ai;(counter_preamble_instrs f_m offset_to_counter), a_i ↦ₐ w_i)%I.

  (* Compute the offset from the start of the program to the move_r r_t1 PC
     instruction. Will be used later to compute [offset_to_awkward]. *)
  (* This is somewhat overengineered, but could be easily generalized to compute
     offsets for other programs if needed. *)
  Definition counter_preamble_move_offset_ : Z.
  Proof.
    unshelve refine (let x := _ : Z in _). {
      set instrs := counter_preamble_instrs 0 0.
      assert (sig (λ l1, ∃ l2, instrs = l1 ++ l2)) as [l1 _]; [do 2 eexists | exact (length l1)].

      assert (forall A (l1 l2 l3 l4: list A), l2 = l3 ++ l4 → l1 ++ l2 = (l1 ++ l3) ++ l4) as step_app.
      { intros * ->. by rewrite app_assoc. }
      assert (forall A (l1 l2 l3: list A) x, l1 = l2 ++ l3 → x :: l1 = (x :: l2) ++ l3) as step_cons.
      { intros * ->. reflexivity. }
      assert (forall A (l1 l2: list A) x, x :: l1 = l2 → x :: l1 = l2) as prepare_cons.
      { auto. }
      assert (forall A (l: list A), l = [] ++ l) as stop.
      { reflexivity. }

      unfold instrs, counter_preamble_instrs.
      (* Program-specific part *)
      eapply step_app.
      repeat (eapply prepare_cons;
              lazymatch goal with
              | |- move_r r_t1 PC :: _ = _ => fail
              | _ => eapply step_cons end).
      eapply stop.
    }
    exact x.
  Defined.

  Definition counter_preamble_move_offset : Z :=
    Eval cbv in counter_preamble_move_offset_.

  Definition counter_preamble_instrs_length : Z :=
    Eval cbv in (length (counter_preamble_instrs 0 0)).
  
  Ltac iPrologue prog :=
    iDestruct prog as "[Hi Hprog]";
    iApply (wp_bind (fill [SeqCtx])).

  Ltac iEpilogue prog :=
    iNext; iIntros prog; iSimpl;
    iApply wp_pure_step_later;auto;iNext.

  Ltac middle_lt prev index :=
    match goal with
    | Ha_first : ?a !! 0 = Some ?a_first |- _
    => apply Z.lt_trans with prev; auto; apply incr_list_lt_succ with a index; auto
    end.

  Ltac iCorrectPC i j :=
    eapply isCorrectPC_contiguous_range with (a0 := i) (an := j); eauto; [];
    cbn; solve [ repeat constructor ].

  Ltac iContiguous_next Ha index :=
    apply contiguous_of_contiguous_between in Ha;
    generalize (contiguous_spec _ Ha index); auto.

  Definition countN : namespace := nroot .@ "awkN".
  Definition count_invN : namespace := countN .@ "inv".
  Definition count_incrN : namespace := countN .@ "incr".
  Definition count_readN : namespace := countN .@ "read".
  Definition count_resetN : namespace := countN .@ "reset".
  Definition count_clsN : namespace := countN .@ "cls".
  Definition count_env : namespace := countN .@ "env". 

  Lemma awkward_preamble_spec (f_m f_a offset_to_counter: Z) (r: Reg) pc_p pc_b pc_e
        ai a_first a_end b_link e_link a_link a_entry a_entry'
        mallocN b_m e_m fail_cap ai_counter counter_first counter_end a_move:

    isCorrectPC_range pc_p pc_b pc_e a_first a_end →
    contiguous_between ai a_first a_end →
    withinBounds (RW, b_link, e_link, a_entry) = true →
    withinBounds (RW, b_link, e_link, a_entry') = true →
    (a_link + f_m)%a = Some a_entry →
    (a_link + f_a)%a = Some a_entry' →
    (a_first + counter_preamble_move_offset)%a = Some a_move →
    (a_move + offset_to_counter)%a = Some counter_first →
    isCorrectPC_range pc_p pc_b pc_e counter_first counter_end →
    contiguous_between ai_counter counter_first counter_end →

    (* Code of the preamble *)
    counter_preamble f_m offset_to_counter ai

    (* Code of the counter example itself *)
    ∗ counter f_a ai_counter

    (** Resources for malloc and assert **)
    (* assume that a pointer to the linking table (where the malloc capa is) is at offset 0 of PC *)
    ∗ na_inv logrel_nais mallocN (malloc_inv b_m e_m)
    ∗ pc_b ↦ₐ (inr (RO, b_link, e_link, a_link))
    ∗ a_entry ↦ₐ (inr (E, b_m, e_m, b_m))
    ∗ a_entry' ↦ₐ fail_cap

    -∗
    interp_expr interp r (inr (pc_p, pc_b, pc_e, a_first)).
  Proof.
    rewrite /interp_expr /=.
    iIntros (Hvpc Hcont Hwb_malloc Hwb_assert Ha_entry Ha_entry' Ha_lea H_counter_offset Hvpc_counter Hcont_counter)
            "(Hprog & Hcounter & #Hinv_malloc & Hpc_b & Ha_entry & Ha_entry')
             ([#Hr_full #Hr_valid] & Hregs & HnaI)".
    iDestruct "Hr_full" as %Hr_full.
    rewrite /full_map.
    iSplitR; auto. rewrite /interp_conf.
    
    (* put the code for the counter example in an invariant *)
    (* we separate the invariants into its tree functions *)
    iDestruct (contiguous_between_program_split with "Hcounter") as (incr_prog restc linkc)
                                                                   "(Hincr & Hcounter & #Hcont)";[apply Hcont_counter|].
    iDestruct "Hcont" as %(Hcont_incr & Hcont_restc & Heqappc & Hlinkrestc).
    iDestruct (contiguous_between_program_split with "Hcounter") as (read_prog reset_prog linkc')
                                                                   "(Hread & Hreset & #Hcont)";[apply Hcont_restc|].
    iDestruct "Hcont" as %(Hcont_read & Hcont_reset & Heqappc' & Hlinkrestc').
    iDestruct (big_sepL2_length with "Hincr") as %incr_length.
    iDestruct (big_sepL2_length with "Hread") as %read_length.
    iDestruct (big_sepL2_length with "Hreset") as %reset_length.
    
    iDestruct (na_inv_alloc logrel_nais _ count_incrN with "Hincr") as ">#Hincr".
    iDestruct (na_inv_alloc logrel_nais _ count_readN with "Hread") as ">#Hread".
    iDestruct (na_inv_alloc logrel_nais _ count_resetN with "Hreset") as ">#Hreset".
    
    rewrite /registers_mapsto.
    iDestruct (big_sepM_delete _ _ PC with "Hregs") as "[HPC Hregs]".
      by rewrite lookup_insert //. rewrite delete_insert_delete //.
    destruct (Hr_full r_t0) as [r0 Hr0].
    iDestruct (big_sepM_delete _ _ r_t0 with "Hregs") as "[Hr0 Hregs]". by rewrite !lookup_delete_ne//.
    pose proof (regmap_full_dom _ Hr_full) as Hdom_r.
    iDestruct (big_sepL2_length with "Hprog") as %Hlength.
    
    assert (pc_p ≠ E).
    { eapply isCorrectPC_range_perm_non_E. eapply Hvpc.
      pose proof (contiguous_between_length _ _ _ Hcont) as HH. rewrite Hlength /= in HH.
      revert HH; clear; solve_addr. }
    
    (* malloc 1 *)
    iDestruct (contiguous_between_program_split with "Hprog") as
        (ai_malloc ai_rest a_malloc_end) "(Hmalloc & Hprog & #Hcont)"; [apply Hcont|].
    iDestruct "Hcont" as %(Hcont_malloc & Hcont_rest & Heqapp & Hlink).
    iDestruct (big_sepL2_length with "Hmalloc") as %Hai_malloc_len.
    assert (isCorrectPC_range pc_p pc_b pc_e a_first a_malloc_end) as Hvpc1.
    { eapply isCorrectPC_range_restrict. apply Hvpc.
      generalize (contiguous_between_bounds _ _ _ Hcont_rest). clear; solve_addr. }
    assert (isCorrectPC_range pc_p pc_b pc_e a_malloc_end a_end) as Hvpc2.
    { eapply isCorrectPC_range_restrict. apply Hvpc.
      generalize (contiguous_between_bounds _ _ _ Hcont_malloc). clear; solve_addr. }
    rewrite -/(malloc _ _ _ _).
    iApply (wp_wand with "[-]").
    iApply (malloc_spec with "[- $HPC $Hmalloc $Hpc_b $Ha_entry $Hr0 $Hregs $Hinv_malloc $HnaI]");
      [apply Hvpc1|eapply Hcont_malloc|eapply Hwb_malloc|eapply Ha_entry| |auto|lia|..].
    { rewrite !dom_delete_L Hdom_r difference_difference_L //. }
    iNext. iIntros "(HPC & Hmalloc & Hpc_b & Ha_entry & HH & Hr0 & HnaI & Hregs)".
    iDestruct "HH" as (b_cell e_cell Hbe_cell) "(Hr1 & Hcell)".
    iDestruct (region_mapsto_single with "Hcell") as (cellv) "(Hcell & _)". revert Hbe_cell; clear; solve_addr.
    iDestruct (big_sepL2_length with "Hprog") as %Hlength_rest.
    2: { iIntros (?) "[HH | ->]". iApply "HH". iIntros (Hv). inversion Hv. }
    
    destruct ai_rest as [| a l]; [by inversion Hlength|].
    pose proof (contiguous_between_cons_inv_first _ _ _ _ Hcont_rest) as ->.
    (* store_z r_t1 0 *)
    destruct l as [| ? l]; [by inversion Hlength_rest|].
    iPrologue "Hprog".
    iApply (wp_store_success_z with "[$HPC $Hr1 $Hi $Hcell]");
      [apply decode_encode_instrW_inv|iCorrectPC a_malloc_end a_end|
       iContiguous_next Hcont_rest 0|..].
    { split; auto. apply le_addr_withinBounds; revert Hbe_cell; clear; solve_addr. }
    iEpilogue "(HPC & Hprog_done & Hr1 & Hb_cell)". iCombine "Hprog_done" "Hmalloc" as "Hprog_done".
    (* move_r r_t2 r_t1 *)
    iDestruct (big_sepM_delete _ _ r_t2 with "Hregs") as "[Hr2 Hregs]".
      by rewrite lookup_insert. rewrite delete_insert_delete.
    destruct l as [| a_move' l]; [by inversion Hlength_rest|].
    iPrologue "Hprog".
    iApply (wp_move_success_reg _ _ _ _ _ _ _ r_t2 _ r_t1 with "[$HPC $Hi $Hr1 $Hr2]");
      [eapply decode_encode_instrW_inv|iCorrectPC a_malloc_end a_end|iContiguous_next Hcont_rest 1|..].
    iEpilogue "(HPC & Hi & Hr2 & Hr1)". iCombine "Hi" "Hprog_done" as "Hprog_done".
    (* move_r r_t1 PC *)
    destruct l as [| ? l]; [by inversion Hlength_rest|].
    iPrologue "Hprog".
    iApply (wp_move_success_reg_fromPC with "[$HPC $Hi $Hr1]");
      [eapply decode_encode_instrW_inv|iCorrectPC a_malloc_end a_end|iContiguous_next Hcont_rest 2|..].
    iEpilogue "(HPC & Hi & Hr1)". iCombine "Hi" "Hprog_done" as "Hprog_done".
    (* move_r r_t8 r_t2 *)
    assert (is_Some (r !! r_t8)) as [w8 Hrt8].
    { apply elem_of_gmap_dom. rewrite Hdom_r. apply all_registers_s_correct. }
    iDestruct (big_sepM_delete _ _ r_t8 with "Hregs") as "[Hr_t8 Hregs]".
    { rewrite lookup_delete_ne;[|by auto]. rewrite !lookup_insert_ne;auto; rewrite !lookup_delete_ne;auto. eauto. }
    destruct l as [| ? l]; [by inversion Hlength_rest|].
    iPrologue "Hprog".
    iApply (wp_move_success_reg with "[$HPC $Hi $Hr_t8 $Hr2]");
      [eapply decode_encode_instrW_inv|iCorrectPC a_malloc_end a_end|iContiguous_next Hcont_rest 3|..].
    iEpilogue "(HPC & Hi & Hr_t8 & Hr2)". iCombine "Hi" "Hprog_done" as "Hprog_done".
    iDestruct (big_sepM_insert _ _ r_t8 with "[$Hregs $Hr_t8]") as "Hregs";[apply lookup_delete|rewrite insert_delete].
    (* move_r r_t9 r_t1 *)
    assert (is_Some (r !! r_t9)) as [w9 Hrt9].
    { apply elem_of_gmap_dom. rewrite Hdom_r. apply all_registers_s_correct. }
    iDestruct (big_sepM_delete _ _ r_t9 with "Hregs") as "[Hr_t8 Hregs]".
    { rewrite lookup_insert_ne;[|by auto]. rewrite lookup_delete_ne;auto. rewrite !lookup_insert_ne;auto; rewrite !lookup_delete_ne;auto. eauto. }
    destruct l as [| ? l]; [by inversion Hlength_rest|].
    iPrologue "Hprog".
    iApply (wp_move_success_reg with "[$HPC $Hi $Hr_t8 $Hr1]");
      [eapply decode_encode_instrW_inv|iCorrectPC a_malloc_end a_end|iContiguous_next Hcont_rest 4|..].
    iEpilogue "(HPC & Hi & Hr_t8 & Hr1)". iCombine "Hi" "Hprog_done" as "Hprog_done".
    iDestruct (big_sepM_insert _ _ r_t9 with "[$Hregs $Hr_t8]") as "Hregs";[apply lookup_delete|rewrite insert_delete].
    (* lea_z r_t1 offset_to_awkward *)
    assert (a_move' = a_move) as ->.
    { assert ((a_first + (length ai_malloc + 2))%a = Some a_move') as HH.
      { rewrite Hai_malloc_len /= in Hlink |- *.
        generalize (contiguous_between_incr_addr_middle _ _ _ 0 2 _ _ Hcont_rest eq_refl eq_refl).
        revert Hlink; clear; solve_addr. }
      revert HH Ha_lea. rewrite Hai_malloc_len. cbn. clear.
      unfold counter_preamble_move_offset. solve_addr. }
    destruct l as [| ? l]; [by inversion Hlength_rest|].
    iPrologue "Hprog".
    iApply (wp_lea_success_z _ _ _ _ _ _ _ _ _ _ _ _ _ counter_first with "[$HPC $Hi $Hr1]");
      [eapply decode_encode_instrW_inv|iCorrectPC a_malloc_end a_end|iContiguous_next Hcont_rest 5
       |assumption|done|..].
    (* { destruct (isCorrectPC_range_perm _ _ _ _ _ _ Hvpc) as [-> | [-> | ->] ]; auto. *)
    (*   generalize (contiguous_between_middle_bounds _ (length ai_malloc) a_malloc_end _ _ Hcont ltac:(subst ai; rewrite list_lookup_middle; auto)). clear. solve_addr. } *)
    iEpilogue "(HPC & Hi & Hr1)". iCombine "Hi" "Hprog_done" as "Hprog_done".
    (* crtcls *)
    iDestruct (contiguous_between_program_split with "Hprog") as
        (ai_crtcls ai_rest a_crtcls_end) "(Hcrtcls & Hprog & #Hcont)".
    { epose proof (contiguous_between_incr_addr _ 6%nat _ _ _ Hcont_rest eq_refl).
      eapply contiguous_between_app with (a1:=[_;_;_;_;_;_]). 2: eapply Hcont_rest.
      all: eauto. }
    iDestruct "Hcont" as %(Hcont_crtcls & Hcont_rest' & Heqapp' & Hlink').
    assert (a_malloc_end <= a3)%a as Ha1_after_malloc.
    { eapply contiguous_between_middle_bounds'. apply Hcont_rest. repeat constructor. }
    iApply (wp_wand with "[-]").
    iApply (crtcls_spec with "[- $HPC $Hcrtcls $Hpc_b $Ha_entry $Hr0 $Hregs $Hr1 $Hr2 $HnaI $Hinv_malloc]");
      [|apply Hcont_crtcls|apply Hwb_malloc|apply Ha_entry| |done|auto|..].
    { eapply isCorrectPC_range_restrict. apply Hvpc2. split; auto.
      eapply contiguous_between_bounds. apply Hcont_rest'. }
    { rewrite !dom_insert_L dom_delete_L !dom_insert_L !dom_delete_L Hdom_r.
      clear. set_solver-. }
    2: { iIntros (?) "[ H | -> ]". iApply "H". iIntros (HC). congruence. }
    iNext. iIntros "(HPC & Hcrtcls & Hpc_b & Ha_entry & HH)".
    iDestruct "HH" as (b_cls e_cls Hbe_cls) "(Hr1 & Hbe_cls & Hr0 & Hr2 & HnaI & Hregs)".
    iDestruct (big_sepL2_length with "Hprog") as %Hlength_rest'.
    (* register map cleanup *)
    rewrite delete_insert_ne;auto. repeat (rewrite (insert_commute _ r_t3);[|by auto]). rewrite insert_insert. 
    repeat (rewrite (insert_commute _ r_t5);[|by auto]). rewrite -delete_insert_ne;auto. rewrite (insert_commute _ r_t5);auto. rewrite insert_insert. 
    repeat (rewrite -(insert_commute _ r_t9);auto).  repeat (rewrite -(insert_commute _ r_t8);auto).

    assert (isCorrectPC_range pc_p pc_b pc_e a_crtcls_end a_end) as Hvpc3. 
    { eapply isCorrectPC_range_restrict. apply Hvpc2.
      generalize (contiguous_between_bounds _ _ _ Hcont_rest').
      revert Ha1_after_malloc Hlink'. clear; solve_addr. }
    (* move r_t10 r_t1 *)
    assert (is_Some (r !! r_t10)) as [w10 Hrt10].
    { apply elem_of_gmap_dom. rewrite Hdom_r. apply all_registers_s_correct. }
    iDestruct (big_sepM_delete _ _ r_t10 with "Hregs") as "[Hr_t10 Hregs]".
    { rewrite !lookup_insert_ne;auto. rewrite lookup_delete_ne;[|by auto]. rewrite !lookup_insert_ne;auto; rewrite !lookup_delete_ne;auto. eauto. }
    destruct ai_rest as [| ? ai_rest]; [by inversion Hlength_rest'|].
    pose proof (contiguous_between_cons_inv_first _ _ _ _ Hcont_rest') as ->.
    destruct ai_rest as [| ? ai_rest]; [by inversion Hlength_rest'|].
    iPrologue "Hprog".
    iApply (wp_move_success_reg with "[$HPC $Hi $Hr_t10 $Hr1]");
      [eapply decode_encode_instrW_inv|iCorrectPC a_crtcls_end a_end|iContiguous_next Hcont_rest' 0|..].
    iEpilogue "(HPC & Hi & Hr_t10 & Hr1)". iCombine "Hi" "Hprog_done" as "Hprog_done".
    iDestruct (big_sepM_insert _ _ r_t10 with "[$Hregs $Hr_t10]") as "Hregs";[apply lookup_delete|rewrite insert_delete].
    (* move r_t2 r_t8 *)
    iDestruct (big_sepM_delete _ _ r_t8 with "Hregs") as "[Hr_t8 Hregs]".
    { rewrite lookup_insert_ne;auto. apply lookup_insert. }
    destruct ai_rest as [| ? ai_rest]; [by inversion Hlength_rest'|].
    iPrologue "Hprog".
    iApply (wp_move_success_reg with "[$HPC $Hi $Hr2 $Hr_t8]");
      [eapply decode_encode_instrW_inv|iCorrectPC a_crtcls_end a_end|iContiguous_next Hcont_rest' 1|..].
    iEpilogue "(HPC & Hi & Hr2 & Hr_t8)". iCombine "Hi" "Hprog_done" as "Hprog_done".
    iDestruct (big_sepM_insert _ _ r_t8 with "[$Hregs $Hr_t8]") as "Hregs";[apply lookup_delete|rewrite insert_delete insert_commute;auto;rewrite insert_insert].
    (* move r_t1 r_t9 *)
    iDestruct (big_sepM_delete _ _ r_t9 with "Hregs") as "[Hr_t9 Hregs]".
    { rewrite lookup_insert_ne;auto. rewrite lookup_insert_ne;auto. apply lookup_insert. }
    destruct ai_rest as [| ? ai_rest]; [by inversion Hlength_rest'|].
    iPrologue "Hprog".
    iApply (wp_move_success_reg with "[$HPC $Hi $Hr1 $Hr_t9]");
      [eapply decode_encode_instrW_inv|iCorrectPC a_crtcls_end a_end|iContiguous_next Hcont_rest' 2|..].
    iEpilogue "(HPC & Hi & Hr1 & Hr_t9)". iCombine "Hi" "Hprog_done" as "Hprog_done".
    iDestruct (big_sepM_insert _ _ r_t9 with "[$Hregs $Hr_t9]") as "Hregs";[apply lookup_delete|rewrite insert_delete !(insert_commute _ _ r_t9);auto].
    rewrite insert_insert. 
    (* lea r_t1 offset_to_counter + length incr_instrs *)
    assert ((a_move + (offset_to_counter + (length incr_instrs)))%a = Some linkc) as H_counter_offset'.
    { revert Hlinkrestc H_counter_offset incr_length. clear. intros. solve_addr. }
    destruct ai_rest as [| ? ai_rest]; [by inversion Hlength_rest'|].
    iPrologue "Hprog".
    iApply (wp_lea_success_z _ _ _ _ _ _ _ _ _ _ _ _ _ linkc with "[$HPC $Hi $Hr1]");
      [eapply decode_encode_instrW_inv|iCorrectPC a_crtcls_end a_end|iContiguous_next Hcont_rest' 3|assumption|done|..].
    iEpilogue "(HPC & Hi & Hr1)". iCombine "Hi" "Hprog_done" as "Hprog_done".
    (* crtcls *)
    iDestruct (contiguous_between_program_split with "Hprog") as
        (ai_crtcls' ai_rest' a_crtcls_end') "(Hcrtcls' & Hprog & #Hcont)".
    { epose proof (contiguous_between_incr_addr _ 4%nat _ _ _ Hcont_rest' eq_refl).
      eapply contiguous_between_app with (a1:=[_;_;_;_]). 2: eapply Hcont_rest'.
      all: eauto. }
    iDestruct "Hcont" as %(Hcont_crtcls' & Hcont_rest'' & Heqapp'' & Hlink'').
    assert (a_crtcls_end <= a7)%a as Ha1_after_crtcls.
    { eapply contiguous_between_middle_bounds'. apply Hcont_rest'. repeat constructor. }
    iApply (wp_wand with "[-]").
    iApply (crtcls_spec with "[- $HPC $Hcrtcls' $Hpc_b $Ha_entry $Hr0 $Hregs $Hr1 $Hr2 $HnaI $Hinv_malloc]");
      [|apply Hcont_crtcls'|apply Hwb_malloc|apply Ha_entry| |done|auto|..].
    { eapply isCorrectPC_range_restrict. apply Hvpc3. split; auto.
      eapply contiguous_between_bounds. apply Hcont_rest''. }
    { rewrite !dom_insert_L dom_delete_L !dom_insert_L !dom_delete_L Hdom_r.
      clear. set_solver-. }
    2: { iIntros (?) "[ H | -> ]". iApply "H". iIntros (HC). congruence. }
    iNext. iIntros "(HPC & Hcrtcls' & Hpc_b & Ha_entry & HH)".
    iDestruct "HH" as (b_cls' e_cls' Hbe_cls') "(Hr1 & Hbe_cls' & Hr0 & Hr2 & HnaI & Hregs)".
    iDestruct (big_sepL2_length with "Hprog") as %Hlength_rest''.
    (* register map cleanup *)
    repeat (rewrite (insert_commute _ _ r_t3);[|by auto]);rewrite insert_insert. 
    repeat (rewrite (insert_commute _ _ r_t4);[|by auto]);rewrite insert_insert. 
    repeat (rewrite (insert_commute _ _ r_t6);[|by auto]);rewrite insert_insert. 
    repeat (rewrite (insert_commute _ _ r_t7);[|by auto]);rewrite insert_insert. 
    do 2 (rewrite delete_insert_ne;auto). repeat (rewrite (insert_commute _ _ r_t5);[|by auto]);rewrite insert_insert. 
    repeat (rewrite (insert_commute _ _ r_t4);[|by auto]);rewrite insert_insert. 

    assert (isCorrectPC_range pc_p pc_b pc_e a_crtcls_end' a_end) as Hvpc4. 
    { eapply isCorrectPC_range_restrict. apply Hvpc3.
      generalize (contiguous_between_bounds _ _ _ Hcont_rest'').
      revert Ha1_after_malloc Ha1_after_crtcls Hlink'' Hlink'. clear; solve_addr. }
    (* move r_t11 r_t1 *)
    assert (is_Some (r !! r_t11)) as [w11 Hrt11].
    { apply elem_of_gmap_dom. rewrite Hdom_r. apply all_registers_s_correct. }
    iDestruct (big_sepM_delete _ _ r_t11 with "Hregs") as "[Hr_t11 Hregs]".
    { rewrite !lookup_insert_ne;auto.  rewrite !lookup_delete_ne;auto. eauto. }
    destruct ai_rest' as [| ? ai_rest']; [by inversion Hlength_rest''|].
    pose proof (contiguous_between_cons_inv_first _ _ _ _ Hcont_rest'') as ->.
    destruct ai_rest' as [| ? ai_rest']; [by inversion Hlength_rest''|].
    iPrologue "Hprog".
    iApply (wp_move_success_reg with "[$HPC $Hi $Hr_t11 $Hr1]");
      [eapply decode_encode_instrW_inv|iCorrectPC a_crtcls_end' a_end|iContiguous_next Hcont_rest'' 0|..].
    iEpilogue "(HPC & Hi & Hr_t11 & Hr1)". iCombine "Hi" "Hprog_done" as "Hprog_done".
    iDestruct (big_sepM_insert _ _ r_t11 with "[$Hregs $Hr_t11]") as "Hregs";[apply lookup_delete|rewrite insert_delete].
    (* move r_t2 r_t8 *)
    iDestruct (big_sepM_delete _ _ r_t8 with "Hregs") as "[Hr_t8 Hregs]".
    { repeat (rewrite lookup_insert_ne;[|by auto]). apply lookup_insert. }
    destruct ai_rest' as [| ? ai_rest']; [by inversion Hlength_rest''|].
    iPrologue "Hprog".
    iApply (wp_move_success_reg with "[$HPC $Hi $Hr2 $Hr_t8]");
      [eapply decode_encode_instrW_inv|iCorrectPC a_crtcls_end' a_end|iContiguous_next Hcont_rest'' 1|..].
    iEpilogue "(HPC & Hi & Hr2 & Hr_t8)". iCombine "Hi" "Hprog_done" as "Hprog_done".
    iDestruct (big_sepM_insert _ _ r_t8 with "[$Hregs $Hr_t8]") as "Hregs";[apply lookup_delete|rewrite insert_delete !(insert_commute _ _ r_t8);auto;rewrite insert_insert].
    (* move r_t1 r_t9 *)
    iDestruct (big_sepM_delete _ _ r_t9 with "Hregs") as "[Hr_t9 Hregs]".
    { repeat (rewrite lookup_insert_ne;[|by auto]). apply lookup_insert. }
    destruct ai_rest' as [| ? ai_rest']; [by inversion Hlength_rest''|].
    iPrologue "Hprog".
    iApply (wp_move_success_reg with "[$HPC $Hi $Hr1 $Hr_t9]");
      [eapply decode_encode_instrW_inv|iCorrectPC a_crtcls_end' a_end|iContiguous_next Hcont_rest'' 2|..].
    iEpilogue "(HPC & Hi & Hr1 & Hr_t9)". iCombine "Hi" "Hprog_done" as "Hprog_done".
    iDestruct (big_sepM_insert _ _ r_t9 with "[$Hregs $Hr_t9]") as "Hregs";[apply lookup_delete|rewrite insert_delete !(insert_commute _ _ r_t9);auto;rewrite insert_insert].
    (* lea r_t1 offset_to_counter + length incr + length read *)
    assert ((a_move + (offset_to_counter + (length incr_instrs) + (length (read_instrs 0))))%a = Some linkc') as H_counter_offset''.
    { revert read_length H_counter_offset' Hlinkrestc' Hlinkrestc H_counter_offset incr_length. clear. intros. solve_addr. }
    destruct ai_rest' as [| ? ai_rest']; [by inversion Hlength_rest''|].
    iPrologue "Hprog".
    iApply (wp_lea_success_z _ _ _ _ _ _ _ _ _ _ _ _ _ linkc' with "[$HPC $Hi $Hr1]");
      [eapply decode_encode_instrW_inv|iCorrectPC a_crtcls_end' a_end|iContiguous_next Hcont_rest'' 3|assumption|done|..].
    iEpilogue "(HPC & Hi & Hr1)". iCombine "Hi" "Hprog_done" as "Hprog_done".
    (* crtcls *)
    iDestruct (contiguous_between_program_split with "Hprog") as
        (ai_crtcls'' ai_rest'' a_crtcls_end'') "(Hcrtcls'' & Hprog & #Hcont)".
    { epose proof (contiguous_between_incr_addr _ 4%nat _ _ _ Hcont_rest'' eq_refl).
      eapply contiguous_between_app with (a1:=[_;_;_;_]). 2: eapply Hcont_rest''.
      all: eauto. }
    iDestruct "Hcont" as %(Hcont_crtcls'' & Hcont_rest''' & Heqapp''' & Hlink''').
    assert (a_crtcls_end' <= a11)%a as Ha1_after_crtcls'.
    { eapply contiguous_between_middle_bounds'. apply Hcont_rest''. repeat constructor. }
    iApply (wp_wand with "[-]").
    iApply (crtcls_spec with "[- $HPC $Hcrtcls'' $Hpc_b $Ha_entry $Hr0 $Hregs $Hr1 $Hr2 $HnaI $Hinv_malloc]");
      [|apply Hcont_crtcls''|apply Hwb_malloc|apply Ha_entry| |done|auto|..].
    { eapply isCorrectPC_range_restrict. apply Hvpc4. split; auto.
      eapply contiguous_between_bounds. apply Hcont_rest'''. }
    { rewrite !dom_insert_L !dom_delete_L Hdom_r.
      clear. set_solver-. }
    2: { iIntros (?) "[ H | -> ]". iApply "H". iIntros (HC). congruence. }
    iNext. iIntros "(HPC & Hcrtcls'' & Hpc_b & Ha_entry & HH)".
    iDestruct "HH" as (b_cls'' e_cls'' Hbe_cls'') "(Hr1 & Hbe_cls'' & Hr0 & Hr2 & HnaI & Hregs)".
    iDestruct (big_sepL2_length with "Hprog") as %Hlength_rest'''.
    (* register map cleanup *)
    repeat (rewrite (insert_commute _ _ r_t3);[|by auto]);rewrite insert_insert. 
    repeat (rewrite (insert_commute _ _ r_t4);[|by auto]);rewrite insert_insert. 
    repeat (rewrite (insert_commute _ _ r_t6);[|by auto]);rewrite insert_insert. 
    repeat (rewrite (insert_commute _ _ r_t7);[|by auto]);rewrite insert_insert. 
    repeat (rewrite (insert_commute _ _ r_t5);[|by auto]);rewrite insert_insert. 
    
    (* FINAL CLEANUP BEFORE RETURN *)
    assert (isCorrectPC_range pc_p pc_b pc_e a_crtcls_end'' a_end) as Hvpc5. 
    { eapply isCorrectPC_range_restrict. apply Hvpc4.
      generalize (contiguous_between_bounds _ _ _ Hcont_rest''').
      revert Ha1_after_malloc Ha1_after_crtcls Ha1_after_crtcls' Hlink''' Hlink'' Hlink'. clear; solve_addr. }
    destruct ai_rest'' as [| ? ai_rest'']; [by inversion Hlength_rest'''|].
    pose proof (contiguous_between_cons_inv_first _ _ _ _ Hcont_rest''') as ->.
    (* move r_t2 r_t10 *)
    rewrite !(insert_commute _ _ r_t10);auto. 
    iDestruct (big_sepM_delete _ _ r_t10 with "Hregs") as "[Hr_t10 Hregs]";[apply lookup_insert|]. 
    destruct ai_rest'' as [| ? ai_rest'']; [by inversion Hlength_rest'''|].
    iPrologue "Hprog".
    iApply (wp_move_success_reg with "[$HPC $Hi $Hr2 $Hr_t10]");
      [eapply decode_encode_instrW_inv|iCorrectPC a_crtcls_end'' a_end|iContiguous_next Hcont_rest''' 0|..].
    iEpilogue "(HPC & Hi & Hr2 & Hr_t10)". iCombine "Hi" "Hprog_done" as "Hprog_done".
    (* move r_t10 0 *)
    destruct ai_rest'' as [| ? ai_rest'']; [by inversion Hlength_rest'''|].
    iPrologue "Hprog".
    iApply (wp_move_success_z with "[$HPC $Hi $Hr_t10]");
      [eapply decode_encode_instrW_inv|iCorrectPC a_crtcls_end'' a_end|iContiguous_next Hcont_rest''' 1|..].
    iEpilogue "(HPC & Hi & Hr_t10)". iCombine "Hi" "Hprog_done" as "Hprog_done".
    iDestruct (big_sepM_insert _ _ r_t10 with "[$Hregs $Hr_t10]") as "Hregs";[apply lookup_delete|rewrite insert_delete insert_insert]. 
    (* move r_t3 r_t11 *)
    rewrite !(insert_commute _ _ r_t11);auto. 
    iDestruct (big_sepM_delete _ _ r_t11 with "Hregs") as "[Hr_t11 Hregs]";[apply lookup_insert|].
    rewrite !(insert_commute _ _ r_t3);auto. rewrite delete_insert_ne;auto. 
    iDestruct (big_sepM_delete _ _ r_t3 with "Hregs") as "[Hr_t3 Hregs]";[apply lookup_insert|]. 
    destruct ai_rest'' as [| ? ai_rest'']; [by inversion Hlength_rest'''|].
    iPrologue "Hprog".
    iApply (wp_move_success_reg with "[$HPC $Hi $Hr_t3 $Hr_t11]");
      [eapply decode_encode_instrW_inv|iCorrectPC a_crtcls_end'' a_end|iContiguous_next Hcont_rest''' 2|..].
    iEpilogue "(HPC & Hi & Hr_t3 & Hr_t11)". iCombine "Hi" "Hprog_done" as "Hprog_done".
    (* move r_t11 0 *)
    destruct ai_rest'' as [| ? ai_rest'']; [by inversion Hlength_rest'''|].
    iPrologue "Hprog".
    iApply (wp_move_success_z with "[$HPC $Hi $Hr_t11]");
      [eapply decode_encode_instrW_inv|iCorrectPC a_crtcls_end'' a_end|iContiguous_next Hcont_rest''' 3|..].
    iEpilogue "(HPC & Hi & Hr_t11)". iCombine "Hi" "Hprog_done" as "Hprog_done".
    iDestruct (big_sepM_insert _ _ r_t3 with "[$Hregs $Hr_t3]") as "Hregs";[apply lookup_delete|rewrite insert_delete insert_insert].
    rewrite -delete_insert_ne;auto. 
    iDestruct (big_sepM_insert _ _ r_t11 with "[$Hregs $Hr_t11]") as "Hregs";[apply lookup_delete|rewrite insert_delete]. 
    rewrite insert_commute;auto. rewrite insert_insert.

    (* WE WILL NOW PREPARE THΕ JUMP *)
    iCombine "Hbe_cls'" "Hbe_cls''" as "Hbe_cls'".
    iCombine "Hbe_cls" "Hbe_cls'" as "Hbe_cls".
    iDestruct (na_inv_alloc logrel_nais _ count_clsN with "Hbe_cls") as ">#Hcls_inv".

    (* in preparation of jumping, we allocate the counter invariant *)
    iDestruct (inv_alloc countN _ (counter_inv b_cell) with "[Hb_cell]") as ">#Hcounter_inv".
    { iNext. rewrite /counter_inv. iExists _. iFrame. auto. }
    (* we also allocate a non atomic invariant for the environment table *)
    iMod (na_inv_alloc logrel_nais _ count_env
                       (pc_b ↦ₐ inr (RO,b_link,e_link,a_link) ∗ a_entry' ↦ₐ fail_cap)%I
            with "[$Ha_entry' $Hpc_b]") as "#Henv".

    (* jmp *)
    destruct ai_rest'' as [| ? ai_rest'']; [|by inversion Hlength_rest'''].
    iPrologue "Hprog".
    iApply (wp_jmp_success with "[$HPC $Hi $Hr0]");
      [apply decode_encode_instrW_inv|iCorrectPC a_crtcls_end'' a_end|..].

    (* the current state of registers is valid *)
    iAssert (interp (inr (E, b_cls, e_cls, b_cls)))%I as "#Hvalid_cls".
    { rewrite /interp fixpoint_interp1_eq. iModIntro. rewrite /enter_cond.
      iIntros (r') "". iNext. rewrite /interp_expr /=.
      iIntros "([Hr'_full #Hr'_valid] & Hregs' & HnaI)". iDestruct "Hr'_full" as %Hr'_full.
      pose proof (regmap_full_dom _ Hr'_full) as Hdom_r'.
      iSplitR; [auto|]. rewrite /interp_conf.
      
      iDestruct (na_inv_open with "Hcls_inv HnaI") as ">(>(Hcls & Hcls' & Hcls'') & Hna & Hcls_close)";
        [auto..|].

      rewrite /registers_mapsto.
      rewrite -insert_delete.
      iDestruct (big_sepM_insert with "Hregs'") as "[HPC Hregs']". by apply lookup_delete. 
      destruct (Hr'_full r_t1) as [r1v ?].
      iDestruct (big_sepM_delete _ _ r_t1 with "Hregs'") as "[Hr1 Hregs']".
        by rewrite lookup_delete_ne //.
        destruct (Hr'_full r_env) as [renvv ?].
        iDestruct (big_sepM_delete _ _ r_env with "Hregs'") as "[Hrenv Hregs']".
        by rewrite !lookup_delete_ne //.
      (* Run the closure activation code *)
      iApply (closure_activation_spec with "[- $HPC $Hr1 $Hrenv $Hcls]");
        [done| |done|..].
      { intros ? [? ?]. constructor; try split; auto. }
      rewrite updatePcPerm_cap_non_E //;[].
      iIntros "(HPC & Hr1 & Hrenv & Hcls)".
      (* close the invariant for the closure *)
      iDestruct ("Hcls_close" with "[Hcls Hcls' Hcls'' $Hna]") as ">Hna".
      { iNext. iFrame. }
      
      (* iDestruct (big_sepM_insert with "[$Hregs' $Hr1]") as "Hregs'". *)
      (*   by rewrite lookup_delete_ne // lookup_delete //. *)
      (*   rewrite -delete_insert_ne // insert_delete. *)
      destruct (Hr'_full r_t0) as [r0v Hr0v].
      iDestruct (big_sepM_delete _ _ r_t0 with "Hregs'") as "[Hr0 Hregs']".
        by rewrite !lookup_delete_ne // lookup_delete_ne //.
        
      iApply (incr_spec with "[$HPC $Hr0 $Hrenv $Hregs' $Hna $Hincr Hr1]");
        [|apply Hcont_incr|auto|..].
      { eapply isCorrectPC_range_restrict; [apply Hvpc_counter|]. split;[clear;solve_addr|].
        apply contiguous_between_bounds in Hcont_restc. apply Hcont_restc. }
      { rewrite !dom_delete_L Hdom_r'. clear. set_solver. }
      { iSplitL;[eauto|]. iSplit. 
        - iExists _. iFrame "#".
        - iSplit; [unshelve iSpecialize ("Hr'_valid" $! r_t0 _); [done|]|].
          rewrite /RegLocate Hr0v. iFrame "Hr'_valid".
          iApply big_sepM_forall. iIntros (reg w Hlook).
          assert (reg ≠ r_t0);[intro Hcontr;subst;rewrite lookup_delete in Hlook;inversion Hlook|rewrite lookup_delete_ne in Hlook;auto]. 
          assert (reg ≠ r_env);[intro Hcontr;subst;rewrite lookup_delete in Hlook;inversion Hlook|rewrite lookup_delete_ne in Hlook;auto]. 
          assert (reg ≠ r_t1);[intro Hcontr;subst;rewrite lookup_delete in Hlook;inversion Hlook|rewrite lookup_delete_ne in Hlook;auto]. 
          assert (reg ≠ PC);[intro Hcontr;subst;rewrite lookup_delete in Hlook;inversion Hlook|rewrite lookup_delete_ne in Hlook;auto]. 
          iSpecialize ("Hr'_valid" $! reg). rewrite /RegLocate Hlook. iApply "Hr'_valid";auto.
      }
      { iNext. iIntros (?) "HH". iIntros (->). iApply "HH". eauto. }
    }
    

    
    
    unshelve iPoseProof ("Hr_valid" $! r_t0 _) as "#Hr0_valid". done.
    rewrite /(RegLocate _ r_t0) Hr0.

    iAssert (((fixpoint interp1) W2) r0) as "#Hr0_valid2".
    { iApply (interp_monotone with "[] Hr0_valid"). iPureIntro. apply related_sts_pub_world_fresh_loc; auto. }
    set r' : gmap RegName Word :=
      <[r_t0  := r0]>
      (<[r_t1 := inr (E, Global, b_cls, e_cls, b_cls)]>
       (create_gmap_default (list_difference all_registers [r_t0;r_t1]) (inl 0%Z))).

    (* either we fail, or we use the continuation in rt0 *)
    iDestruct (jmp_or_fail_spec with "Hr0_valid2") as "Hcont".
    destruct (decide (isCorrectPC (updatePcPerm r0))). 
    2 : { iEpilogue "(HPC & Hi & Hr0)". iApply "Hcont". iFrame "HPC". iIntros (Hcontr);done. }
    iDestruct "Hcont" as (p g b e a3 Heq) "#Hcont". 
    simplify_eq. 

    iAssert (future_world g W2 W2) as "#Hfuture".
    { destruct g; iPureIntro. apply related_sts_priv_refl_world. apply related_sts_pub_refl_world. }
    iAssert (∀ r, ▷ ((interp_expr interp r) W2 (updatePcPerm (inr (p, g, b, e, a3)))))%I with "[Hcont]" as "Hcont'".
    { iIntros. iApply "Hcont". iApply "Hfuture". }

    (* prepare the continuation *)
    iEpilogue "(HPC & Hi & Hr0)". iCombine "Hi" "Hprog_done" as "Hprog_done".

    (* Put the registers back in the map *)
    iDestruct (big_sepM_insert with "[$Hregs $Hr2]") as "Hregs".
    { repeat (rewrite lookup_insert_ne //;[]). rewrite lookup_delete //. }
    iDestruct (big_sepM_insert with "[$Hregs $Hr1]") as "Hregs".
    { repeat (rewrite lookup_insert_ne //;[]). rewrite lookup_delete_ne //.
      repeat (rewrite lookup_insert_ne //;[]). apply lookup_delete. }
    iDestruct (big_sepM_insert with "[$Hregs $Hr0]") as "Hregs".
    { repeat (rewrite lookup_insert_ne //;[]). rewrite lookup_delete_ne //.
      repeat (rewrite lookup_insert_ne //;[]). rewrite lookup_delete_ne // lookup_delete //. }
    iDestruct (big_sepM_insert with "[$Hregs $HPC]") as "Hregs".
    { repeat (rewrite lookup_insert_ne //;[]). rewrite lookup_delete_ne //.
      repeat (rewrite lookup_insert_ne //;[]). do 2 rewrite lookup_delete_ne //.
      apply lookup_delete. }
    repeat (rewrite -(delete_insert_ne _ r_t2) //;[]). rewrite insert_delete.
    repeat (rewrite -(delete_insert_ne _ r_t1) //;[]). rewrite insert_delete.
    repeat (rewrite -(delete_insert_ne _ r_t0) //;[]). rewrite insert_delete.
    repeat (rewrite -(delete_insert_ne _ PC) //;[]). rewrite insert_delete.
    rewrite -(insert_insert _ PC _ (inl 0%Z)).
    match goal with |- context [ ([∗ map] k↦y ∈ <[PC:=_]> ?r, _)%I ] => set r'' := r end.
    iAssert (full_map r'') as %Hr''_full.
    { rewrite /full_map. iIntros (rr). iPureIntro. rewrite elem_of_gmap_dom /r''.
      rewrite 12!dom_insert_L regmap_full_dom //.
      generalize (all_registers_s_correct rr). clear; set_solver. }
    assert (related_sts_pub_world W W2) as Hfuture2.
    { apply related_sts_pub_world_fresh_loc; auto. }
    iSpecialize ("Hcont'" $! r'' with "[Hsts Hr Hregs HnaI]").
    { iFrame.
      iDestruct (region_monotone with "[] [] Hr") as "$"; auto.
      rewrite /interp_reg. iSplit; [iPureIntro; apply Hr''_full|].
      iIntros (rr Hrr).
      assert (is_Some (r'' !! rr)) as [rrv Hrrv] by apply Hr''_full.
      rewrite /RegLocate Hrrv. rewrite /r'' in Hrrv.
      rewrite lookup_insert_Some in Hrrv |- *. move=> [ [? ?] | [_ Hrrv] ].
      { subst rr. by exfalso. }
      rewrite lookup_insert_Some in Hrrv |- *. move=> [ [? ?] | [? Hrrv] ].
      { subst rr rrv. iApply "Hr0_valid2". }
      rewrite lookup_insert_Some in Hrrv |- *. move=> [ [? ?] | [? Hrrv] ].
      { subst rr rrv. iApply "Hvalid_cls". }
      repeat (
        rewrite lookup_insert_Some in Hrrv |- *; move=> [ [? ?] | [? Hrrv] ];
        [subst; by rewrite (fixpoint_interp1_eq W2 (inl 0%Z)) |]
      ).
      unshelve iSpecialize ("Hr_valid" $! rr _). by auto. rewrite Hrrv.
      iApply (interp_monotone with "[] Hr_valid"). auto. }
    (* apply the continuation *)
    iDestruct "Hcont'" as "[_ Hcallback_now]".
    iApply wp_wand_l. iFrame "Hcallback_now".
    iIntros (v) "Hφ". iIntros (Hne).
    iDestruct ("Hφ" $! Hne) as (r0 W') "(Hfull & Hregs & #Hrelated & Hna & Hsts & Hr)".
    iExists r0,W'. iFrame.
    iDestruct "Hrelated" as %Hrelated. iPureIntro.
    eapply related_sts_pub_priv_trans_world;[|eauto].
    apply related_sts_pub_world_fresh_loc; auto.
  Qed.

End awkward_example_preamble.
