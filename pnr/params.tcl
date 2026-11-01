# =============================================================================
# params.tcl -- every parameter of the back-end (place and route) flow, in one place
#
# Sourced by every pnr/*.tcl stage script (through common.tcl) and by plain
# tclsh for the local tests. It holds `set` commands and a few derived values
# only: NO tool command, NO file access at source time. It prints the derived
# floorplan values and dies (Error: [unpu] ..., exit 1) if they are not
# consistent.
#
# Environment overrides (csh: setenv NAME value):
#   SCL_KIT_ROOT       SCL kit root (read-only; nothing is ever written into it)
#   UNPU_WORK          work directory of the whole re-run (outside the repo)
#   UNPU_RUN_TAG       run name; one directory per run under UNPU_WORK
#   UNPU_NETLIST       DC netlist (default: the untracked DC output in the repo clone)
#   UNPU_SDC           DC-written SDC (same)
#   UNPU_NDM_MODE      two (default) | single      (see ndm_file_gen.tcl; single does not work on this kit)
#   UNPU_BLK_<NAME>    override of a checkpoint block name BLK_<NAME> (IMPORT FP PWR PINS PLACED CTS CLKOPT ROUTE_AUTO ROUTED FINAL)
#   UNPU_CTS_STAGE     all | tree | hold   (cts.tcl)
#   UNPU_OUTPUTS_OVERWRITE  1 lets outputs.tcl delete and rewrite existing output files (default 0)
#   UNPU_GDS_LAYER_MAP  path of a corrected GDS layer map used instead of the kit map (outputs.tcl)
#   UNPU_PIN_SIDE_RIGHT / UNPU_PIN_SIDE_TOP  side numbers of the pin placer for the right (APB) and top (DMA) groups (defaults 3 / 2, a guess)
#   UNPU_FILL_ECO      1 lets fill.tcl run route_eco once if fillers with violations remain (default 0)
#   UNPU_ROUTE_ACCEPT_HOLD  1 lets route.tcl save with a hold residual (default 0; never set it without a written reason)
#   UNPU_ICC2_ROOT     install directory of the ICC2 release that matches icc2_shell
#   UNPU_DIE_SIZE      die side in um   (plan 2.2 default below; the old run was 817.6)
#   UNPU_HOLD_UNCERT   hold uncertainty in ns (default below; the old run applied 0.2)
# The last two are experiment knobs (plan A2 regression with the OLD parameters,
# plan X1); the defaults are the plan's values and are not changed here.
#
# Every parameter has its source in a comment: a handoff section
# (docs/session-handoff.md), a kit file, or "plan" (docs/planning/backend-rerun-plan.md).
# No value from the plan is changed in this file without Planning.
# =============================================================================

# Snapshot of the global variables before this file runs, so that the list of
# parameters (UNPU_PARAM_NAMES, used by the run manifest) is computed, not typed.
if {![info exists UNPU_PARAM_NAMES]} {
  set _p_before [info globals]
}

# ---- tiny helpers (pure Tcl) -------------------------------------------------
proc _p_die {msg} {
  if {[llength [info commands unpu_die]]} {
    unpu_die $msg
  } else {
    puts "Error: \[unpu\] $msg"
    exit 1
  }
}
proc _p_env {name default} {
  if {[info exists ::env($name)] && $::env($name) ne ""} { return $::env($name) }
  return $default
}
# floating-point "is this an integer" test with a small tolerance; returns the integer
proc _p_int_or_die {what value tol} {
  set r [expr {round($value)}]
  if {abs($value - $r) > $tol} {
    _p_die "$what = $value is not an integer (nearest $r, tolerance $tol)"
  }
  return $r
}
# round to 4 decimals so no floating-point tail (812.0000000000001) reaches initialize_floorplan
proc unpu_round4 {x} { return [expr {round($x * 10000.0) / 10000.0}] }
# a checkpoint block name: UNPU_BLK_<NAME> overrides the default (letters, digits, _), with a Warning, so that several
# experiments (for example hold uncertainties: clkopt, clkopt_h02, ...) can live in one library
proc _p_blk {name default} {
  set v [_p_env UNPU_BLK_$name $default]
  if {![regexp {^[A-Za-z0-9_]+$} $v]} { _p_die "UNPU_BLK_$name='$v' may contain only letters, digits and _" }
  if {$v ne $default} { puts "Warning: \[unpu\] checkpoint block BLK_$name = $v overrides the default $default (UNPU_BLK_$name is set)" }
  return $v
}
# the floorplan consistency check, as a procedure so the local test can call it with other numbers
proc unpu_floorplan_check {die offset row_h site_w tol} {
  if {![string is double -strict $die] || $die <= 0} { _p_die "DIE_SIZE='$die' is not a positive number" }
  set core [expr {$die - 2.0 * $offset}]
  if {$core <= 0} { _p_die "core side $core um is not positive (DIE_SIZE $die, CORE_OFFSET $offset)" }
  set rows  [_p_int_or_die "core side / ROW_HEIGHT ($core / $row_h)" [expr {$core / $row_h}] $tol]
  set sites [_p_int_or_die "DIE_SIZE / SITE_WIDTH ($die / $site_w)" [expr {$die / $site_w}] $tol]
  # the core offset must be a whole number of sites (x) and of rows (y), or the core edge is off the grid
  _p_int_or_die "CORE_OFFSET / SITE_WIDTH ($offset / $site_w)" [expr {$offset / $site_w}] $tol
  _p_int_or_die "CORE_OFFSET / ROW_HEIGHT ($offset / $row_h)" [expr {$offset / $row_h}] $tol
  return [list [unpu_round4 $core] $rows $sites [unpu_round4 [expr {$core * $core}]]]
}

