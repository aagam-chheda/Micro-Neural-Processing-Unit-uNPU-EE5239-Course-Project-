# ==============================================================================
# Script: fix_antenna.tcl
# Path  : /storage/EE5239G2/RFID_v2/pnr_icc2/TCL_pnr/fix_antenna.tcl
# Stage : Universal Coordinate-Based Upward Antenna Hopping (M1, M2, M3 & TOP_M)
# Tool  : Synopsys ICC2 (U-2022.12-SP3)
# ==============================================================================

set DESIGN_NAME "baseband_crypto_macro"
set PNR_DIR     "/storage/EE5239G2/RFID_v2/pnr_icc2"
set BLOCKS_DIR  "${PNR_DIR}/blocks"
set LOG_DIR     "${PNR_DIR}/logs"
set ANT_DB      "/storage/EE5239G2/project/pv/drc/baseband_crypto_macro_antenna_bkp.db"

file mkdir $LOG_DIR

redirect -tee -file ${LOG_DIR}/fix_antenna.log {

    set open_blk [get_blocks -quiet *]
    if {[sizeof_collection $open_blk] > 0} {
        close_blocks -force $open_blk
    }
    set open_lib [get_libs -quiet *]
    if {[sizeof_collection $open_lib] > 0} {
        foreach_in_collection lib_obj $open_lib {
            close_lib -force $lib_obj
        }
    }

    open_lib ${BLOCKS_DIR}/${DESIGN_NAME}.dlib
    open_block ${DESIGN_NAME}.dlib:${DESIGN_NAME}_route
    current_block ${DESIGN_NAME}_route
    link_block

    # Allow clock nets (from CTS) to hop up to TOP_M
    set_clock_routing_rules \
        -default_rule \
        -min_routing_layer M2 \
        -max_routing_layer TOP_M

    if {![file exists $ANT_DB]} {
        error "ERROR: Cannot find Calibre antenna DB at $ANT_DB"
    }

    set fp [open $ANT_DB r]
    set lines [split [read $fp] "\n"]
    close $fp

    set cur_rule ""
    set i 0
    set blk_count 0
    set nets_to_reroute ""

    while {$i < [llength $lines]} {
        set line [string trim [lindex $lines $i]]
        if {[regexp {^(AN\.[A-Z0-9.]+)} $line -> rname]} {
            set cur_rule $rname
            incr i
            continue
        }
        if {[regexp {^p\s+([0-9]+)\s+([0-9]+)} $line -> pnum nverts]} {
            set xs {}
            set ys {}
            for {set v 0} {$v < $nverts} {incr v} {
                incr i
                set vline [string trim [lindex $lines $i]]
                if {[regexp {^([0-9-]+)\s+([0-9-]+)} $vline -> x_dbu y_dbu]} {
                    lappend xs [expr {$x_dbu / 1000.0}]
                    lappend ys [expr {$y_dbu / 1000.0}]
                }
            }
            if {[llength $xs] > 0} {
                set xs_s [lsort -real $xs]
                set ys_s [lsort -real $ys]
                set xmin [lindex $xs_s 0]
                set xmax [lindex $xs_s end]
                set ymin [lindex $ys_s 0]
                set ymax [lindex $ys_s end]
                set dx [expr {$xmax - $xmin}]
                set dy [expr {$ymax - $ymin}]

                # Determine which layer violated in Calibre (M1, M2, M3, or TOP_M)
                set target_lyr ""
                if {[string match "*.M1" $cur_rule]} {
                    set target_lyr "M1"
                } elseif {[string match "*.M2" $cur_rule]} {
                    set target_lyr "M2"
                } elseif {[string match "*.M3" $cur_rule]} {
                    set target_lyr "M3"
                } elseif {[string match "*.MT" $cur_rule]} {
                    set target_lyr "TOP_M"
                }

                if {$target_lyr ne ""} {
                    # Locate the violating net inside the polygon bounding box
                    set search_box [list [list [expr {$xmin - 0.1}] [expr {$ymin - 0.1}]] [list [expr {$xmax + 0.1}] [expr {$ymax + 0.1}]]]
                    set sh [get_shapes -quiet -within $search_box -filter "layer.name == $target_lyr"]
                    if {[sizeof_collection $sh] == 0} {
                        set sh [get_shapes -quiet -intersect $search_box -filter "layer.name == $target_lyr"]
                    }
                    if {[sizeof_collection $sh] == 0} {
                        set sh [get_shapes -quiet -intersect $search_box]
                    }
                    set vnet [get_nets -quiet -of_objects $sh -filter "net_type == signal || net_type == clock"]
                    if {[sizeof_collection $vnet] > 0} {
                        puts ">>> Fixing $cur_rule ($target_lyr) #$pnum on net [get_object_name $vnet] bbox=($xmin,$ymin)->($xmax,$ymax)"
                        append_to_collection -unique nets_to_reroute $vnet
                        # Unlock shapes/vias in case it is a CTS clock net
                        set_attribute -quiet -objects [get_shapes -quiet -of_objects $vnet] -name physical_status -value unrestricted
                        set_attribute -quiet -objects [get_vias -quiet -of_objects $vnet]   -name physical_status -value unrestricted
                    }

                    # ----------------------------------------------------------
                    # 1. M1 Violation (AN.MTL.1.M1 / AN.MTL.2.M1)
                    #    Block {M1} every 25um -> forces upward hop to M2/M3
                    # ----------------------------------------------------------
                    if {$target_lyr eq "M1"} {
                        if {$dx >= $dy} {
                            set x_cur [expr {$xmin + 12.0}]
                            if {$x_cur > [expr {$xmax - 2.0}]} { set x_cur [expr {($xmin + $xmax)/2.0 - 0.7}] }
                            while {$x_cur < [expr {$xmax - 2.0}]} {
                                create_routing_blockage -layers {M1} -name_prefix ant_fix_blk_ \
                                    -boundary [list [list $x_cur [expr {$ymin-0.15}]] [list [expr {$x_cur+1.4}] [expr {$ymax+0.15}]]]
                                incr blk_count
                                set x_cur [expr {$x_cur + 25.0}]
                            }
                        } else {
                            set y_cur [expr {$ymin + 12.0}]
                            if {$y_cur > [expr {$ymax - 2.0}]} { set y_cur [expr {($ymin + $ymax)/2.0 - 0.7}] }
                            while {$y_cur < [expr {$ymax - 2.0}]} {
                                create_routing_blockage -layers {M1} -name_prefix ant_fix_blk_ \
                                    -boundary [list [list [expr {$xmin-0.15}] $y_cur] [list [expr {$xmax+0.15}] [expr {$y_cur+1.4}]]]
                                incr blk_count
                                set y_cur [expr {$y_cur + 25.0}]
                            }
                        }
                    }

                    # ----------------------------------------------------------
                    # 2. M2 Violation (AN.MTL.1.M2 / AN.MTL.2.M2)
                    #    Block {M1 M2} every 25um -> forces upward hop to M3/TOP_M
                    # ----------------------------------------------------------
                    if {$target_lyr eq "M2"} {
                        if {$dy >= $dx} {
                            set y_cur [expr {$ymin + 12.0}]
                            if {$y_cur > [expr {$ymax - 2.0}]} { set y_cur [expr {($ymin + $ymax)/2.0 - 0.7}] }
                            while {$y_cur < [expr {$ymax - 2.0}]} {
                                create_routing_blockage -layers {M1 M2} -name_prefix ant_fix_blk_ \
                                    -boundary [list [list [expr {$xmin-0.15}] $y_cur] [list [expr {$xmax+0.15}] [expr {$y_cur+1.4}]]]
                                incr blk_count
                                set y_cur [expr {$y_cur + 25.0}]
                            }
                        } else {
                            set x_cur [expr {$xmin + 12.0}]
                            if {$x_cur > [expr {$xmax - 2.0}]} { set x_cur [expr {($xmin + $xmax)/2.0 - 0.7}] }
                            while {$x_cur < [expr {$xmax - 2.0}]} {
                                create_routing_blockage -layers {M1 M2} -name_prefix ant_fix_blk_ \
                                    -boundary [list [list $x_cur [expr {$ymin-0.15}]] [list [expr {$x_cur+1.4}] [expr {$ymax+0.15}]]]
                                incr blk_count
                                set x_cur [expr {$x_cur + 25.0}]
                            }
                        }
                    }

                    # ----------------------------------------------------------
                    # 3. M3 Violation (AN.MTL.1.M3 / AN.MTL.2.M3)
                    #    Block {M1 M2 M3} every 25um -> forces upward hop to TOP_M
                    # ----------------------------------------------------------
                    if {$target_lyr eq "M3"} {
                        if {$dx >= $dy} {
                            set x_cur [expr {$xmin + 12.0}]
                            if {$x_cur > [expr {$xmax - 2.0}]} { set x_cur [expr {($xmin + $xmax)/2.0 - 0.7}] }
                            while {$x_cur < [expr {$xmax - 2.0}]} {
                                create_routing_blockage -layers {M1 M2 M3} -name_prefix ant_fix_blk_ \
                                    -boundary [list [list $x_cur [expr {$ymin-0.15}]] [list [expr {$x_cur+1.4}] [expr {$ymax+0.15}]]]
                                incr blk_count
                                set x_cur [expr {$x_cur + 25.0}]
                            }
                        } else {
                            set y_cur [expr {$ymin + 12.0}]
                            if {$y_cur > [expr {$ymax - 2.0}]} { set y_cur [expr {($ymin + $ymax)/2.0 - 0.7}] }
                            while {$y_cur < [expr {$ymax - 2.0}]} {
                                create_routing_blockage -layers {M1 M2 M3} -name_prefix ant_fix_blk_ \
                                    -boundary [list [list [expr {$xmin-0.15}] $y_cur] [list [expr {$xmax+0.15}] [expr {$y_cur+1.4}]]]
                                incr blk_count
                                set y_cur [expr {$y_cur + 25.0}]
                            }
                        }
                    }

                    # ----------------------------------------------------------
                    # 4. TOP_M Violation (AN.MTL.1.MT / AN.MTL.2.MT)
                    #    Block {TOP_M} over the long span (pushes wire to M2)
                    #    and block {M1 M2} every 25um so M2 hops UP to M3
                    # ----------------------------------------------------------
                    if {$target_lyr eq "TOP_M"} {
                        set by1 [expr {$ymin + 4.0}]
                        set by2 [expr {$ymax - 4.0}]
                        if {$by2 <= $by1} {
                            set by1 $ymin
                            set by2 $ymax
                        }
                        create_routing_blockage -layers {TOP_M} -name_prefix ant_fix_blk_ \
                            -boundary [list [list [expr {$xmin-0.2}] $by1] [list [expr {$xmax+0.2}] $by2]]
                        incr blk_count

                        set y_cur [expr {$ymin + 15.0}]
                        while {$y_cur < [expr {$ymax - 4.0}]} {
                            create_routing_blockage -layers {M1 M2} -name_prefix ant_fix_blk_ \
                                -boundary [list [list [expr {$xmin-0.8}] $y_cur] [list [expr {$xmax+0.8}] [expr {$y_cur+1.4}]]]
                            incr blk_count
                            set y_cur [expr {$y_cur + 25.0}]
                        }
                    }
                }
            }
        }
        incr i
    }

    puts ">>> Created $blk_count surgical antenna blockages across [sizeof_collection $nets_to_reroute] violating nets."

    # Rip-up and ECO-route ONLY the violating nets so they hop around the surgical blockages
    if {[sizeof_collection $nets_to_reroute] > 0} {
        remove_routes -nets $nets_to_reroute -detail_route
        route_eco \
            -nets $nets_to_reroute \
            -reuse_existing_global_route false \
            -reroute modified_nets_first_then_others \
            -max_detail_route_iterations 60
    }

    # Remove the temporary surgical routing blockages and clean up any minor DRCs
    set temp_blks [get_routing_blockages -quiet ant_fix_blk_*]
    if {[sizeof_collection $temp_blks] > 0} {
        remove_routing_blockages $temp_blks
    }

    route_eco \
        -open_net_driven true \
        -reuse_existing_global_route true \
        -reroute modified_nets_first_then_others \
        -max_detail_route_iterations 40
    route_detail -incremental true -max_number_iterations 40
    check_routes

    # Overwrite the existing _route block in-place so metal_fill.tcl reads it directly
    save_block
    save_block -force -as ${DESIGN_NAME}_route
    save_lib
    puts ">>> UNIVERSAL SURGICAL ANTENNA FIX (M1/M2/M3/TOP_M) COMPLETE! Now run metal_fill.tcl and pv.tcl."
}