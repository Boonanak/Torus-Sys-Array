# Core rings
# Outer rings
set_db add_rings_target default  \
; set_db add_rings_extend_over_row 0 ; set_db add_rings_ignore_rows 0 ; set_db add_rings_avoid_short 0  \
; set_db add_rings_skip_shared_inner_ring none ; set_db add_rings_stacked_via_top_layer METAL5  \
; set_db add_rings_stacked_via_bottom_layer METAL1 ; set_db add_rings_via_using_exact_crossover_size 1  \
; set_db add_rings_orthogonal_only true ; set_db add_rings_skip_via_on_pin { standardcell }  \
; set_db add_rings_skip_via_on_wire_shape { noshape }
add_rings -nets {VDD VSS} -type core_rings -follow core  \
-layer {top METAL5 bottom METAL5 left METAL6 right METAL6}  \
-width {top 6 bottom 6 left 6 right 6}  \
-spacing {top 3 bottom 3 left 3 right 3}  \
-offset {top 8 bottom 8 left 8 right 8}  \
-center 0 -threshold 0 -jog_distance 0 -snap_wire_center_to_grid none

# Power pad pins
set_db route_special_via_connect_to_shape { ring } 
route_special -connect {pad_pin} -layer_change_range { METAL1(1) METAL6(6) }  \
-pad_pin_port_connect {all_port} -pad_pin_target {ring} -allow_jogging 0  \
-crossover_via_layer_range { METAL1(1) METAL6(6) } -nets { VDD VSS }  \
-allow_layer_change 1 -target_via_layer_range { METAL1(1) METAL6(6) }

# Inner rings
# addRing -skip_via_on_wire_shape Noshape \
#    -skip_via_on_pin Standardcell \
#    -type core_rings -jog_distance 0.045 \
#    -threshold 0.045 -nets {VDD VSS} -follow core -stacked_via_bottom_layer METAL1 \
#    -layer {bottom M3 top M3 right M4 left M4} -stacked_via_top_layer METAL5 \
#    -width 1.44 -spacing 1

# Stripes
set_db add_stripes_ignore_block_check false  \
; set_db add_stripes_break_at none \
; set_db add_stripes_route_over_rows_only false  \
; set_db add_stripes_rows_without_stripes_only false \
; set_db add_stripes_extend_to_closest_target none \
; set_db add_stripes_stop_at_last_wire_for_area false  \
; set_db add_stripes_partial_set_through_domain false \
; set_db add_stripes_ignore_non_default_domains false \
; set_db add_stripes_trim_antenna_back_to_shape none  \
; set_db add_stripes_spacing_type edge_to_edge \
; set_db add_stripes_spacing_from_block 0  \
; set_db add_stripes_stacked_via_top_layer METAL6 \
; set_db add_stripes_stacked_via_bottom_layer METAL1 \
; set_db add_stripes_via_using_exact_crossover_size false  \
; set_db add_stripes_split_vias false \
; set_db add_stripes_orthogonal_only true \
; set_db add_stripes_allow_jog { padcore_ring block_ring }  \
; set_db add_stripes_skip_via_on_pin { standardcell } \
; set_db add_stripes_skip_via_on_wire_shape { noshape }

add_stripes -nets {VDD VSS} -layer METAL5 -direction horizontal -width 6  \
-spacing 5.76 -set_to_set_distance 70.56 -start_from bottom -start_offset 28.36  \
-switch_layer_over_obs false -max_same_layer_jog_length 2 -pad_core_ring_top_layer_limit METAL6  \
-pad_core_ring_bottom_layer_limit METAL1 -block_ring_top_layer_limit METAL6  \
-block_ring_bottom_layer_limit METAL1 -use_wire_group 0 -snap_wire_center_to_grid none
   
set_db add_stripes_ignore_block_check false  \
; set_db add_stripes_break_at none \
; set_db add_stripes_route_over_rows_only false  \
; set_db add_stripes_rows_without_stripes_only false \
; set_db add_stripes_extend_to_closest_target none  \
; set_db add_stripes_stop_at_last_wire_for_area false \
; set_db add_stripes_partial_set_through_domain false  \
; set_db add_stripes_ignore_non_default_domains false \
; set_db add_stripes_trim_antenna_back_to_shape none  \
; set_db add_stripes_spacing_type edge_to_edge \
; set_db add_stripes_spacing_from_block 0  \
; set_db add_stripes_stacked_via_top_layer METAL6 \
; set_db add_stripes_stacked_via_bottom_layer METAL1  \
; set_db add_stripes_via_using_exact_crossover_size false \
; set_db add_stripes_split_vias false  \
; set_db add_stripes_orthogonal_only true \
; set_db add_stripes_allow_jog { padcore_ring block_ring }  \
; set_db add_stripes_skip_via_on_pin { standardcell} \
; set_db add_stripes_skip_via_on_wire_shape { noshape } 

add_stripes -nets {VDD VSS} -layer METAL6 -direction vertical  \
-width 6 -spacing 3 -set_to_set_distance 70 -start_from left  \
-start_offset 70 -switch_layer_over_obs false -max_same_layer_jog_length 2  \
-pad_core_ring_top_layer_limit METAL6 -pad_core_ring_bottom_layer_limit METAL1  \
-block_ring_top_layer_limit METAL6 -block_ring_bottom_layer_limit METAL1 -use_wire_group 0 -snap_wire_center_to_grid none



# Lower stripes
# setAddStripeMode -extend_to_first_ring true \
#    -trim_antenna_back_to_shape {block_ring} \
#    -break_at {block_ring}

# # Core vertical stripes
# addStripe -skip_via_on_wire_shape Noshape \
#    -block_ring_top_layer_limit M4 \
#    -max_same_layer_jog_length 3.6 \
#    -padcore_ring_bottom_layer_limit M4 \
#    -skip_via_on_pin Standardcell \
#    -stacked_via_top_layer METAL5 \
#    -padcore_ring_top_layer_limit METAL1 \
#    -spacing 17 \
#    -set_to_set_distance 35 \
#    -layer M4 -block_ring_bottom_layer_limit METAL1 \
#    -width 1.44 -nets {VDD VSS} \
#    -stacked_via_bottom_layer METAL1 

# Rails
# avoid M1.S.1
create_route_blockage -pg_nets -rects {115.8 903 119 955} -layer {METAL1}
create_route_blockage -pg_nets -rects {115.8 1116 119 1166} -layer {METAL1}

set_db route_special_via_connect_to_shape { ring stripe } \
; set_db route_special_extend_nearest_target true 

route_special -connect {pad_pin core_pin} -layer_change_range { METAL1(1) METAL6(6) }  \
-pad_pin_port_connect {all_port one_geom}  \
-pad_pin_target {nearest_target} -core_pin_target {ring} -allow_jogging 1  \
-crossover_via_layer_range { METAL1(1) METAL6(6) } -nets { VDD VSS } -allow_layer_change 1  \
-target_via_layer_range { METAL1(1) METAL6(6) }


#set_db route_special_via_connect_to_shape { stripe }
# route_special -connect {block_pin pad_pin pad_ring core_pin} -layer_change_range { METAL1(1) METAL6(6) } \
# -block_pin_target nearest_target -pad_pin_port_connect {all_port one_geom} \
# -pad_pin_target nearest_target -core_pin_target first_after_row_end -delete_existing_routes \
# -allow_jogging 1 \
# -crossover_via_layer_range { METAL1(1) METAL6(6) } -nets { VDD VSS } -allow_layer_change 1 \
# -block_pin use_lef -target_via_layer_range { METAL1(1) METAL6(6) }\