# ---- environment-controlled roots -------------------------------------------
# Default from docs/session-handoff.md 18.3. Never the generic non-SCL kit that cad_cshrc
# points at (docs/session-handoff.md 18.4); see pnr/README.md.
set SCL_KIT_ROOT   [_p_env SCL_KIT_ROOT /storage/PDK_iitg/SCLPDK_V3.0_KIT/scl180]
# Default work directory of the re-run (plan 2.2: library in icc2_work_v2).
set UNPU_WORK      [_p_env UNPU_WORK /storage/EE5239G1/aagams_workspace/icc2_work_v2]
set UNPU_RUN_TAG   [_p_env UNPU_RUN_TAG run1]
if {![regexp {^[A-Za-z0-9_.-]+$} $UNPU_RUN_TAG]} {
  _p_die "UNPU_RUN_TAG='$UNPU_RUN_TAG' may contain only letters, digits, _ . -"
}

# REPO_ROOT: this file lives in <repo>/pnr/, whoever sources it.
if {[info script] eq ""} { _p_die "cannot determine the location of params.tcl (info script is empty)" }
set PNR_DIR   [file dirname [file normalize [info script]]]
set REPO_ROOT [file dirname $PNR_DIR]

# ---- tool installation (handoff 18.10: the library manager must match icc2_shell) ----
# icc2_shell is U-2022.12-SP3. The bare name icc2_lm_shell finds Fusion Compiler V-2023.12-SP4,
# whose NDM may not open in the older icc2_shell.
set ICC2_VERSION   U-2022.12-SP3
set ICC2_ROOT      [_p_env UNPU_ICC2_ROOT /home/Synopsys_tools/icc2/$ICC2_VERSION]
set ICC2_LM_SHELL  $ICC2_ROOT/bin/icc2_lm_shell

# ---- directory layout (all derived) ------------------------------------------
set NDM_DIR     $UNPU_WORK/ndm                 ;# shared by all runs
set RUN_DIR     $UNPU_WORK/$UNPU_RUN_TAG
set LOG_DIR     $RUN_DIR/logs
set LIB_DIR     $RUN_DIR/lib                   ;# the design library
set OUT_DIR     $RUN_DIR/out
set RPT_DIR     $RUN_DIR/rpt
set CALIBRE_DIR $RUN_DIR/calibre

