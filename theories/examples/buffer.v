From iris.algebra Require Import frac.
From iris.proofmode Require Import tactics.
Require Import Eqdep_dec List.
From cap_machine Require Import rules logrel fundamental.
From cap_machine Require Import proofmode.
From cap_machine.examples Require Import template_adequacy.
Open Scope Z_scope.

Section buffer.
  Context {Σ:gFunctors} {memg:memG Σ} {regg:regG Σ}
          {nainv: logrel_na_invs Σ}
          `{MP: MachineParameters}.

  Context (N: namespace).

  Definition buffer_code (off: Z) : list Word :=
    (* code: *)
    encodeInstrsW [
      Mov r_t1 PC;
      Lea r_t1 4 (* [data-code] *);
      Subseg r_t1 (off + 4)%Z (* [data] *) (off + 7)%Z (* [data+3] *);
      Jmp r_t0
    ].
  Definition buffer_data : list Word :=
    (* data: *)
    map WInt [72 (* 'H' *); 105 (* 'i' *); 0; 42 (* secret value *)]
    (* end: *).

  Lemma buffer_spec (a_first: Addr) wadv w1 φ :
    let len_region := length (buffer_code a_first) + length buffer_data in
    ContiguousRegion a_first len_region →

   ⊢ (( codefrag a_first (buffer_code a_first)
      ∗ PC ↦ᵣ WCap RWX a_first (a_first ^+ len_region)%a a_first
      ∗ r_t0 ↦ᵣ wadv
      ∗ r_t1 ↦ᵣ w1
      ∗ ▷ (let a_data := (a_first ^+ 4)%a in
             PC ↦ᵣ updatePcPerm wadv
           ∗ r_t0 ↦ᵣ wadv
           ∗ r_t1 ↦ᵣ WCap RWX a_data (a_data ^+ 3)%a a_data
           -∗ WP Seq (Instr Executable) {{ φ }}))
      -∗ WP Seq (Instr Executable) {{ φ }})%I.
  Proof.
    intros len_region.
    iIntros (Hcont) "(Hprog & HPC & Hr0 & Hr1 & Hφ)".
    iGo "Hprog".
    { transitivity (Some (a_first ^+ 4)%a); auto. solve_addr. }
    { transitivity (Some (a_first ^+ 7)%a); auto. solve_addr. }
    solve_addr.
    iInstr "Hprog". iApply "Hφ". iFrame.
    rewrite (_: (a_first ^+ 4) ^+ 3 = a_first ^+ 7)%a //. solve_addr.
  Qed.
End buffer.

Program Definition buffer_inv (pstart: Addr) : memory_inv :=
  MkMemoryInv
    (λ m, m !! (pstart ^+ 7)%a = Some (WInt 42))
    {[ (pstart ^+ 7)%a ]}
    _.
Next Obligation.
  intros pstart m m' H. cbn in *.
  specialize (H (pstart ^+ 7)%a). feed specialize H. by set_solver.
  destruct H as [w [? ?] ]. by simplify_map_eq.
Qed.

Lemma adequacy `{MachineParameters} (P Adv: prog) (m m': Mem) (reg reg': Reg) es:
  prog_instrs P = buffer_code (prog_start P) ++ buffer_data →
  with_adv.is_initial_memory P Adv m →
  with_adv.is_initial_registers P Adv reg →
  Forall (λ w, is_cap w = false) (prog_instrs Adv) →

  rtc erased_step ([Seq (Instr Executable)], (reg, m)) (es, (reg', m')) →
  m' !! (prog_start P ^+ 7)%a = Some (WInt 42).
