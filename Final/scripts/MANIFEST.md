# MANIFEST — scripts pinned to `e2469b1`

`Final/tools/build_final.py`, `stages.py` and `verify_final.sh` (the tools that build and check this folder) are in `../tools/`.
Purpose = first header comment of the file (auto-extracted; "(no header comment found)" when there is none). Stage = rule-based by file name.

| path | stage(s) | sha256 | purpose | source |
|---|---|---|---|---|
| `constraints/legacy/dc_script_legacy.tcl` | 03 | `826cbc3457c0ab850250e7bf6c5e33c64e8692505158e50b20c9b7c879fe4dc4` | ============================================================================= | git |
| `constraints/legacy/test_legacy_dc_script.tcl` | 03 | `85caf5d9067a3d583bd40a2a599b48606027594179fbc3aa10590267cf5c82c1` | ============================================================================= | git |
| `constraints/legacy/unpu_top_legacy.sdc` | 03 | `d095964a879a228c43d34283e64efee6bce193cff9a660047692ac2db060abaf` | ============================================================================= | git |
| `constraints/pm_dc_script_unpu.tcl` | 03 (superseded profiles) | `9f50101ea8e74d62ccebcd535918de40d7045261700f41828ad7090e9d0986bb` | ============================================================================= | git |
| `constraints/pm_unpu_top.sdc` | 03 (superseded profiles) | `93385e7a19ed02472dab392466e6784a8fe2d0be6d8498d3c616d5c23ddea2b3` | ============================================================================= | git |
| `constraints/stage_numbers.tcl` | 03 (superseded profiles) | `53794df64710d437d312c0178915d7885fe494d5b7bed326c14503a03c08169a` | ============================================================================= | git |
| `constraints/test_dc_script.tcl` | 03 (superseded profiles) | `b90afb258b9f486413b0207afe8215e484030e19f3f09fbc89653364fd34f6b6` | ============================================================================= | git |
| `constraints/test_stages.tcl` | 03 (superseded profiles) | `def25b24c67f2eecc4e0ced35ff328f4a93de175eee1b4619bc4221b526501bf` | ============================================================================= | git |
| `constraints/unpu_pe.sdc` | 03 (superseded profiles) | `4edd35c1231b0e6904bd9b1be245993ed5dafe644b393534bad0bb2aef4063c4` | ============================================================================= | git |
| `constraints/unpu_top.sdc` | 03 (superseded profiles) | `48110fbb43cfb142edbde5996963840489df0481ceca12191de3c37c5ac48620` | ============================================================================= | git |
| `model/golden.c` | 02 | `faeb22c3da538b39712c5540ebaa192d97a80ffcac7966bdefb055057cbc4c85` | Golden model for the uNPU 4x4 weight-stationary INT8 matmul. | git |
| `pnr/README.md` | (old flow v1, superseded) | `dd4c38e0ae2bcf80b72d56029b619c8fe5526ad3600c1df37ad45ae64692bb23` | pnr/ -- scripted place-and-route flow (re-run plan: `docs/planning/backend-rerun-plan.md`) | git |
| `pnr/RUNBOOK.md` | (old flow v1, superseded) | `cc880d3d63f963907f44857ee5cff6f26247748fc5680480c422f0020b86ace3` | RUNBOOK — the ICC2 flow, step by step (for the user at the server) | git |
| `pnr/VERIFY_STATUS.md` | (old flow v1, superseded) | `8edb876da5446b46ac78dbd83844b49bde4f408ab020607c8474d1bfe926bff8` | pnr/ — status of the `VERIFY` items (task 047) | git |
| `pnr/common.tcl` | (old flow v1, superseded) | `97f76f8e5a2032c2ef64d509c95b6c1e8d24bee5a8f77d28e81bbdedcec2f3ae` | ============================================================================= | git |
| `pnr/cts.tcl` | 09 | `9ed0c5370cc522421b69ad6d2e5a1b41eeacda20cf365764ee2a78727d2488f3` | ============================================================================= | git |
| `pnr/design_setup.tcl` | 05 | `079f566881ac665cfb4fb3c52fd67326f98699c67a768675e1dbe6c535e3e343` | ============================================================================= | git |
| `pnr/fill.tcl` | (old flow v1, superseded) | `4200547129ecc6f4e6b66f9feb76a4cf189dba29027dc7524434d65cc078a987` | ============================================================================= | git |
| `pnr/floorplan.tcl` | (old flow v1, superseded) | `67080f13ae290717d3629f5809f7a960f9d04f24d585adb5fdaddb5b6ffb9ea1` | ============================================================================= | git |
| `pnr/help_probe.tcl` | (old flow v1, superseded) | `d9af1b0cbe914aa03df2a8a2bed2d0a705814a5b5df9bfe1e4344a5e7eaa10ba` | ============================================================================= | git |
| `pnr/help_probe_lm.tcl` | (old flow v1, superseded) | `599f5e23c23f9788a9f8a53c9079eda6aa652c26e26dc78c88e0adcacfde9064` | ============================================================================= | git |
| `pnr/ndm_check.tcl` | (old flow v1, superseded) | `9e122efb0d3d5eab71c8ed2eab1ab0ca171d249bb0640480246cc7859a910780` | ============================================================================= | git |
| `pnr/ndm_file_gen.tcl` | (old flow v1, superseded) | `fae40c87a03fb96a733283fd4590f1ed47f386e77a9a3d4baee606d990174940` | ============================================================================= | git |
| `pnr/ndm_fill_common.tcl` | (old flow v1, superseded) | `69a6c05aef8d49fd9fd5e9d7c1e401b59cdc10b576fce6940b81e59200f12d50` | ============================================================================= | git |
| `pnr/ndm_fill_probe.tcl` | (old flow v1, superseded) | `e4827512ddc01685da2f4cb7d766a828e71e753ae9200a80508f56d6a14e1169` | ============================================================================= | git |
| `pnr/outputs.tcl` | (old flow v1, superseded) | `4de46e15862ef63dd582247af743d1e2c68f0137faccfd76b23b5f1ccae5d23a` | ============================================================================= | git |
| `pnr/params.tcl` | (old flow v1, superseded) | `562a3c76915971d6e1bbdf73b5b09ff68ab6ae860c0133f51b0e2afb26a05e28` | ============================================================================= | git |
| `pnr/pin_place.tcl` | (old flow v1, superseded) | `2a921e34c4ac720ebf9616e32d12ada50b32f9864d144914f4b6ed417bb3151c` | ============================================================================= | git |
| `pnr/placement.tcl` | 08 | `76427dabf60f08f366b57f74e8df43d37932811f92ab2b910ec86397ec10b33a` | ============================================================================= | git |
| `pnr/power.tcl` | (old flow v1, superseded) | `fb786f14fdb6bcdc11e81a286c08f3807257040de9fb8ee8510bbce606ba3172` | ============================================================================= | git |
| `pnr/route.tcl` | 10, 12 | `14296480ea1d7aaa754a569bbfb7302ecb1aa61f9395cd8a83fd3c51fc115853` | ============================================================================= | git |
| `pnr/test_common.tcl` | (old flow v1, superseded) | `9436e64a58412d8be3e7e7ebdde78d52de996ca1d8eb587a21a9d81941bcde43` | ============================================================================= | git |
| `pnr_v2/IO_LATENCY_RESEARCH.md` | (support) | `5a4b27aafd098488a272602dd2c0fd4ca7bc1438f625cb12d267ba917d78abdc` | I/O clock-latency research (task 083 Part A, 2026-11-10) and its diagnostic (task 084) | git |
| `pnr_v2/PIN_SPACING_RESEARCH.md` | (support) | `e8e00eecb7a1e884e7584920ecc4f91450eba8ec27f3a512ed9ec1ca4f461f87` | Why the second `place_pins` ignored the 8 um spacing, and what pin placement can and cannot do for the antenna problem (task 085 Part 2, read-only research) | git |
| `pnr_v2/README.md` | (support) | `fcdf8047f9ae97b2dcc987faba7e3e0cd5f58d65e6a6d7f2b322428e2f34a836` | pnr_v2 -- the user's example ICC2 scripts, minimally edited for `unpu_top` (task 063) | git |
| `pnr_v2/RUN3_RUNBOOK.md` | (support) | `144ba24149247ca0f4494ff5e9585f21aa86b9ddc869677c275246ce0f925bb3` | Run 3 runbook: the ordered steps that produced the final state (2026-11-10 19:26 to 2026-11-11 04:43) | git |
| `pnr_v2/VERIFY_STATUS_RUN3.md` | (support) | `a13e4ff4534e66f6220a234677e66b633117270d2be2035d2af7281b528ec07e` | VERIFY status after run 3 (final layout, 2026-11-11) | git |
| `pnr_v2/antenna_clk_root.tcl` | 11 | `fb874e2b45880194235934f10edeeee8e763203eb5b6341323bad5513627f635` | ============================================================================== | git |
| `pnr_v2/antenna_port_buffers.tcl` | 11 | `87097768d9f05bd808b1caa17145ca71b69bbd94ca4af56e5c259ba850b2834d` | ============================================================================== | git |
| `pnr_v2/build_ndm_filler.tcl` | 04 | `415d3ae6dbf0bb3567c0128e3e4f076fdfdc31f7cf4712c91d998409aab8b849` | ============================================================================== | git |
| `pnr_v2/build_ndm_std.tcl` | 04 | `a154cfa50bb6edbcd3b706c0116a43554d6bd9b1c33d09b83b124f8ead0fc4b7` | ============================================================================== | git |
| `pnr_v2/calibre/README.md` | 13 | `687b576c3d6a5483a1bc972ed9939bfa827bb6fcfc080fc7512e3027158683a5` | Calibre DRC, antenna and LVS for the clean-slate layout (task 066) | git |
| `pnr_v2/calibre/ant.ctrl` | 13 | `ca7f8ebe3178447e35ff05cae1457550de4c44c44b1051c85828a1fe608d5139` | 082: RELATIVE on purpose (VERIFY V18: Calibre resolves LAYOUT PATH from the folder it is started in, like SOURCE PATH / MASK SVDB DIRECTORY). Start it from <RUN | git |
| `pnr_v2/calibre/drc.ctrl` | 13 | `58c4e5d4da1c1dcef44f815f2dc3305b9658c40822d1159fe99570cf63675332` | 082: RELATIVE on purpose (VERIFY V18: Calibre resolves LAYOUT PATH from the folder it is started in, like SOURCE PATH / MASK SVDB DIRECTORY). Start it from <RUN | git |
| `pnr_v2/calibre/lvs.ctrl` | 13 | `43044f1d86745f6b89aea349206efdc0e0d70f410cc3b4070b745eea28e9ccab` | lvs.ctrl -- Calibre LVS control file for the clean-slate layout (task 066) | git |
| `pnr_v2/clock_latency.tcl` | 08 | `7a8cc49ef414dfdbabd2ddc907ef883c4b12f33bb61841f7da01f9ab29e0e920` | ============================================================================== | git |
| `pnr_v2/cts.tcl` | 09 | `5277df36d1509ed0d919354967558f1be24048d753811fd699040c8eb158c70d` | ============================================================================== | git |
| `pnr_v2/design_setup.tcl` | 05 | `5f667041d4ea685364f14d3f3ba797d2cab06c7a0dd7d43aafa8fe1c0b854fea` | ============================================================================== | git |
| `pnr_v2/diag_clock_latency_origin.tcl` | 08 | `22b01032a5b1baa0abdb883401e2df84223c13ec0917c50fb132b2998f9a105c` | ============================================================================== | git |
| `pnr_v2/diag_filler_runs.tcl` | 08 | `54e73d3d9720da0a8bfeb0e3087da63ad447580c63e99fce07b6cb8ce4b7c88d` | ============================================================================== | git |
| `pnr_v2/diag_io_latency.tcl` | 08 | `035f800e58201a5267bae808ec33b410f8cfa359a67f00a63940f4534378ce7f` | ============================================================================== | git |
| `pnr_v2/diag_io_whatif.tcl` | 08 | `e8d08c8280bcf17701fde48e3ba8ce1737c1c3dc413c172a15fc2e03d37c0c1a` | ============================================================================== | git |
| `pnr_v2/fix_antenna.tcl` | 11 | `0f704b90ab1d0c8fb849525d4abf1a88b551795a37c688f323c78ef79a942a27` | ============================================================================== | git |
| `pnr_v2/floorplanning.tcl` | 06 | `6f3a9b0898d6bf982ecb8c977be747725e0d684e20444bcb7644d4e71c3df657` | ============================================================================== | git |
| `pnr_v2/metal_fill.tcl` | 12 | `54c06534ce8cfb89c27dea8f5758cff1196b3909873a8d02b6c5556d54c2127f` | ============================================================================== | git |
| `pnr_v2/opt_uncertainty.tcl` | 08 | `ce40a6263cb5cb4c3f84b12808911ff17453e8f2b66db406fde6f7ae093598dc` | ============================================================================== | git |
| `pnr_v2/pin_replace.tcl` | 06 | `b358c7af0f38f24e130c9f2d477908f02b32cf9925b31766e3a8d85f034d4ca9` | PARKED (task 068): see README | git |
| `pnr_v2/placement.tcl` | 08 | `6e142edd3c5c526257765f0a64129f0e01909ea9ee601ba2fd71d1522bc378dc` | ============================================================================== | git |
| `pnr_v2/port_buffers_early.tcl` | 08 | `7b065928ea7c3611662e9fcc1e343cf83e0a9f42c45b5532d56f624d5f7631af` | ============================================================================== | git |
| `pnr_v2/powerplanning.tcl` | 07 | `e8a1336e606c572a71b84f8fd454fcb66ac12f57bee78163c83bcd03b1042f94` | ============================================================================== | git |
| `pnr_v2/pt/README.md` | 14 | `215f85741516e29143645fa449fb832bf5dee56f06f83e5fc862406b19989b41` | PrimeTime sign-off of the final layout (task 074) | git |
| `pnr_v2/pt/check_annotation.tcl` | 14 | `6c67a7b097b1eb761ee5f39edbde4e8acc4803386686afe4aa0927d4e50e0911` | ============================================================================== | git |
| `pnr_v2/pt/pt_common.tcl` | 14 | `1b6d2bb22ce988c5bbace052a2154b4e8362abb146d27f42c80aa4a0f90b64a8` | ============================================================================== | git |
| `pnr_v2/pt/pt_eco_drc_probe.tcl` | 11 | `5f82fb1b22156f08d655e7b81e9969a352bc0d1d6e3de5a0079c888591bb03c5` | ============================================================================== | git |
| `pnr_v2/pt/pt_eco_probe.tcl` | 11 | `1aeeb7692a629f8cd4309c4fbb71922d4c40f513f119e68c9b408f48492b57cd` | ============================================================================== | git |
| `pnr_v2/pt/pt_eco_setup_probe.tcl` | 11 | `bafd349efc1009b3a387ff7bb40930cae4fe3d55bc153785f988ef7162e0d53e` | ============================================================================== | git |
| `pnr_v2/pt/pt_hold_ff.tcl` | 14 | `6dfcc03fd4f7de5eed83f99022f308b861e84cd9fb073a305e275336cf5fa2b2` | ============================================================================== | git |
| `pnr_v2/pt/pt_setup_ss.tcl` | 14 | `e0e6bdae5221609a8326fb0ef793a4b00cf178a89385e5bb97de622a2a8bb69a` | ============================================================================== | git |
| `pnr_v2/pt/test_pt_common.tcl` | 14 | `e6892b91f143a3fd3b9cb57a48b1be3336a9727632d8b68dc148eb7baa7339e7` | ============================================================================== | git |
| `pnr_v2/pt_eco_apply.tcl` | 11 | `05ef396f0b7a06aa9aee20e54b03e564eb5a9ce1143e4aa8442f9e1788b23ac4` | ============================================================================== | git |
| `pnr_v2/pv.tcl` | 10, 12 | `74f778cbe6908c80b8ea3aed4f93b7a8d49a2a8fd68d9e09c475cf47dbfd1f12` | ============================================================================== | git |
| `pnr_v2/route.tcl` | 10, 12 | `ca7acd5f78433a4b9ad4efe11292abcca44d1b5d10c01a345bb467441c8f9751` | ============================================================================== | git |
| `pnr_v2/run_root.tcl` | 05 | `f8c39606e59bc39c09afda601fa1a110e503b90d869d18d6294ba8217e06f3fc` | ============================================================================== | git |
| `pnr_v2/sdc_compare.tcl` | 12 | `79b853fbaaa937337a8e74ada1e8585b7c764f78b746e53f5749210d6d0f97ab` | ============================================================================== | git |
| `pnr_v2/sim/README.md` | 15 | `901b754e03eda3090e004948723172bafbc4a8be6e62079278b517570321af5e` | Post-layout simulation with the SDF (Xcelium) -- task 075 | git |
| `pnr_v2/sim/run_experiments.sh` | 15 | `fac724fcd89e37121bec31edeeacb89ce80d3359f4c544594e229e8a526483ab` | The two simulation experiments of task 094 in ONE command (README "Experiments that remove the causes"): | git |
| `pnr_v2/sim/run_postlayout_sim.sh` | 15 | `a88f59e8cd320916c74ce5a397bdbffbf1372869d8aba1ab9275801fb5d185d2` | Post-layout simulation with the SDF (task 075): the SAME testbench tb/unpu_top_tb.sv against the post-layout netlist written by pv.tcl, with the SDF of one corn | git |
| `pnr_v2/sim/test_postlayout_verdict.sh` | 15 | `03d9dc2bc3bf5279933e034f8e43c4cc47930732df8d74a8e855618cf05d1fea` | Test of the verdict logic of pnr_v2/sim/run_postlayout_sim.sh (task 075) on SAMPLE log texts, plus the dry-run output and the usage errors. | git |
| `pnr_v2/test_antenna_clk_root.tcl` | 11 | `33e0bb494dd6f809a765d6b96ff42ca76582e13364f0263a88720e73467a5f91` | ============================================================================== | git |
| `pnr_v2/test_antenna_port_buffers.tcl` | 11 | `a685ebf3ec226c4a77a203068501821eefdbda9b994157c3a90e1ddfa8c60101` | ============================================================================== | git |
| `pnr_v2/test_clock_latency.tcl` | 08 | `ac141e7eb87bba1ac54452cfe82286326591b1600df7e1eff6c55d430072e565` | ============================================================================== | git |
| `pnr_v2/test_diag_io_latency.tcl` | 08 | `d2f9214397862a7602939a8897cabd7545dc59268e440c5ae641f91d86e3148e` | ============================================================================== | git |
| `pnr_v2/test_diag_io_whatif.tcl` | 08 | `1897f96e853a092448af5a89bfa8d3c5178a9ec605625956476713544a068f03` | ============================================================================== | git |
| `pnr_v2/test_drc_eco.tcl` | 11 | `cdca5f4a0d061d3f745062c9376c717e04b92eecb8bafe40255911acb52b7dda` | ============================================================================== | git |
| `pnr_v2/test_eco_scope.tcl` | 11 | `170c1b965ca652a76af7ccdc31dc73963b7514903b124095344f646d3020babd` | ============================================================================== | git |
| `pnr_v2/test_opt_uncertainty.tcl` | 08 | `b0c1fd134f33d2d5a70b8241351fecdbfbcfb89365f73f28132157f62dd92ca6` | ============================================================================== | git |
| `pnr_v2/test_port_buffers_early.tcl` | 08 | `8cb2b86e24b2d8fa555218872a6624ede447e9fece19f36fb1a539c933ddfd08` | ============================================================================== | git |
| `pnr_v2/test_pt_eco_apply.tcl` | 11 | `bfd8753829f34af5fef37dfaa9a6ea98fe6f0ffc53ecf8f4401352d323c59053` | ============================================================================== | git |
| `pnr_v2/test_pv_checkpoint.tcl` | 10, 12 | `166d7f486bcb21a6b8678541a4e35b22a9f50d3683b599a373a18b1b65e00965` | ============================================================================== | git |
| `pnr_v2/test_pv_lef_check.tcl` | 10, 12 | `f80b7b413855e69f2828cd1d5dd996a876e789aecbff550fa30aebe5420796b4` | ============================================================================== | git |
| `pnr_v2/test_pv_sdf_check.tcl` | 10, 12 | `3f0f4159ef83debdf2ba77662c115a137b15f5c8dfe5cffdece7444e5077854f` | ============================================================================== | git |
| `pnr_v2/test_run_root.tcl` | 05 | `3d845ac22797f20fba2bab2504d2c4772879f50915b1aba4d312962ed7b81cd9` | ============================================================================== | git |
| `pnr_v2/test_sdc_limits.tcl` | 12 | `2a54cca35a99dc0519635b14c2c22c117e7768a543261039fe85141a7ec47e09` | ============================================================================== | git |
| `pnr_v2/test_si_eco.tcl` | 11 | `d877effc48d797195ab199784eb649b6c53b0ee91498f8f9f1cd74913363f98a` | ============================================================================== | git |
| `pnr_v2/test_timing_closure.tcl` | 08 | `56a812bd3ac72a9d01d73263a720eab8e184a277a91347784a31fe34ede1267f` | ============================================================================== | git |
| `pnr_v2/testdata/095_run3_ff_design_rules.rpt` | (support) | `26b28309125db0a127fbdf53e6b7db549333153f4492100e667ae3aee63bc374` | (no header comment found) | git |
| `pnr_v2/testdata/095_run3_ss_design_rules.rpt` | (support) | `7de7632e1debda9d50e1b71781f79a3a4ce2af55cf5778b6b41242a85ff0caf8` | (no header comment found) | git |
| `pnr_v2/testdata/096_run3_exported_ff.sdc` | (support) | `e6ca89af17e347cad78384cdb6bfb045136bc9a95fa1fb832a39cc86abcc14fd` | (no header comment found) | git |
| `pnr_v2/testdata/096_run3_exported_ss.sdc` | (support) | `e90f744c308396aec686968299e0d2236270432c7b34109f80503eb01249d70c` | (no header comment found) | git |
| `pnr_v2/testdata/annotation_si_off.txt` | (support) | `1d9bca3fc5e7ee2258f2bf73622de8a74380043793b3d93925677bb40943f013` | ------------------+---------+---------+---------+---------+---------+ | git |
| `pnr_v2/testdata/annotation_si_on.txt` | (support) | `862b71b9bd0302c518fe7888b119c2ee271d6fc5ce556775968ee386b71fb7ef` | ------------------+---------+---------+---------+---------+---------+---------+ | git |
| `pnr_v2/testdata/pt_eco_hold_changes_head.tcl` | 11 | `417bb9970db8455ed503e6a911b9a23850012724743d7f18be2aab1fb087b0af` | Change list, formatted for IC Compiler | git |
| `pnr_v2/testdata/pt_eco_setup_changes_head.tcl` | 11 | `8923474cf9f107f8c5f64e77dd5c53a4b68baa88cf1d4d5953b086d8824bae71` | Test data (task 079 fix): the two NON-COMMENT lines are verbatim from the user's server file pnr_icc2/pt/pt_eco_setup_changes_icc2.tcl (reported by Planning); | git |
| `pnr_v2/timing_closure.tcl` | 08 | `4b83c50d42c6ef1d7643ee02181e80860693a3984311ba9e1a63b290dec35c1b` | ============================================================================== | git |
| `rtl/unpu_actbuf.sv` | 01 | `bf89178581f1d7d1ae26d0e041c4df9603ef67a7f944f0a8e1888f0ab97d68e3` | Double-buffered activation staging for the uNPU 4x4 systolic array. | git |
| `rtl/unpu_apb.sv` | 01 | `cfe55d2abc5fc3c4b2c86d94d251435692a99cdfddde888a9036526213975208` | APB slave for the uNPU CSR window. Turns CPU-facing (and SPI-debug- | git |
| `rtl/unpu_csr.sv` | 01 | `894587f7a1e055fea0f4297a7879868d79edbc3cf9a4a7ab2907eb5ef3b0ef81` | CSR / register file for the uNPU. Pure control-plane storage and | git |
| `rtl/unpu_deskew.sv` | 01 | `ebe2700a769f5efb1e9f5064a095d67ffb7b3b89cbf0c9b0938b3ad56adea601` | Output de-skew bank for the uNPU 4x4 systolic array. Delays each | git |
| `rtl/unpu_dma.sv` | 01 | `b772f1d7bb89beea04e651c2d949957e5e2b7a1408149d107f9d883871395796` | DMA master for the uNPU 4x4 systolic array. Moves A/W tensors from | git |
| `rtl/unpu_grid.sv` | 01 | `639af15ab6386a44efdea5f329d817cdf5241b59ffcdb5eccf95417099129900` | 4x4 systolic array of unpu_pe. Weight-stationary, single-stage PEs. | git |
| `rtl/unpu_pe.sv` | 01 | `5a1843b42827f10d65b84eafb27e2c2640321d9f7a7176ef3a240ed69f511a23` | Single-stage systolic processing element for the uNPU 4x4 INT8 array. | git |
| `rtl/unpu_seq.sv` | 01 | `01d6742d8a7a516d43e80da33f710e92932674988ec4f43d2d84c22851635fbb` | Main sequencer FSM for the uNPU 4x4 systolic array. Task 011 revision: | git |
| `rtl/unpu_skew.sv` | 01 | `598abaeb368280a676961df365d390a4fce73ccbf9fdd99c41f083bb481145d7` | Input skew bank for the uNPU 4x4 systolic array. Delays each row's raw | git |
| `rtl/unpu_top.sv` | 01 | `4878abfeb732e975a5a61bd3ad7aa46a76fe054330bf6ba2068c5029fcc9feab` | Top-level integration for the uNPU macro. Pure wiring across ten | git |
| `rtl/unpu_wbuf.sv` | 01 | `abfccc7515add055c8cbc3ab4f478ad414a38efb7f850965f4f8ccbf167cacce` | Double-buffered weight staging for the uNPU 4x4 systolic array. | git |
| `scripts/bootstrap.sh` | 02 | `7b6d9dfc08aa5f2f667bbf905b1393aef9e327d8ee1997503d7342aa942605e2` | Run this from inside the cloned repo root. | git |
| `scripts/dc_summary.sh` | 03 | `863ace9c4e04f4476fed85b1e8e0e0e3f4e6559d71fbf0353bf01cf86d5f6850` | Quick read of a Design Compiler run written by syn/dc_run.tcl (task 035). | git |
| `scripts/run_gls.sh` | 03 | `061a1deb4e25761ddafe839f9a437c016ca7e9079fa27b081a023a3b5cc9962f` | Gate-level simulation of a synthesised clean-name netlist with Xcelium (task 059; replaces the hand-typed xrun lines of syn/RUNBOOK.md step 6). | WORKTREE (not pinned): untracked in git at the pinned commit (copied from the working tree) |
| `scripts/run_xrun.sh` | 02 | `4937f0665ee1b70b721174d4e1def76500e1828d10ae18712761a56426e81a24` | Run the uNPU testbenches under Cadence Xcelium (xrun) and report per-TB | git |
| `scripts/syn_compare.sh` | 03 | `fe3ab141628a1bcc16503724f786735530b77f1f7602f78d529e20614f3513cd` | Compare the Design Compiler runs of the stage profiles syn20 / syn18 / syn16 (task 052). | git |
| `scripts/test_run_gls.sh` | 03 | `eab97b8ff9dbcd337862db2e609e4cca37eeebf771d6ca52b96d13775e1e428a` | Self-test of scripts/run_gls.sh (task 059) with a STUB xrun: proves the argument handling, the file names, the verdict logic. It proves | WORKTREE (not pinned): untracked in git at the pinned commit (copied from the working tree) |
| `scripts/test_syn_compare.sh` | 03 | `563d54118aa047487fd2858f7c7c8b4265fbde2e31f4faf6460cecba0fd02e93` | Test of scripts/syn_compare.sh (task 052). Builds sample run directories in a temporary folder from the text of the REAL round-3 | git |
| `syn/RUNBOOK.md` | 03 | `a49bab7c40d3641aab33fa1c75ca5476747a5d082d9a348730940eb589bb8e56` | syn/RUNBOOK.md — Design Compiler at three periods, comparison, choice of netlist, gate-level simulation | git |
| `syn/RUNBOOK_legacy.md` | 03 | `91bcb815650c680899bf9045f7f01849eeff0d4b3cea443bcc1e650f6e152229` | syn/RUNBOOK_legacy.md -- synthesis with the OLD constraints into `syn/out/legacy/` (task 064) | git |
| `syn/dc_run.tcl` | 03 | `c3396e703261797a64a30ddd6b588d3701a8945411c42dd7b06f4bf70c979386` | ============================================================================= | git |
| `syn/dc_setup.tcl` | 03 | `a4a0ea50733de768cebb647aab0773f88b1cf643666e661b5e7287e322f1971e` | ============================================================================= | git |
| `tb/unpu_apb_tb.sv` | 02 | `d6c43f20d88d283c987c914ec191436bf15fae94e4434d29307915b06b8c6015` | Integration test for unpu_apb, paired with a REAL unpu_csr (task 009) | git |
| `tb/unpu_buf_tb.sv` | 02 | `b34092128857eb678fe66b88ad05fc4b39c33f69f99f3b5bbe201a979af0809d` | Integration test for unpu_wbuf + unpu_actbuf, driving the real | git |
| `tb/unpu_csr_tb.sv` | 02 | `bef796ea65fcc8af955d9eb95767fcc285cf22d9958e33c6dd4ddbfa5aa0d439` | Directed + CRV test for unpu_csr. Pure control-plane module -- no | git |
| `tb/unpu_dma_tb.sv` | 02 | `ed4e32b96106b6b6881017821badb93cac6145fd59aedebb45f6f8cca4092131` | Integration test for unpu_dma, driving real unpu_actbuf/unpu_wbuf | git |
| `tb/unpu_ext1_tb.sv` | 02 | `3a77c39671fbdfe59d725f3867b7f0fc772cd66dee7e97460766ddb254841c93` | ============================================================================= | git |
| `tb/unpu_ext2_tb.sv` | 02 | `e753da2a2b1682b4f25e8443d43e80ffc6cb208ec18fa4791f69f471b24881db` | ============================================================================= | git |
| `tb/unpu_grid_tb.sv` | 02 | `5294e970b7aa3798fd289f89f782a17c3c8178556a80f3a52d8b2fd0b09d4c4f` | Grid-level identity/matmul test for unpu_grid (End-W2 gate). | git |
| `tb/unpu_pe_tb.sv` | 02 | `8a7ab559f84b442b8441f3be97bf41c226a16b2047181fcfab9baf3e238764db` | Directed unit test for unpu_pe. Self-checking, 20 vectors, plus (task | git |
| `tb/unpu_seq_tb.sv` | 02 | `f1f6e1d97d5a63fb7ec88a6f84a985c009e54ae9927097845d7038654fc57056` | Full-stack integration test for the revised unpu_seq (task 011): | git |
| `tb/unpu_skew_tb.sv` | 02 | `66919b90617d20ff5ac0fcf94b5f6fcad0fae091f3202c318e34725e569db40a` | End-to-end skew -> grid -> de-skew timing-contract test for the uNPU | git |
| `tb/unpu_stall_tb.sv` | 02 | `6982a969154bcb7daa8dbf35f4b41a5a5c682106222ec472fc1dff2290d0e69b` | Stall test: proves dropping array_en mid-stream freezes the skew bank, | git |
| `tb/unpu_top_tb.sv` | 02 | `94c6f36a600a41d5ce4798cb6dd1c5fd729aaa8e463699d497c7d8f02a515a0b` | CPU's-eye-view integration test for unpu_top. Drives the DUT through | git |