# ---- kit inputs (read-only) -------------------------------------------------
# NB the directory under stdcell/fs120/ is spelled 4M1IL (with an I); the one under
# digital_pnr_kit/snps/non_rh/ is 4M1L (handoff 18.3).
set KIT_STDCELL  $SCL_KIT_ROOT/stdcell/fs120/4M1IL
set KIT_PNR      $SCL_KIT_ROOT/digital_pnr_kit/snps/non_rh/4M1L
set TECH_FILE    $KIT_PNR/SCL_4LM.tf
set TLUPLUS_FILE $KIT_PNR/SCL_TLUPLUS_4M1L_TYP.tlup      ;# typical only (18.2)
set TLUPLUS_MAP  $KIT_PNR/SCL_TLUPLUS_4M1L.map
set GDS_LAYER_MAP_KIT $KIT_PNR/icc_gds_out_4LM.map          ;# the kit map: the only one; write_gds prints GDS-017 for its T lines (18.23)
# UNPU_GDS_LAYER_MAP replaces it with a corrected copy (outputs.tcl prints a Warning and the path lands in the manifest)
set GDS_LAYER_MAP [_p_env UNPU_GDS_LAYER_MAP $GDS_LAYER_MAP_KIT]
if {$GDS_LAYER_MAP ne $GDS_LAYER_MAP_KIT} {
  if {![file exists $GDS_LAYER_MAP]} { _p_die "UNPU_GDS_LAYER_MAP='$GDS_LAYER_MAP' does not exist" }
  puts "Warning: \[unpu\] GDS layer map overridden: $GDS_LAYER_MAP (kit map: $GDS_LAYER_MAP_KIT)"
}
set LEF_STD      $KIT_STDCELL/lef/scl18fs120_std.lef
set LIB_SS_NAME  tsl18fs120_scl_ss                       ;# library names inside the .db (18.10)
set LIB_FF_NAME  tsl18fs120_scl_ff
set LIB_DB_SS    $KIT_STDCELL/liberty/lib_flow_ss/${LIB_SS_NAME}.db
set LIB_DB_FF    $KIT_STDCELL/liberty/lib_flow_ff/${LIB_FF_NAME}.db
set STD_GDS      $KIT_STDCELL/gds/scl18fs120.gds
set CDL_SUPPLY   $KIT_STDCELL/cdl/scl18fs120_supply_pins.cdl
set CDL_NOSUPPLY $KIT_STDCELL/cdl/scl18fs120_scl_no_supply_pins.cdl

# ---- design inputs (untracked DC outputs; they exist in the user's server clone) ----
set TOP_NAME     unpu_top
set NETLIST      [_p_env UNPU_NETLIST $REPO_ROOT/syn/out/pm_flow/unpu_top_cn.dc.v]
set SDC_FILE     [_p_env UNPU_SDC     $REPO_ROOT/syn/out/pm_flow/unpu_top_cn.sdc]

# ---- names -------------------------------------------------------------------
set LIB_NAME     unpu2_lib                       ;# design library (plan 2.2)
set NDM_WS_MAIN  scl18fs120                      ;# NDM workspace of the standard cells (18.10)
set NDM_WS_FILL  scl18fs120_fillf                ;# NDM workspace of the filler cells, mode two (18.22)
# filler cells: feedth 1 site, feedth3 3 sites, feedth9 9 sites, class CORE (18.22)
set FILLER_CELLS {feedth feedth3 feedth9}
# one checkpoint block name per stage (a stage starts from the previous one and saves a new one)
set BLK_IMPORT     [_p_blk IMPORT unpu_top]
set BLK_FP         [_p_blk FP fp]
set BLK_PWR        [_p_blk PWR pwr]
set BLK_PINS       [_p_blk PINS pins]
set BLK_PLACED     [_p_blk PLACED placed]
set BLK_CTS        [_p_blk CTS cts]
set BLK_CLKOPT     [_p_blk CLKOPT clkopt]
set BLK_ROUTE_AUTO [_p_blk ROUTE_AUTO routeauto]   ;# saved right after route_auto, the fallback if route_opt goes wrong (task 044)
set BLK_ROUTED     [_p_blk ROUTED routed]
set BLK_FINAL      [_p_blk FINAL final]

# ---- floorplan (plan 2.2) ----------------------------------------------------
set PLAN_DIE_SIZE 868.0                          ;# um, the plan's die (plan 2.2); the default of DIE_SIZE
set DIE_SIZE     [_p_env UNPU_DIE_SIZE $PLAN_DIE_SIZE]   ;# um, square die
set CORE_OFFSET  5.6                             ;# um, die edge to core edge (18.14)
set ROW_HEIGHT   5.6                             ;# um, site 'unit' 0.56 x 5.6 (18.14)
set SITE_WIDTH   0.56                            ;# um
set FP_TOLERANCE 1e-6                            ;# tolerance of the integer tests below
foreach {CORE_SIDE FP_ROWS FP_SITES_ACROSS CORE_AREA} \
    [unpu_floorplan_check $DIE_SIZE $CORE_OFFSET $ROW_HEIGHT $SITE_WIDTH $FP_TOLERANCE] {}
# boundary for initialize_floorplan: the CORE rectangle; -core_offset then adds the margin
# (18.14: giving the die as the boundary made a bigger die)
set _p_hi [unpu_round4 [expr {$DIE_SIZE - $CORE_OFFSET}]]
set FP_BOUNDARY [list [list [unpu_round4 $CORE_OFFSET] [unpu_round4 $CORE_OFFSET]] [list $_p_hi $_p_hi]]
puts [format "Info: \[unpu\] floorplan: die %s um, core side %.1f um, %d rows, %d sites across the die, core area %.2f um2, boundary %s" \
        $DIE_SIZE $CORE_SIDE $FP_ROWS $FP_SITES_ACROSS $CORE_AREA $FP_BOUNDARY]

