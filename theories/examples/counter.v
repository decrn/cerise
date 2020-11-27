From iris.algebra Require Import frac.
From iris.proofmode Require Import tactics.
Require Import Eqdep_dec List.
From cap_machine Require Import rules logrel macros_helpers macros fundamental.

Section counter.
  Context {Σ:gFunctors} {memg:memG Σ} {regg:regG Σ}
          {nainv: logrel_na_invs Σ}
          `{MP: MachineParameters}.

  (* ----------------------------------------------------------------------------- *)
  Definition r_ret := r_t31.
  

  Definition incr_instrs :=
    [load_r r_t1 r_env;
    add_r_z r_t1 r_t1 1;
    store_r r_env r_t1;
    move_z r_env 0;
    jmp r_t0]. 

  Definition read_instrs f_a :=
    [load_r r_ret r_env;
    lt_r_z r_t4 r_ret 0] ++
    assert_r_z_instrs f_a r_t4 0 ++
    [move_z r_env 0;
    jmp r_t0]. 

  Definition reset_instrs :=
    [store_z r_env 0;
    move_z r_env 0;
    move_z r_t1 0;
    jmp r_t0].

  Definition incr a :=
    ([∗ list] a_i;w ∈ a;incr_instrs, a_i ↦ₐ w)%I.
  Definition read a f_a :=
    ([∗ list] a_i;w ∈ a;read_instrs f_a, a_i ↦ₐ w)%I. 
  Definition reset a :=
    ([∗ list] a_i;w ∈ a;reset_instrs, a_i ↦ₐ w)%I. 

  Definition pos_word (w : Word) : iProp Σ :=
    (match w with
    | inl z => ⌜(0 ≤ z)%Z⌝
    | inr _ => False
    end)%I. 
  Definition counter_inv d : iProp Σ :=
    (∃ w, d ↦ₐ w ∗ pos_word w)%I.
  
  Instance pos_word_Timeless : Timeless (pos_word w).
  Proof. intros d. destruct d; apply _. Qed. 
  Instance pos_word_Persistent : Persistent (pos_word w).
  Proof. intros w. destruct w; apply _. Qed.


  (* ----------------------------------- INCR -------------------------------------- *)
  
  Lemma incr_spec pc_p pc_b pc_e (* PC *)
        wret (* return cap *)
        incr_addrs (* program addresses *)
        d d' (* dynamically allocated memory given by preamble *)
        a_first a_last (* special adresses *)
        rmap (* registers *)
        ι1 (* invariant names *) :

    (* PC assumptions *)
    isCorrectPC_range pc_p pc_b pc_e a_first a_last ->

    (* Program adresses assumptions *)
    contiguous_between incr_addrs a_first a_last ->
    
    (* malloc'ed memory assumption for the counter *)
    (d + 1)%a = Some d' ->

    (* footprint of the register map *)
    dom (gset RegName) rmap = all_registers_s ∖ {[PC;r_t0;r_env;r_t1]} →
    
    {{{ PC ↦ᵣ inr (pc_p,pc_b,pc_e,a_first)
      ∗ r_t0 ↦ᵣ wret
      ∗ r_env ↦ᵣ inr (RWX,d,d',d)
      ∗ (∃ w, r_t1 ↦ᵣ w)
      ∗ ([∗ map] r_i↦w_i ∈ rmap, r_i ↦ᵣ w_i)
      (* invariant for d *)
      ∗ (∃ ι, inv ι (counter_inv d))
      (* token which states all non atomic invariants are closed *)
      ∗ na_own logrel_nais ⊤
      (* callback validity *)
      ∗ interp wret
      (* trusted code *)
      ∗ na_inv logrel_nais ι1 (incr incr_addrs)
      (* the remaining registers are all valid *)
      ∗ ([∗ map] _↦w_i ∈ rmap, interp w_i)
    }}}
      Seq (Instr Executable)
      {{{ v, RET v; ⌜v = HaltedV⌝ →
                    ∃ r, full_map r ∧ registers_mapsto r
                         ∗ na_own logrel_nais ⊤ }}}.
  Proof.
    iIntros (Hvpc Hcont Hd Hdom φ) "(HPC & Hr_t0 & Hr_env & Hr_t1 & Hregs & Hinv & Hown & #Hcallback & #Hincr & #Hregs_val) Hφ". 
    iDestruct "Hinv" as (ι) "#Hinv".
    iMod (na_inv_acc with "Hincr Hown") as "(>Hprog & Hown & Hcls)";auto.
    iDestruct (big_sepL2_length with "Hprog") as %Hprog_length.
    destruct_list incr_addrs.
    apply contiguous_between_cons_inv_first in Hcont as Heq. subst a. 
    (* Get a general purpose register *)
    iDestruct "Hr_t1" as (w1) "Hr_t1". 
    (* load r_t1 r_env *)
    iPrologue "Hprog". rewrite /counter_inv. 
    iInv ι as (w) "[>Hd >#Hcond]" "Hcls'".
    iAssert (⌜(d =? a_first)%a = false⌝)%I as %Hfalse.
    { destruct (d =? a_first)%a eqn:Heq;auto. apply Z.eqb_eq,z_of_eq in Heq as ->. iDestruct (mapsto_valid_2 with "Hi Hd") as %?. done. }
    iApply (wp_load_success with "[$HPC $Hi $Hr_t1 $Hr_env Hd]");
      [apply decode_encode_instrW_inv|iCorrectPC a_first a_last| |iContiguous_next Hcont 0|..]. 
    { split;auto. simpl. apply andb_true_iff. rewrite Z.leb_le Z.ltb_lt. revert Hd;clear;solve_addr. }
    { rewrite Hfalse. iFrame. }
    rewrite Hfalse. 
    iNext. iIntros "(HPC & Hr_t1 & Ha_first & Hr_env & Hd)".
    iMod ("Hcls'" with "[Hd]") as "_". 
    { iNext. iExists w. iFrame "∗ #". }
    iModIntro. iApply wp_pure_step_later;auto;iNext.
    (* add r_t1 r_t1 1 *)
    destruct w;[|done]. 
    iPrologue "Hprog". 
    iApply (wp_add_sub_lt_success_dst_z with "[$HPC $Hi $Hr_t1]");
      [apply decode_encode_instrW_inv|eauto|iContiguous_next Hcont 1|iCorrectPC a_first a_last|]. 
    iEpilogue "(HPC & Hi & Hr_t1) /=". iCombine "Hi Ha_first" as "Hprog_done". 
    (* store r_env r_t1 *)
    iPrologue "Hprog".
    iInv ι as (w) "[>Hd _]" "Hcls'". 
    iApply (wp_store_success_reg with "[$HPC $Hi $Hr_t1 $Hr_env $Hd]");
      [apply decode_encode_instrW_inv|iCorrectPC a_first a_last|iContiguous_next Hcont 2|..]; auto.
    { simpl. apply andb_true_iff. rewrite Z.leb_le Z.ltb_lt. revert Hd;clear;solve_addr. }
    iNext. iIntros "(HPC & Hi & Hr_t1 & Hr_env & Hd)".
    iMod ("Hcls'" with "[Hd]") as "_". 
    { iNext. iExists (inl (z + 1)%Z). iFrame. iDestruct "Hcond" as %Hcond. iPureIntro. revert Hcond;clear;lia. }
    iModIntro. iApply wp_pure_step_later;auto;iNext. iCombine "Hi Hprog_done" as "Hprog_done". 
    (* move r_env 0 *)
    iPrologue "Hprog". 
    iApply (wp_move_success_z with "[$HPC $Hi $Hr_env]");
      [apply decode_encode_instrW_inv|iCorrectPC a_first a_last|iContiguous_next Hcont 3|]. 
    iEpilogue "(HPC & Hi & Hr_env)". iCombine "Hi Hprog_done" as "Hprog_done".
    (* jmp r_t0 *)
    iPrologue "Hprog". 
    apply (contiguous_between_last _ _ _ a3) in Hcont as Hlast;auto. 
    iApply (wp_jmp_success with "[$HPC $Hi $Hr_t0]");
      [apply decode_encode_instrW_inv|iCorrectPC a_first a_last|]. 
    iDestruct (jmp_or_fail_spec with "Hcallback") as "Hcallback_now". 
    (* close program invariant *)
    
    (* reassemble registers *)
    iDestruct (big_sepM_insert _ _ r_t1 with "[$Hregs $Hr_t1]") as "Hregs".
    { apply elem_of_gmap_dom_none. rewrite Hdom. clear; set_solver. }
    iDestruct (big_sepM_insert _ _ r_env with "[$Hregs $Hr_env]") as "Hregs".
    { rewrite !lookup_insert_ne;auto. apply elem_of_gmap_dom_none. rewrite Hdom. clear; set_solver. }
    (* now we are ready to apply the jump or fail pattern *)
    destruct (decide (isCorrectPC (updatePcPerm wret))). 
    - iDestruct "Hcallback_now" as (p b e a Heq) "Hcallback'". 
      simplify_eq.
      iEpilogue "(HPC & Hi & Hr_t0)".
      iMod ("Hcls" with "[Hprog_done Hi $Hown]") as "Hown".
      { iNext. iFrame. iDestruct "Hprog_done" as "($&$&$&$&$)". done. }
      iDestruct (big_sepM_insert _ _ r_t0 with "[$Hregs $Hr_t0]") as "Hregs".
      { rewrite !lookup_insert_ne;auto. apply elem_of_gmap_dom_none. rewrite Hdom. clear; set_solver. }
      set (regs' := <[PC:=inl 0%Z]> (<[r_t0:=inr (p, b, e, a)]> (<[r_env:=inl 0%Z]> (<[r_t1:=inl (z + 1)%Z]> (delete r_t1 rmap))))). 
      iDestruct ("Hcallback'" $! regs' with "[Hregs $Hown HPC]") as "[_ Hexpr]". 
      { rewrite /registers_mapsto /regs'.
        iSplit.
        - iClear "Hcallback' Hregs HPC". rewrite /interp_reg /=. iSplit.
          + iPureIntro.
            intros r'. simpl.
            consider_next_reg r' PC. consider_next_reg r' r_t0. consider_next_reg r' r_env. rewrite insert_delete.
            consider_next_reg r' r_t1. 
            apply elem_of_gmap_dom. rewrite Hdom. assert (r' ∈ all_registers_s) as Hin;[apply all_registers_s_correct|].
            revert n n0 n1 n2 Hin;clear. set_solver.
          + iIntros (r Hne).
            rewrite /RegLocate.
            consider_next_reg r PC. done. consider_next_reg r r_t0. consider_next_reg r r_env. rewrite !fixpoint_interp1_eq. done.
            consider_next_reg r r_t1. rewrite !fixpoint_interp1_eq. done. 
            rewrite lookup_delete_ne;auto. destruct (rmap !! r) eqn:Hsome;rewrite Hsome;[|rewrite !fixpoint_interp1_eq;done].
            iDestruct (big_sepM_delete _ _ r with "Hregs_val") as "[Hr _]";[eauto|]. iFrame "Hr".
        - rewrite insert_insert. iApply (big_sepM_delete _ _ PC);[apply lookup_insert|]. iFrame.
          rewrite delete_insert. rewrite insert_delete. iFrame.
          repeat (rewrite lookup_insert_ne;auto). rewrite lookup_delete_ne;auto.
          apply elem_of_gmap_dom_none. rewrite Hdom. clear;set_solver.
      }
      rewrite /interp_conf. iApply wp_wand_l. iFrame "Hexpr". 
      iIntros (v). iApply "Hφ".
    - iEpilogue "(HPC & Hi & Hr_t0)".
      iApply "Hcallback_now". iFrame.
      iApply "Hφ". iIntros (Hcontr); inversion Hcontr. 
  Qed.


  (* ----------------------------------- READ -------------------------------------- *)

  Lemma read_spec pc_p pc_b pc_e (* PC *)
        wret (* return cap *)
        read_addrs (* program addresses *)
        d d' (* dynamically allocated memory given by preamble *)
        a_first a_last (* special adresses *)
        f_a b_link e_link a_link a_entry fail_cap (* linking table variables *)
        rmap (* registers *)
        ι1 ι2 (* invariant names *) :

    (* PC assumptions *)
    isCorrectPC_range pc_p pc_b pc_e a_first a_last ->

    (* Program adresses assumptions *)
    contiguous_between read_addrs a_first a_last ->
    
    (* Linking table assumptions *)
    withinBounds (RW, b_link, e_link, a_entry) = true →
    (a_link + f_a)%a = Some a_entry ->

    (* malloc'ed memory assumption for the counter *)
    (d + 1)%a = Some d' ->

    (* footprint of the register map *)
    dom (gset RegName) rmap = all_registers_s ∖ {[PC;r_t0;r_env;r_t1]} →

    (* The two invariants have different names *)
    (up_close (B:=coPset) ι2 ## ↑ι1) ->
    
    {{{ PC ↦ᵣ inr (pc_p,pc_b,pc_e,a_first)
      ∗ r_t0 ↦ᵣ wret
      ∗ r_env ↦ᵣ inr (RWX,d,d',d)
      ∗ (∃ w, r_t1 ↦ᵣ w)
      ∗ ([∗ map] r_i↦w_i ∈ rmap, r_i ↦ᵣ w_i)
      (* invariant for d *)
      ∗ (∃ ι, inv ι (counter_inv d))
      (* token which states all non atomic invariants are closed *)
      ∗ na_own logrel_nais ⊤
      (* callback validity *)
      ∗ interp wret
      (* trusted code *)
      ∗ na_inv logrel_nais ι1 (read read_addrs f_a)
      (* linking table *)
      ∗ na_inv logrel_nais ι2 (pc_b ↦ₐ inr (RO,b_link,e_link,a_link) ∗ a_entry ↦ₐ fail_cap)
      (* the remaining registers are all valid *)
      ∗ ([∗ map] _↦w_i ∈ rmap, interp w_i)
    }}}
      Seq (Instr Executable)
      {{{ v, RET v; ⌜v = HaltedV⌝ →
                    ∃ r, full_map r ∧ registers_mapsto r
                         ∗ na_own logrel_nais ⊤ }}}.
  Proof.
    iIntros (Hvpc Hcont Hwb Hlink Hd Hdom Hclose φ) "(HPC & Hr_t0 & Hr_env & Hr_t1 & Hregs & Hinv & Hown & #Hcallback & #Hread & #Hlink & #Hregs_val) Hφ". 
    iDestruct "Hinv" as (ι) "#Hinv".
    iMod (na_inv_acc with "Hread Hown") as "(>Hprog & Hown & Hcls)";auto.
    iDestruct (big_sepL2_length with "Hprog") as %Hprog_length.
    destruct read_addrs as [|a read_addrs];[inversion Hprog_length|]. 
    apply contiguous_between_cons_inv_first in Hcont as Heq. subst a.
    (* Get a general purpose register *)
    assert (is_Some (rmap !! r_ret)) as [w' Hrtret].
    { apply elem_of_gmap_dom. rewrite Hdom. apply elem_of_difference.
      split;[apply all_registers_s_correct|clear;set_solver]. }
    assert (is_Some (rmap !! r_t2)) as [w2 Hrt2].
    { apply elem_of_gmap_dom. rewrite Hdom. apply elem_of_difference.
      split;[apply all_registers_s_correct|clear;set_solver]. }
    assert (is_Some (rmap !! r_t3)) as [w3 Hrt3].
    { apply elem_of_gmap_dom. rewrite Hdom. apply elem_of_difference.
      split;[apply all_registers_s_correct|clear;set_solver]. }
    assert (is_Some (rmap !! r_t4)) as [w4 Hrt4].
    { apply elem_of_gmap_dom. rewrite Hdom. apply elem_of_difference.
      split;[apply all_registers_s_correct|clear;set_solver]. }
    iDestruct (big_sepM_delete _ _ r_ret with "Hregs") as "[Hr_ret Hregs]";[eauto|].
    iDestruct "Hr_t1" as (w1) "Hr_t1". 
    iDestruct (big_sepM_delete _ _ r_t2 with "Hregs") as "[Hr_t2 Hregs]";[rewrite !lookup_delete_ne;eauto|].
    iDestruct (big_sepM_delete _ _ r_t3 with "Hregs") as "[Hr_t3 Hregs]";[rewrite !lookup_delete_ne;eauto|].
    iDestruct (big_sepM_delete _ _ r_t4 with "Hregs") as "[Hr_t4 Hregs]";[rewrite !lookup_delete_ne;eauto|]. 
    (* load r_ret r_env *)
    let a := fresh "a" in destruct read_addrs as [|a read_addrs];[inversion Hprog_length|]. 
    iPrologue "Hprog". 
    iInv ι as (w) "[>Hd >#Hcond]" "Hcls'".
    iAssert (⌜(d =? a_first)%a = false⌝)%I as %Hfalse.
    { destruct (d =? a_first)%a eqn:Heq;auto. apply Z.eqb_eq,z_of_eq in Heq as ->. iDestruct (mapsto_valid_2 with "Hi Hd") as %?. done. }
    iApply (wp_load_success with "[$HPC $Hi $Hr_ret $Hr_env Hd]");
      [apply decode_encode_instrW_inv|iCorrectPC a_first a_last| |iContiguous_next Hcont 0|..]. 
    { split;auto. simpl. apply andb_true_iff. rewrite Z.leb_le Z.ltb_lt. revert Hd;clear;solve_addr. }
    { rewrite Hfalse. iFrame. }
    rewrite Hfalse. 
    iNext. iIntros "(HPC & Hr_ret & Ha_first & Hr_env & Hd)".
    iMod ("Hcls'" with "[Hd]") as "_". 
    { iNext. iExists w. iFrame "∗ #". }
    iModIntro. iApply wp_pure_step_later;auto;iNext.
    (* Lt r_t4 r_ret 0 *)
    let a := fresh "a" in destruct read_addrs as [|a read_addrs];[inversion Hprog_length|]. 
    destruct w;[|done]. 
    iPrologue "Hprog". 
    iApply (wp_add_sub_lt_success_r_z with "[$HPC $Hi $Hr_t4 $Hr_ret]");
      [apply decode_encode_instrW_inv|eauto|iContiguous_next Hcont 1|iCorrectPC a_first a_last|]. 
    iEpilogue "(HPC & Hi & Hr_ret & Hr_t4)". iCombine "Hi" "Ha_first" as "Hprog_done". 
    (* assert r_t4 0 *)
    assert (contiguous_between (a0 :: read_addrs) a0 a_last) as Hcont'.
    { apply contiguous_between_cons_inv in Hcont as [Heq [? [? Hcont] ] ];
      apply contiguous_between_cons_inv_first in Hcont as ?; subst.
      apply contiguous_between_cons_inv in Hcont as [? [? [? Hcont] ] ].
      apply contiguous_between_cons_inv_first in Hcont as ?; subst. auto. }
    iDestruct (contiguous_between_program_split with "Hprog") as (assert_prog rest link)
                                                                   "(Hassert & Hprog & #Hcont)";[apply Hcont'|].
    iDestruct "Hcont" as %(Hcont_assert & Hcont_rest & Heqapp & Hlinkrest).
    iDestruct "Hcond" as %Hpos. 
    iMod (na_inv_acc with "Hlink Hown") as "[ [>Hpc_b >Ha_entry] [Hna Hcls'] ]";[revert Hclose;clear;solve_ndisj..|].
    iApply (assert_r_z_success with "[-]");[..|iFrame "HPC Hpc_b Ha_entry Hassert"];
      [|apply Hcont_assert|auto|auto|auto|..].
    { eapply isCorrectPC_range_restrict;[eauto|]. apply contiguous_between_bounds in Hcont_rest. split;auto.
      assert (a_first + 1 = Some a)%a;[iContiguous_next Hcont 0|]. assert (a + 1 = Some a0)%a;[iContiguous_next Hcont 1|].
      revert H H0;clear;solve_addr. }
    iSplitL "Hr_t4".
    { (* we use the positive condition of the invariant to assert that the value in r_t4 is 0 *)
      simpl. assert ((z <? 0)%Z = false) as ->;[|iFrame]. apply Z.ltb_ge. auto. }
    iSplitL "Hr_t1";[eauto|].
    iSplitL "Hr_t2";[eauto|].
    iSplitL "Hr_t3";[eauto|]. 
    iNext. iIntros "(Hr_t1 & Hr_t2 & Hr_t3 & Hr_t4 & HPC & Hassert & Hb & Ha_entry)". 
    iMod ("Hcls'" with "[$Ha_entry $Hb $Hna]") as "Hown". iCombine "Hassert" "Hprog_done" as "Hprog_done". 
    (* prepare the rest of the program *)
    iDestruct (big_sepL2_length with "Hprog") as %Hrest_length. 
    let a := fresh "a" in destruct rest as [|a rest];[inversion Hrest_length|].
    let a := fresh "a" in destruct rest as [|a rest];[inversion Hrest_length|].
    assert (isCorrectPC_range pc_p pc_b pc_e link a_last) as Hvpc'.
    { eapply isCorrectPC_range_restrict;[eauto|]. split;[|clear;solve_addr].
      apply contiguous_between_bounds in Hcont_assert.
      assert (a_first + 1 = Some a)%a;[iContiguous_next Hcont 0|]. assert (a + 1 = Some a0)%a;[iContiguous_next Hcont 1|].
      revert H H0 Hcont_assert;clear;solve_addr. }
    apply contiguous_between_cons_inv_first in Hcont_rest as ?; subst.
    (* move r_env 0 *)
    iPrologue "Hprog". 
    iApply (wp_move_success_z with "[$HPC $Hi $Hr_env]");
      [apply decode_encode_instrW_inv|iCorrectPC link a_last|iContiguous_next Hcont_rest 0|]. 
    iEpilogue "(HPC & Hi & Hr_env)". iCombine "Hi" "Hprog_done" as "Hprog_done". 
    (* jmp r_t0 *)
    iPrologue "Hprog". 
    iApply (wp_jmp_success with "[$HPC $Hi $Hr_t0]");
      [apply decode_encode_instrW_inv|iCorrectPC link a_last|]. 

    (* We now want to apply the jump or fail pattern *)
    iDestruct (jmp_or_fail_spec with "Hcallback") as "Hcallback_now". 
    
    (* reassemble registers *)
    iDestruct (big_sepM_insert _ _ r_t4 with "[$Hregs $Hr_t4]") as "Hregs";[apply lookup_delete|rewrite insert_delete]. 
    iDestruct (big_sepM_insert _ _ r_t3 with "[$Hregs $Hr_t3]") as "Hregs".
    { rewrite !lookup_insert_ne;auto. apply lookup_delete. }
    iDestruct (big_sepM_insert _ _ r_t2 with "[$Hregs $Hr_t2]") as "Hregs".
    { rewrite !lookup_insert_ne;auto. rewrite lookup_delete_ne;auto. apply lookup_delete. }
    iDestruct (big_sepM_insert _ _ r_t1 with "[$Hregs $Hr_t1]") as "Hregs".
    { rewrite !lookup_insert_ne;auto. repeat (rewrite lookup_delete_ne;[|by auto]). apply elem_of_gmap_dom_none. rewrite Hdom. clear; set_solver. }
    iDestruct (big_sepM_insert _ _ r_ret with "[$Hregs $Hr_ret]") as "Hregs".
    { rewrite !lookup_insert_ne;auto. repeat (rewrite lookup_delete_ne;[|by auto]). apply lookup_delete. }
    iDestruct (big_sepM_insert _ _ r_env with "[$Hregs $Hr_env]") as "Hregs".
    { rewrite !lookup_insert_ne;auto. rewrite !lookup_delete_ne;auto. apply elem_of_gmap_dom_none. rewrite Hdom. clear; set_solver. }
    repeat (repeat (rewrite -delete_insert_ne;[|by auto]);rewrite insert_delete). 
    
    (* now we are ready to apply the jump or fail pattern *)
    destruct (decide (isCorrectPC (updatePcPerm wret))). 
    - iDestruct "Hcallback_now" as (p b e a' Heq) "Hcallback'". 
      simplify_eq.
      iEpilogue "(HPC & Hi & Hr_t0)".
      iMod ("Hcls" with "[Hprog_done Hi $Hown]") as "Hown".
      { iNext. rewrite Heqapp. iFrame. iDestruct "Hprog_done" as "($&Hassert&$&$)". iFrame. destruct rest; inversion Hrest_length. done. }
      iDestruct (big_sepM_insert _ _ r_t0 with "[$Hregs $Hr_t0]") as "Hregs".
      { rewrite !lookup_insert_ne;auto. apply elem_of_gmap_dom_none. rewrite Hdom. clear; set_solver. }
      set (regs' := <[PC:=inl 0%Z]> (<[r_t0:=inr (p, b, e, a')]>
                    (<[r_env:=inl 0%Z]> (<[r_ret:=inl z]> (<[r_t1:=inl 0%Z]> (<[r_t2:=inl 0%Z]> (<[r_t3:=inl 0%Z]> (<[r_t4:=inl 0%Z]> rmap)))))))). 
      iDestruct ("Hcallback'" $! regs' with "[Hregs $Hown HPC]") as "[_ Hexpr]". 
      { rewrite /registers_mapsto /regs'.
        iSplit.
        - iClear "Hcallback' Hregs HPC". rewrite /interp_reg /=. iSplit.
          + iPureIntro.
            intros r'. simpl.
            consider_next_reg r' PC. consider_next_reg r' r_t0. consider_next_reg r' r_env.
            consider_next_reg r' r_ret. consider_next_reg r' r_t1. consider_next_reg r' r_t2.
            consider_next_reg r' r_t3. consider_next_reg r' r_t4.
            apply elem_of_gmap_dom. rewrite Hdom. assert (r' ∈ all_registers_s) as Hin;[apply all_registers_s_correct|].
            revert n n0 n1 n2 n3 n4 n5 n6 Hin;clear. set_solver.
          + iIntros (r' Hne).
            rewrite /RegLocate.
            consider_next_reg r' PC. done. consider_next_reg r' r_t0. consider_next_reg r' r_env. rewrite !fixpoint_interp1_eq. done.
            consider_next_reg r' r_ret. rewrite !fixpoint_interp1_eq. done. consider_next_reg r' r_t1.
            rewrite !fixpoint_interp1_eq. done. consider_next_reg r' r_t2. rewrite !fixpoint_interp1_eq. done.
            consider_next_reg r' r_t3.  rewrite !fixpoint_interp1_eq. done. consider_next_reg r' r_t4. rewrite !fixpoint_interp1_eq. done.
            destruct (rmap !! r') eqn:Hsome;rewrite Hsome;[|rewrite !fixpoint_interp1_eq;done].
            iDestruct (big_sepM_delete _ _ r' with "Hregs_val") as "[Hr _]";[eauto|]. iFrame "Hr".
        - rewrite insert_insert. iApply (big_sepM_delete _ _ PC);[apply lookup_insert|]. iFrame.
          rewrite delete_insert. iFrame.
          repeat (rewrite lookup_insert_ne;auto). 
          apply elem_of_gmap_dom_none. rewrite Hdom. clear;set_solver.
      }
      rewrite /interp_conf. iApply wp_wand_l. iFrame "Hexpr". 
      iIntros (v). iApply "Hφ".
    - iEpilogue "(HPC & Hi & Hr_t0)".
      iApply "Hcallback_now". iFrame.
      iApply "Hφ". iIntros (Hcontr); inversion Hcontr. 
  Qed.


  (* ----------------------------------- RESET -------------------------------------- *)
  
  Lemma reset_spec pc_p pc_b pc_e (* PC *)
        wret (* return cap *)
        reset_addrs (* program addresses *)
        d d' (* dynamically allocated memory given by preamble *)
        a_first a_last (* special adresses *)
        rmap (* registers *)
        ι1 (* invariant names *) :

    (* PC assumptions *)
    isCorrectPC_range pc_p pc_b pc_e a_first a_last ->

    (* Program adresses assumptions *)
    contiguous_between reset_addrs a_first a_last ->
    
    (* malloc'ed memory assumption for the counter *)
    (d + 1)%a = Some d' ->

    (* footprint of the register map *)
    dom (gset RegName) rmap = all_registers_s ∖ {[PC;r_t0;r_env;r_t1]} →
    
    {{{ PC ↦ᵣ inr (pc_p,pc_b,pc_e,a_first)
      ∗ r_t0 ↦ᵣ wret
      ∗ r_env ↦ᵣ inr (RWX,d,d',d)
      ∗ (∃ w, r_t1 ↦ᵣ w)
      ∗ ([∗ map] r_i↦w_i ∈ rmap, r_i ↦ᵣ w_i)
      (* invariant for d *)
      ∗ (∃ ι, inv ι (counter_inv d))
      (* token which states all non atomic invariants are closed *)
      ∗ na_own logrel_nais ⊤
      (* callback validity *)
      ∗ interp wret
      (* trusted code *)
      ∗ na_inv logrel_nais ι1 (reset reset_addrs)
      (* the remaining registers are all valid *)
      ∗ ([∗ map] _↦w_i ∈ rmap, interp w_i)
    }}}
      Seq (Instr Executable)
      {{{ v, RET v; ⌜v = HaltedV⌝ →
                    ∃ r, full_map r ∧ registers_mapsto r
                         ∗ na_own logrel_nais ⊤ }}}.
  Proof.
    iIntros (Hvpc Hcont Hd Hdom φ) "(HPC & Hr_t0 & Hr_env & Hr_t1 & Hregs & Hinv & Hown & #Hcallback & #Hreset & #Hregs_val) Hφ". 
    iDestruct "Hinv" as (ι) "#Hinv".
    iMod (na_inv_acc with "Hreset Hown") as "(>Hprog & Hown & Hcls)";auto.
    iDestruct (big_sepL2_length with "Hprog") as %Hprog_length.
    destruct_list reset_addrs.
    apply contiguous_between_cons_inv_first in Hcont as Heq. subst a. 
    (* store r_env 0 *)
    iPrologue "Hprog". 
    iInv ι as (w) "[>Hd _]" "Hcls'". 
    iApply (wp_store_success_z with "[$HPC $Hi $Hr_env $Hd]");
      [apply decode_encode_instrW_inv|iCorrectPC a_first a_last|iContiguous_next Hcont 0|..]; auto.
    { simpl. apply andb_true_iff. rewrite Z.leb_le Z.ltb_lt. revert Hd;clear;solve_addr. }
    iNext. iIntros "(HPC & Hprog_done & Hr_env & Hd)".
    iMod ("Hcls'" with "[Hd]") as "_". 
    { iNext. iExists _;iFrame. auto. }
    iModIntro. iApply wp_pure_step_later;auto;iNext.
    (* move r_env 0 *)
    iPrologue "Hprog". 
    iApply (wp_move_success_z with "[$HPC $Hi $Hr_env]");
      [apply decode_encode_instrW_inv|iCorrectPC a_first a_last|iContiguous_next Hcont 1|..].
    iEpilogue "(HPC & Hi & Hr_env)". iCombine "Hi" "Hprog_done" as "Hprog_done".
    (* move r_t1 0 *)
    iPrologue "Hprog".
    iDestruct "Hr_t1" as (w1) "Hr_t1". 
    iApply (wp_move_success_z with "[$HPC $Hi $Hr_t1]");
      [apply decode_encode_instrW_inv|iCorrectPC a_first a_last|iContiguous_next Hcont 2|..].
    iEpilogue "(HPC & Hi & Hr_t1)". iCombine "Hi" "Hprog_done" as "Hprog_done". 
    (* jmp r_t0 *)
    iPrologue "Hprog". 
    iApply (wp_jmp_success with "[$HPC $Hi $Hr_t0]");
      [apply decode_encode_instrW_inv|iCorrectPC a_first a_last|].

    (* we can now apply the jump or fail pattern *)
    iDestruct (jmp_or_fail_spec with "Hcallback") as "Hcallback_now". 

    (* reassemble registers *)
    iDestruct (big_sepM_insert _ _ r_env with "[$Hregs $Hr_env]") as "Hregs".
    { apply elem_of_gmap_dom_none. rewrite Hdom. clear; set_solver. }
    iDestruct (big_sepM_insert _ _ r_t1 with "[$Hregs $Hr_t1]") as "Hregs".
    { rewrite lookup_insert_ne;auto. apply elem_of_gmap_dom_none. rewrite Hdom. clear; set_solver. }
    
    destruct (decide (isCorrectPC (updatePcPerm wret))). 
    - iDestruct "Hcallback_now" as (p b e a' Heq) "Hcallback'". 
      simplify_eq.
      iEpilogue "(HPC & Hi & Hr_t0)".
      iMod ("Hcls" with "[Hprog_done Hi $Hown]") as "Hown".
      { iNext. iFrame. iDestruct "Hprog_done" as "($&$&$)". done. }
      iDestruct (big_sepM_insert _ _ r_t0 with "[$Hregs $Hr_t0]") as "Hregs".
      { rewrite !lookup_insert_ne;auto. apply elem_of_gmap_dom_none. rewrite Hdom. clear; set_solver. }
      set (regs' := <[PC:=inl 0%Z]> (<[r_t0:=inr (p, b, e, a')]> (<[r_t1:=inl 0%Z]> (<[r_env:=inl 0%Z]> rmap)))). 
      iDestruct ("Hcallback'" $! regs' with "[Hregs $Hown HPC]") as "[_ Hexpr]". 
      { rewrite /registers_mapsto /regs'.
        iSplit.
        - iClear "Hcallback' Hregs HPC". rewrite /interp_reg /=. iSplit.
          + iPureIntro.
            intros r'. simpl.
            consider_next_reg r' PC. consider_next_reg r' r_t0. consider_next_reg r' r_t1. consider_next_reg r' r_env.
            apply elem_of_gmap_dom. rewrite Hdom. assert (r' ∈ all_registers_s) as Hin;[apply all_registers_s_correct|].
            revert n n0 n1 n2 Hin;clear. set_solver.
          + iIntros (r' Hne).
            rewrite /RegLocate.
            consider_next_reg r' PC. done. consider_next_reg r' r_t0. consider_next_reg r' r_t1. rewrite !fixpoint_interp1_eq. done.
            consider_next_reg r' r_env. rewrite !fixpoint_interp1_eq. done.
            destruct (rmap !! r') eqn:Hsome;rewrite Hsome;[|rewrite !fixpoint_interp1_eq;done].
            iDestruct (big_sepM_delete _ _ r' with "Hregs_val") as "[Hr _]";[eauto|]. iFrame "Hr".
        - rewrite insert_insert. iApply (big_sepM_delete _ _ PC);[apply lookup_insert|]. iFrame.
          rewrite delete_insert. iFrame.
          repeat (rewrite lookup_insert_ne;auto). 
          apply elem_of_gmap_dom_none. rewrite Hdom. clear;set_solver.
      }
      rewrite /interp_conf. iApply wp_wand_l. iFrame "Hexpr". 
      iIntros (v). iApply "Hφ".
    - iEpilogue "(HPC & Hi & Hr_t0)".
      iApply "Hcallback_now". iFrame.
      iApply "Hφ". iIntros (Hcontr); inversion Hcontr. 
  Qed.

End counter. 