Proof.
  intros HP Hm Hr HAdv Hstep.
  generalize (prog_size P). rewrite HP /=. intros.

  (* Prove the side-conditions over the memory invariant *)
  eapply (with_adv.template_adequacy P Adv (buffer_inv (prog_start P)) m m' reg reg' es); auto.
  { cbn. unfold with_adv.is_initial_memory in Hm. destruct Hm as (Hm & _ & _).
    eapply lookup_weaken; [| apply Hm]. rewrite /prog_region mkregion_lookup.
    { exists 7%nat. split. done. rewrite HP; done. }
    { apply prog_size. } }
  { cbn. apply elem_of_subseteq_singleton, elem_of_list_to_set, elem_of_region_addrs. solve_addr. }

  intros * Hrmap_dom. iIntros "(#HI & Hna & HPC & Hr0 & Hrmap & Hadv & Hprog)".

  (* Extract the code & data regions from the program resources *)
  iAssert (codefrag (prog_start P) (buffer_code (prog_start P)) ∗
           [∗ list] a;w ∈ (region_addrs (prog_start P ^+ 4)%a (prog_start P ^+ 7)%a);(take 3%nat buffer_data), a ↦ₐ w)%I
    with "[Hprog]" as "[Hcode Hdata]".
  { rewrite /codefrag /region_mapsto.
    set M := filter _ _.
    set Mcode := mkregion (prog_start P) (prog_start P ^+ 4)%a (buffer_code (prog_start P)).
    set Mdata := mkregion (prog_start P ^+ 4)%a (prog_start P ^+ 7)%a (take 3%nat buffer_data).

    assert (Mcode ##ₘ Mdata).
    { apply map_disjoint_spec.
      intros ? ? ? [ic [? ?%lookup_lt_Some] ]%mkregion_lookup
                   [id [? ?%lookup_lt_Some] ]%mkregion_lookup.
      2,3: solve_addr. simplify_eq. solve_addr. }

    assert (Mcode ∪ Mdata ⊆ M) as HM.
    { apply map_subseteq_spec. intros a w. intros [Ha|Ha]%lookup_union_Some; auto.
      { apply mkregion_lookup in Ha as [? [? HH] ]. 2: solve_addr.
        apply map_filter_lookup_Some_2.
        2: { cbn; apply not_elem_of_singleton. apply lookup_lt_Some in HH. solve_addr. }
        subst. rewrite mkregion_lookup. 2: rewrite HP; solve_addr.
        eexists. split; eauto. rewrite HP. by apply lookup_app_l_Some. }
      { apply mkregion_lookup in Ha as [i [? HH] ]. 2: solve_addr.
        apply map_filter_lookup_Some_2.
         2: { cbn; apply not_elem_of_singleton. apply lookup_lt_Some in HH. solve_addr. }
        subst. rewrite mkregion_lookup. 2: rewrite HP; solve_addr.
        exists (i+4)%nat. split. solve_addr+. rewrite HP.
        apply lookup_app_Some. right. split. solve_addr+. apply take_lookup_Some_inv in HH as [? ?].
        rewrite (_: i + 4 - _ = i)%nat //. solve_addr. } }

    iDestruct (big_sepM_subseteq with "Hprog") as "Hprog". apply HM.
    iDestruct (big_sepM_union with "Hprog") as "[Hcode Hdata]". assumption.
    iDestruct (mkregion_sepM_to_sepL2 with "Hcode") as "Hcode". solve_addr.
    iDestruct (mkregion_sepM_to_sepL2 with "Hdata") as "Hdata". solve_addr.
    iFrame. }

  assert (is_Some (rmap !! r_t1)) as [w1 Hr1].
  { rewrite elem_of_gmap_dom Hrmap_dom. set_solver+. }
  iDestruct (big_sepM_delete _ _ r_t1 with "Hrmap") as "[[Hr1 _] Hrmap]"; eauto.

  (* The capability to the adversary is safe and we can also jmp to it *)
  iDestruct (mkregion_sepM_to_sepL2 with "Hadv") as "Hadv". apply prog_size.
  iDestruct (region_integers_alloc' _ _ _ (prog_start Adv) _ RWX with "Hadv") as ">#Hadv". done.
  iDestruct (jmp_to_unknown with "Hadv") as "Hcont".

  iApply (buffer_spec (prog_start P) with "[-]"). solve_addr. iFrame.
  simpl. rewrite (_: prog_start P ^+ (_ + _) = prog_end P)%a. 2: solve_addr. iFrame.
  iNext. iIntros "(HPC & Hr0 & Hr1)".

  (* Show that the contents of r1 are safe *)
  iDestruct (region_integers_alloc' _ _ _ (prog_start P ^+ 4)%a _ RWX with "Hdata") as ">#Hdata".
    by repeat constructor.

  (* Show that the contents of unused registers is safe *)
  iAssert ([∗ map] r↦w ∈ delete r_t1 rmap, r ↦ᵣ w ∗ interp w)%I with "[Hrmap]" as "Hrmap".
  { iApply (big_sepM_mono with "Hrmap"). intros r w Hr'. cbn. iIntros "[? %Hw]". iFrame.
    destruct w; [| by inversion Hw]. rewrite fixpoint_interp1_eq //. }

  (* put the other registers back into the register map *)
  iDestruct (big_sepM_insert _ _ r_t1 with "[$Hrmap Hr1]") as "Hrmap".
    by rewrite lookup_delete.
  { iFrame. rewrite (_: (prog_start P ^+ _) ^+ _ = prog_start P ^+ 7)%a //. solve_addr+. }
  rewrite insert_delete.
  iDestruct (big_sepM_insert _ _ r_t0 with "[$Hrmap Hr0]") as "Hrmap".
    rewrite lookup_insert_ne //. apply not_elem_of_dom. rewrite Hrmap_dom. set_solver+.
  { by iFrame. }

  iApply (wp_wand with "[-]").
  { iApply "Hcont"; cycle 1. by iFrame. iPureIntro. rewrite !dom_insert_L Hrmap_dom.
    rewrite !singleton_union_difference_L. set_solver+. }
  eauto.
Qed.