# ---- timing ------------------------------------------------------------------
# Hold uncertainty applied in scenario ff_hold from CTS on. Plan: back to the value of
# constraints/unpu_top.sdc. The SDC labels it an assumption; the user chose it on 2026-11-01.
# The first run applied 0.2 (18.18). No setup parameter: it stays 1.5 in the SDC.
set PLAN_HOLD_UNCERT 0.5                         ;# ns, the plan's value; the default of HOLD_UNCERT
set HOLD_UNCERT  [_p_env UNPU_HOLD_UNCERT $PLAN_HOLD_UNCERT]   ;# ns
if {![string is double -strict $HOLD_UNCERT] || $HOLD_UNCERT < 0} {
  _p_die "HOLD_UNCERT='$HOLD_UNCERT' must be a number >= 0 (ns)"
}
# an experiment run must be visible in the log
if {abs($DIE_SIZE - $PLAN_DIE_SIZE) > 1e-9} {
  puts "Warning: \[unpu\] DIE_SIZE = $DIE_SIZE differs from the plan default $PLAN_DIE_SIZE (UNPU_DIE_SIZE is set): this is an experiment run"
}
if {abs($HOLD_UNCERT - $PLAN_HOLD_UNCERT) > 1e-9} {
  puts "Warning: \[unpu\] HOLD_UNCERT = $HOLD_UNCERT differs from the plan default $PLAN_HOLD_UNCERT (UNPU_HOLD_UNCERT is set): this is an experiment run"
}

# ---- don't-use (ONE line, exact form: same list as syn/dc_setup.tcl:39) ------
set DONT_USE_PATTERNS {slnht* skbrb* slbhb* slnhn* slnln* mx08d*}
# Three more cells are flagged dont_use by the library itself (18.15): adiode (antenna diode,
# cannot be used: user decision 2026-11-01, the flag cannot be overridden), bh01d1 (bus
# holder), cload1 (load cell).
set LIB_DONT_USE_CELLS {adiode bh01d1 cload1}
# After the dont_use attribute is set (set_attribute; set_dont_use is not a command here) on the patterns above the first run counted 18 cells with dont_use==true (18.15):
# 15 matched by our patterns (3 each for slnht*, skbrb*, slbhb*, slnhn*, slnln*) + adiode, bh01d1, cload1
# flagged by the library itself.
set EXPECT_DONT_USE_MATCHED 15   ;# cells matched by DONT_USE_PATTERNS (18.15)
set EXPECT_DONT_USE_COUNT   18   ;# all cells with dont_use==true after the attribute is set (18.15)
# patterns that may legitimately match nothing: mx08d1/2/4 have no timing view and are not in the NDM (18.15)
set DONT_USE_EXPECT_EMPTY {mx08d*}
set SITE_NAME unit               ;# the site of the rows, 0.56 x 5.6 um (18.14)

# ---- power grid (18.15, 18.21) -----------------------------------------------
set PG_RAIL_LAYER    M1       ;# standard-cell rails
set PG_RAIL_WIDTH    0.74     ;# um, from the LEF (inv0d0: VDD y 4.86-5.60, VSS y 0-0.74)
set PG_STRIPE_LAYER  TOP_M    ;# vertical stripes
set PG_STRIPE_WIDTH  2.24     ;# um
set PG_STRIPE_PITCH  112      ;# um (= 100 TOP_M tracks); VDD/VSS interleaved
set PG_PIN_HEIGHT    6.0      ;# um, height of the extension shape at the bottom boundary (18.21)
set PG_PIN_BOTTOM_Y  0.0      ;# um, y of the bottom die boundary where the extension shapes start (18.21: {{x1 0} {x2 6.0}})
set PG_NET_POWER     VDD      ;# create_net -power (18.14)
set PG_NET_GROUND    VSS      ;# create_net -ground (18.14)
set PG_PATTERN_RAIL  std_rail ;# create_pg_std_cell_conn_pattern name (18.15)
set PG_PATTERN_MESH  top_mesh ;# create_pg_mesh_pattern name (18.15)
set PG_STRAT_RAIL    s_rail   ;# set_pg_strategy name for the rails (18.15)
set PG_STRAT_MESH    s_mesh   ;# set_pg_strategy name for the stripes (18.15)
set PG_SPACING       interleaving   ;# stripe spacing mode: VDD/VSS alternate (18.15)
set PG_STRIPE_SHAPE_USE stripe      ;# shape_use of the TOP_M stripes (18.21 queries shape_use==stripe)
set PG_RAIL_SHAPE_USE   follow_pin  ;# shape_use of the M1 rails: a GUESS, VERIFY on the server (power.tcl falls back to the layer alone, with a Warning)
set PG_TOLERANCE     0.001    ;# um, tolerance of the geometry comparisons (one database unit at 1000 per um)

