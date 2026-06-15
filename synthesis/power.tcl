connect_global_net VDD -type pg_pin -pin VDD -inst *
connect_global_net VSS -type pg_pin -pin VSS -inst *
connect_global_net VDD -type tie_hi 
connect_global_net VSS -type tie_lo 
connect_global_net VDD -type tie_hi -pin VDD -inst *
connect_global_net VSS -type tie_lo -pin VSS -inst *

connect_global_net VDDPST -type pg_pin -pin VDDPST -inst *
connect_global_net VSSPST -type pg_pin -pin VSSPST -inst *
connect_global_net VDDPST -type tie_hi 
connect_global_net VSSPST -type tie_lo 
connect_global_net VDDPST -type tie_hi -pin VDDPST -inst *
connect_global_net VSSPST -type tie_lo -pin VSSPST -inst *