# ---- signal pins (plan 2.2) --------------------------------------------------
set PIN_WIDTH        0.28     ;# um
set PIN_LENGTH       1.0      ;# um
set PIN_PITCH        6.72     ;# um, minimum
set PIN_LAYER_RIGHT  M3
set PIN_LAYER_TOP    M2
set PIN_PORTS_RIGHT  {paddr[*] pwdata[*] prdata[*] pwrite psel penable pready clk rst_n}
set PIN_PORTS_TOP    {dma_addr[*] dma_wdata[*] dma_rdata[*] dma_wstrb[*] dma_valid dma_ready}
# Side numbers of set_individual_pin_constraints -sides. The usage text (set_individual_pin_constraints.txt) does not say which integer
# is which edge. THE DEFAULTS ARE A GUESS: clockwise from the left edge, 1 left, 2 top, 3 right, 4 bottom. pin_place.tcl measures where the
# pins really land and, if a group is on the wrong edge, names the edge and the numbers to try. Override: UNPU_PIN_SIDE_RIGHT / UNPU_PIN_SIDE_TOP.
set PIN_SIDE_RIGHT [_p_env UNPU_PIN_SIDE_RIGHT 3]
set PIN_SIDE_TOP   [_p_env UNPU_PIN_SIDE_TOP 2]
foreach {_v _n} [list $PIN_SIDE_RIGHT UNPU_PIN_SIDE_RIGHT $PIN_SIDE_TOP UNPU_PIN_SIDE_TOP] {
  if {![string is integer -strict $_v] || $_v < 1} { _p_die "$_n='$_v' must be a positive integer (a side number of the pin placer)" }
}
if {$PIN_SIDE_RIGHT == $PIN_SIDE_TOP} { _p_die "UNPU_PIN_SIDE_RIGHT and UNPU_PIN_SIDE_TOP are both $PIN_SIDE_RIGHT; the two groups need different sides" }
if {$PIN_SIDE_RIGHT != 3 || $PIN_SIDE_TOP != 2} { puts "Warning: \[unpu\] pin side numbers overridden: right group side $PIN_SIDE_RIGHT, top group side $PIN_SIDE_TOP (defaults 3 and 2 are a guess)" }
# a plain safety margin, not a rule of the kit: no signal pin within two pitches of a corner (the pin placer keeps its own keep-out too)
set PIN_CORNER_KEEPOUT_UM [expr {2 * $PIN_PITCH}]
set PIN_TOLERANCE_UM 0.005   ;# um, tolerance of the pin geometry checks (a few database units at 1000 per um)

# ---- placement (task 049) ------------------------------------------------------------------
set PLACE_OPT_STAGES {initial_place initial_drc initial_opto final_place final_opto}   ;# place_opt -list_only (usage text, 18.16)
# the smallest gate area ICC2 itself printed in the first run's antenna listing (18.25/18.26); used when a load's gate area cannot be read
set MIN_GATE_AREA 0.108   ;# um2
# weight of the top metal in the Calibre antenna deck, rule AN.MTL.1.MT: perimeter * 0.84 / gate area (handoff 18.27); the worst case
set ANT_WEIGHT_TOP 0.84
set PORT_REPORT_LONG_UM 50   ;# input-port nets with an HPWL above this are counted as long (the first run's worst, paddr[4], was 180 um)
# attribute names tried, in this order, for the gate area of a load pin (GUESSES: the usage texts do not list attributes; VERIFY on the server)
set GATE_AREA_ATTRS {antenna_gate_area gate_area}

# ---- clock tree --------------------------------------------------------------
set CTS_EXCLUDE_PATTERN */dl*   ;# the 12 delay cells, kept for hold fixing (plan C1)
set EXPECT_CTS_EXCLUDED 12      ;# cells matched by CTS_EXCLUDE_PATTERN: dl01..dl04 x d1/d2/d4 (18.17); a different count is a Warning
# cts.tcl stage: all = tree then hold optimisation; tree = build the tree, save $BLK_CTS, stop; hold = open $BLK_CTS, apply
# the hold uncertainty, optimise, save $BLK_CLKOPT (task 044)
set CTS_STAGE [_p_env UNPU_CTS_STAGE all]
if {[lsearch -exact {all tree hold} $CTS_STAGE] < 0} { _p_die "UNPU_CTS_STAGE='$CTS_STAGE' is not allowed; it must be all, tree or hold" }
set CTS_BUILD_TO   build_clock  ;# clock_opt -to <stage>: builds the clock tree (18.17)
set CTS_OPT_FROM   route_clock  ;# clock_opt -from <stage>: detail-routes the clock nets (18.17, 18.18)
set CTS_OPT_TO     final_opto   ;# clock_opt -to <stage>: post-CTS optimisation incl. hold (18.18)
set FLW_INCOMPLETE_ID FLW-8004  ;# "Incomplete clock_opt / final_opto" (18.18); counted and reported, not an error
# INFORMATIVE reference values of the first run's tree (18.17); used in comments and RESULT lines only, never in a check
set EXPECT_CTS_LEVELS    3
set EXPECT_CTS_REPEATERS 53
set TIMING_MAX_PATHS 100000     ;# report_timing -max_paths used to count violating endpoints (the first 0.5 ns run started with 2,219)
set HOLD_ENDPOINTS_LISTED 10    ;# worst hold endpoints quoted in the Warning

# ---- antenna (plan 2.3 D3) ---------------------------------------------------
set ANT_MODE          4
set ANT_DIODE_MODE    1
set ANT_CUT_RATIO     0
set ANT_RATIO         300     ;# ICC2 metal ratio on all layers. Stricter than Calibre's limit
                               ;# (ANT_CALIBRE_LIMIT) because ICC2 and Calibre agreed within about 2%
                               ;# on M2/M3 (395 against 402) and the top-metal weight is unverified
                               ;# in ICC2 (plan 2.3 D3)
set ANT_CALIBRE_LIMIT 400     ;# informational: the limit used by the Calibre deck
set HPWL_DETOUR       1.2     ;# route length / HPWL factor of the port-net estimate (plan B6)

# route.tcl: 1 = save the routed block although hold violations remain (the hold check only; default 0)
set ROUTE_ACCEPT_HOLD [_p_env UNPU_ROUTE_ACCEPT_HOLD 0]
if {[lsearch -exact {0 1} $ROUTE_ACCEPT_HOLD] < 0} { _p_die "UNPU_ROUTE_ACCEPT_HOLD='$ROUTE_ACCEPT_HOLD' must be 0 or 1" }
if {$ROUTE_ACCEPT_HOLD eq "1"} { puts "Warning: \[unpu\] UNPU_ROUTE_ACCEPT_HOLD=1: route.tcl will save the routed block even if hold violations remain (give a written reason)" }
set ROUTE_WIRE_LAYERS {M1 M2 M3 TOP_M}   ;# metal layers of the routing summary (18.20)
set ROUTE_VIA_LAYERS  {V2 V3 TOP_V}      ;# via layers of the routing summary (18.20)
set ROUTE_ANTENNA_OPTION_PATTERN route.detail.antenna*   ;# application options printed before routing (18.25 names route.detail.antenna_fixing_preference)
# The router fixes antenna violations only if this boolean application option is on. route.tcl reads it after define_antenna_rule
# and prints a loud Warning for anything but true (task 044 follow-up; the option name is Planning's, VERIFY with the help probe).
set ROUTE_ANTENNA_ENABLE_OPTION route.detail.antenna

# ---- fill --------------------------------------------------------------------
set FILLER_PATTERN */feedth*
set FILLER_PREFIX  FILLER
set FILLER_SITES   {feedth 1 feedth3 3 feedth9 9}   ;# sites (0.56 um) covered by one filler of each cell (18.22: 0.56, 1.68, 5.04 um)
set FILL_RULES     post_route_auto_delete           ;# the only create_stdcell_fillers option beyond -lib_cells and -prefix (18.22)
set FILL_COVERAGE_TOL_SITES 2                       ;# the filler sites may differ from the free sites by this much (task 045; 18.22 was exact)
# Decision of 2026-10-29 (docs/session-handoff.md 18.22, option A): a hold residual caused by the filler capacitance that is not
# worse than this (ns, i.e. one picosecond) is accepted with a Warning and a manifest line; PrimeTime judges it. Larger fails.
set FILL_HOLD_TOLERANCE_NS 0.001
# ... and it may cover at most this many endpoints (the decision accepted ONE path; more is a CHECK FAIL: task 046 A2, review of 045)
set FILL_HOLD_MAX_ENDPOINTS 10
# 1 lets fill.tcl run route_eco ONCE when fillers with violations remain (18.22 fixed its one real violation that way); default 0
set FILL_ECO [_p_env UNPU_FILL_ECO 0]
if {[lsearch -exact {0 1} $FILL_ECO] < 0} { _p_die "UNPU_FILL_ECO='$FILL_ECO' must be 0 or 1" }
if {$FILL_ECO eq "1"} { puts "Warning: \[unpu\] UNPU_FILL_ECO=1: fill.tcl will run route_eco once if fillers with violations remain" }
# first run (18.22), reference only, never used in a check: 22,512 fillers = 4,159 feedth9 + 7,451 feedth3 + 10,902 feedth
# on a 144-row, 1,440-site core; 45,024 power/ground pins connected
set EXPECT_FILLER_REF_FEEDTH9 4159
set EXPECT_FILLER_REF_FEEDTH3 7451
set EXPECT_FILLER_REF_FEEDTH  10902

# ---- outputs -----------------------------------------------------------------
# GDS database units. The Calibre rule precision is 1000; without it the deck stops with a
# precision error (18.23).
set GDS_UNITS      1000
set GDS_UNITS_REL_TOL 1e-6   ;# relative tolerance of the UNITS check (GDSII reals are base-16 floats, not exact)
set OUT_PREFIX     unpu_top  ;# file prefix of every output (18.23: unpu_top_sim.v ...); the top module and the macro are TOP_NAME
# modules in the netlists written by write_verilog -hierarchy all: 76 in the first run (18.23); place_opt did not change the
# module count there. A different hierarchy (RTL change) changes it: then this is a plan change, not a script fix.
set EXPECT_NETLIST_MODULES 76
# 1 lets outputs.tcl replace output files that exist (a Warning per file; they are deleted first so that a stale file can never pass the checks)
set OUTPUTS_OVERWRITE [_p_env UNPU_OUTPUTS_OVERWRITE 0]
if {[lsearch -exact {0 1} $OUTPUTS_OVERWRITE] < 0} { _p_die "UNPU_OUTPUTS_OVERWRITE='$OUTPUTS_OVERWRITE' must be 0 or 1" }
if {$OUTPUTS_OVERWRITE eq "1"} { puts "Warning: \[unpu\] UNPU_OUTPUTS_OVERWRITE=1: outputs.tcl will delete and rewrite existing output files" }
# smallest plausible size in bytes per kind of file: well below the first run (18.23: LEF 56,524 B, SPEF 25.7 MB each, SDF 8.3 MB /
# 8.8 MB, GDS 15.7 MB) and far above the 163-byte empty LEF shell that a missing frame view gave. Netlist and SDC sizes were not
# recorded in the handoff: the values are floors for a 12k-cell design, not measurements.
set OUT_MIN_BYTES {verilog 10000 lef 10000 spef 1000000 sdf 1000000 sdc 1000 gds 1000000}

# ---- expected facts (checks, not inputs) ------------------------------------
set EXPECT_TIMING_CELLS 534   ;# cells of the ss/ff .lib = cells of the first NDM (18.10)
set EXPECT_LEF_MACROS   540   ;# MACROs in scl18fs120_std.lef (18.10)
set EXPECT_PORTS        204   ;# top-level ports of unpu_top (18.12)
set EXPECT_SEQ_CELLS    2465  ;# sequential cells of the DC netlist (18.12)
set EXPECT_ROWS         $FP_ROWS   ;# derived above (153 at the default die)
set EXPECT_LEAF_CELLS   12487 ;# leaf cells (is_hierarchical==false) of the DC netlist (18.14)
set EXPECT_SDC_IGNORED  {SDC-3 SDC-4}   ;# set_wire_load_model and set_max_area, "not supported by icc2" (18.12)
set EXPECT_CHECK_TIMING_WARNINGS 1      ;# check_timing: only pready, unconstrained constant (18.13, rtl/unpu_apb.sv:87)
set EXPECT_SS_VOLT      1.62  ;# V, ss library tsl18fs120_scl_ss (18.2)
set EXPECT_SS_TEMP      125   ;# C
set EXPECT_FF_VOLT      1.98  ;# V, ff library tsl18fs120_scl_ff (18.2)
set EXPECT_FF_TEMP      -40   ;# C

# ---- corners, scenarios, parasitics (18.13) ----------------------------------
# read_sdc creates one mode, corner and scenario all named default; the shell has no rename
# command, so default is kept as the ss (setup) scenario and an ff corner/scenario is added.
set MODE_NAME     default
set CORNER_SETUP  default
set CORNER_HOLD   ff
set SCEN_SETUP    default
set SCEN_HOLD     ff_hold
set PARA_TECH_NAME typ    ;# read_parasitic_tech -name; only a typical TLUPlus exists (18.2)

# ---- command-usage probe (task 042): what pnr/help_probe*.tcl asks the tools -----------------
# Every tool command that carries a VERIFY comment in pnr/*.tcl is in these lists, plus the commands the
# next scripts (pin placement, placement, CTS, routing, fill, outputs) will need.
# (set_dont_use is in the list below and came back NOT_FOUND: it is not a command in this release; task 047. get_app_option_value and
# report_constraint were not in the first list: add them to the next probe.)
set PROBE_COMMANDS_ICC2 {
  create_lib open_lib close_lib save_lib open_block save_block close_blocks get_blocks current_block
  current_lib report_ref_libs read_parasitic_tech read_verilog link_block read_sdc create_corner create_scenario
  current_scenario set_scenario_status set_operating_conditions set_parasitic_parameters report_corners report_scenarios
  report_parasitic_parameters check_timing get_timing_paths report_timing report_qor report_design report_utilization
  initialize_floorplan get_site_rows get_site_defs set_dont_use get_lib_cells get_attribute set_attribute
  create_net connect_pg_net create_pg_std_cell_conn_pattern create_pg_mesh_pattern set_pg_strategy compile_pg
  check_pg_drc check_pg_connectivity create_shape create_terminal get_terminals get_shapes remove_terminals remove_shapes
  set_block_pin_constraints set_individual_pin_constraints place_pins create_placement place_opt legalize_placement
  check_legality refine_placement set_app_options get_app_options report_app_options set_lib_cell_purpose clock_opt
  set_clock_uncertainty report_clock_qor report_clock_timing route_auto route_global route_track route_detail route_opt
  route_eco check_routes check_lvs define_antenna_rule remove_routes set_routing_rule create_stdcell_fillers
  remove_stdcell_fillers_with_violation create_frame write_lef write_verilog write_parasitics write_sdf write_sdc
  write_gds add_port_protection_diodes report_port_protection_diodes insert_buffer create_cell index_collection
  redirect foreach_in_collection sizeof_collection
  get_app_option_value report_constraint report_pin_placement check_pin_placement report_pin_constraints
  report_individual_pin_constraints report_block_pin_constraints remove_individual_pin_constraints report_placement
  get_libs get_object_name get_nets get_pins get_ports get_cells get_scenarios set_app_var get_app_var printvar report_units
}
# commands whose names are not known: help <pattern> lists the commands that match (help *protection_diode* worked in the first run)
set PROBE_WILDCARDS_ICC2 {
  *pin* *place* *cts* *clock* *route* *routing* *antenna* *diode* *filler* *frame* *write_* *buffer* *terminal*
  *scenario* *site* *floorplan* *hold* *uncertainty* *lef* *gds* *parasitic*
}
# application options: report_app_options <pattern> (or get_app_options)
set PROBE_APPOPT_PATTERNS_ICC2 {
  place.* place_opt.* clock_opt.* cts.* opt.* route.common.* route.global.* route.track.* route.detail.*
  *hold* *antenna* *pin* *port* time.*
}
# the library manager (icc2_lm_shell): the commands ndm_file_gen.tcl uses, plus helpers it relies on
set PROBE_COMMANDS_LM {
  create_workspace read_lef read_db read_lib check_workspace commit_workspace set_attribute get_lib_cells get_cells
  report_workspace remove_workspace get_object_name foreach_in_collection sizeof_collection redirect set_app_var get_app_var printvar
}
set PROBE_WILDCARDS_LM {*workspace* *lef* *db* *lib* *attribute* *filler*}

# ---- NDM generation mode -----------------------------------------------------
# single: filler cells are put into the same NDM as the 534 timing cells (the goal).
# two:    the main NDM as in the first run plus a second, physical-only NDM for the fillers.
set NDM_MODE [_p_env UNPU_NDM_MODE two]   ;# two: the fillers in a second NDM. single does NOT work on this kit (LM-052, 0 of 3 fillers: task 047)
if {[lsearch -exact {single two} $NDM_MODE] < 0} {
  _p_die "UNPU_NDM_MODE='$NDM_MODE' is not allowed; it must be single or two"
}

# ---- computed list of parameter names (for the run manifest) ----------------
if {[info exists _p_before]} {
  set UNPU_PARAM_NAMES {}
  foreach _p_v [lsort [info globals]] {
    if {[lsearch -exact $_p_before $_p_v] >= 0} continue
    if {[string match _p_* $_p_v]} continue
    if {$_p_v eq "UNPU_PARAM_NAMES"} continue
    lappend UNPU_PARAM_NAMES $_p_v
  }
  unset _p_before
  catch {unset _p_v}
  catch {unset _p_hi}
}
