/* =============================================================================
   master.do

   Purpose: Replicate every table and figure of the paper and its
            appendices. As distributed (local build 0, below), it unzips the
            public analysis file included in the package
            (data/nih_risk_public.zip) and runs the analysis
            (code/analysis/), in the paper's order; nothing else is needed.
            With local build 1, it first runs the build (code/build/), from
            the raw sources, available from the authors on request, to the
            analysis file, the side files that some appendix exhibits read,
            and a new public analysis file.

   Use:     with Stata's working directory at this folder:
                do master.do                   (in a Stata session), or
                stata-mp -b do master.do       (batch; StataMP-64.exe /e on Windows)
            Each stage has a switch below (1 runs it, 0 skips it); a stage
            reads only what the stages before it wrote, so a later stage can
            be rerun alone once the earlier ones have run.

   Output:  output/tables/   the table fragments, named by the printed number
            output/figures/  the figures, named by the printed number
            logs/            one log per do-file, and logs/master.log with
                             the runtime of each stage
            data/            the public analysis file, unzipped
            ${data}          with the build only: its intermediates and the
                             analysis file

   Note:    about five hours in one Stata session on a 16-core machine with
            128 GB of memory; about two and a quarter with one Stata process
            per do-file (README).
   ============================================================================= */

#delimit ;
clear all ;
version 19.5 ;
set more off ;
capture log close master ;

include "config.do" ;

log using "logs/master.log", replace text name(master) ;

local start_all = clock("`c(current_date)' `c(current_time)'", "DMYhms") ;

/* -----------------------------------------------------------------------------
   build: 0 (the default) replicates every table and figure from the public
   analysis file included in the package, data/nih_risk_public.zip, which is
   unzipped here; the build's stages are skipped. 1 runs the build from the
   raw sources first (available from the authors on request), ending with a
   new public analysis file.
   ----------------------------------------------------------------------------- */
local build 0 ;
if `build' == 0 {;
    local here "`c(pwd)'" ;
    cd "${public}" ;
    unzipfile "nih_risk_public.zip", replace ;
    cd "`here'" ;
    confirm file "${public}/nih_risk_public.dta" ;
} ;

/* -----------------------------------------------------------------------------
   The stages, in run order: switch (1 runs, 0 skips), do-file, arguments.
   ----------------------------------------------------------------------------- */
local n 0 ;

/* the build: the cycle file, the papers, the controls, the measures, the
   outcomes, the investigators, then the analysis file */
local ++n ; local s`n' `build' ; local f`n' "code/build/01_cycles.do" ;                  local a`n' "" ;
local ++n ; local s`n' `build' ; local f`n' "code/build/02_ackn_links.do" ;              local a`n' "" ;
local ++n ; local s`n' `build' ; local f`n' "code/build/03_cycle_papers.do" ;            local a`n' "" ;
local ++n ; local s`n' `build' ; local f`n' "code/build/04_cycle_controls.do" ;          local a`n' "" ;
local ++n ; local s`n' `build' ; local f`n' "code/build/05_paper_attributes.do" ;        local a`n' "" ;
local ++n ; local s`n' `build' ; local f`n' "code/build/06_cycle_output.do" ;            local a`n' "" ;
local ++n ; local s`n' `build' ; local f`n' "code/build/07_tails.do" ;                   local a`n' "" ;
local ++n ; local s`n' `build' ; local f`n' "code/build/08_disruption.do" ;              local a`n' "" ;
local ++n ; local s`n' `build' ; local f`n' "code/build/09_pivoting.do" ;                local a`n' "" ;
local ++n ; local s`n' `build' ; local f`n' "code/build/10_pivoting_extras.do" ;         local a`n' "" ;
local ++n ; local s`n' `build' ; local f`n' "code/build/11_abstract_tags.do" ;           local a`n' "" ;
local ++n ; local s`n' `build' ; local f`n' "code/build/12_standing_out.do" ;            local a`n' "" ;
local ++n ; local s`n' `build' ; local f`n' "code/build/13_novelty_mesh.do" ;            local a`n' "" ;
local ++n ; local s`n' `build' ; local f`n' "code/build/14_novelty_text.do" ;            local a`n' "" ;
local ++n ; local s`n' `build' ; local f`n' "code/build/15_proposal_pivot.do" ;          local a`n' "" ;
local ++n ; local s`n' `build' ; local f`n' "code/build/16_patents.do" ;                 local a`n' "" ;
local ++n ; local s`n' `build' ; local f`n' "code/build/17_cycle_cites.do" ;             local a`n' "" ;
local ++n ; local s`n' `build' ; local f`n' "code/build/18_commercial_potential.do" ;    local a`n' "" ;
local ++n ; local s`n' `build' ; local f`n' "code/build/19_investigator_flags.do" ;      local a`n' "" ;
local ++n ; local s`n' `build' ; local f`n' "code/build/20_record_before_cycle.do" ;     local a`n' "" ;
local ++n ; local s`n' `build' ; local f`n' "code/build/21_concurrent_grants.do" ;       local a`n' "" ;
local ++n ; local s`n' `build' ; local f`n' "code/build/22_breadth.do" ;                 local a`n' "" ;
local ++n ; local s`n' `build' ; local f`n' "code/build/23_analysis_file.do" ;           local a`n' "" ;

/* the side files that some appendix exhibits read */
local ++n ; local s`n' `build' ; local f`n' "code/build/24_risk_windows.do" ;            local a`n' "" ;
local ++n ; local s`n' `build' ; local f`n' "code/build/25_lagged_risk.do" ;             local a`n' "" ;
local ++n ; local s`n' `build' ; local f`n' "code/build/26_fading_fields.do" ;           local a`n' "" ;
local ++n ; local s`n' `build' ; local f`n' "code/build/27_tail_projects.do" ;           local a`n' "" ;
local ++n ; local s`n' `build' ; local f`n' "code/build/28_team_distance.do" ;           local a`n' "" ;
local ++n ; local s`n' `build' ; local f`n' "code/build/29_other_work_risk.do" ;         local a`n' "" ;
local ++n ; local s`n' `build' ; local f`n' "code/build/30_disruption_versions.do" ;     local a`n' "" ;
local ++n ; local s`n' `build' ; local f`n' "code/build/31_disruption_versions_cycle.do" ; local a`n' "" ;
local ++n ; local s`n' `build' ; local f`n' "code/build/32_standout_extras.do" ;         local a`n' "" ;
local ++n ; local s`n' `build' ; local f`n' "code/build/33_outcome_windows.do" ;         local a`n' "" ;
/* the public analysis file, which every do-file of the analysis reads */
local ++n ; local s`n' `build' ; local f`n' "code/build/34_public_file.do" ;            local a`n' "" ;

/* the main text's exhibits, in the paper's order. Table 3 runs its four
   measures one after the other (arguments 1 to 4), then writes Tables 1e
   and 3 (argument 0); code/programs/run_parallel.py runs the four measures
   at once instead (README) */
local ++n ; local s`n' 1 ; local f`n' "code/analysis/10_tables_1a_1d_figures_1_2.do" ; local a`n' "" ;
local ++n ; local s`n' 1 ; local f`n' "code/analysis/11_tables_1e_3.do" ;          local a`n' "1" ;
local ++n ; local s`n' 1 ; local f`n' "code/analysis/11_tables_1e_3.do" ;          local a`n' "2" ;
local ++n ; local s`n' 1 ; local f`n' "code/analysis/11_tables_1e_3.do" ;          local a`n' "3" ;
local ++n ; local s`n' 1 ; local f`n' "code/analysis/11_tables_1e_3.do" ;          local a`n' "4" ;
local ++n ; local s`n' 1 ; local f`n' "code/analysis/11_tables_1e_3.do" ;          local a`n' "0" ;
local ++n ; local s`n' 1 ; local f`n' "code/analysis/12_table_2.do" ;              local a`n' "" ;
local ++n ; local s`n' 1 ; local f`n' "code/analysis/13_figure_3.do" ;             local a`n' "" ;
local ++n ; local s`n' 1 ; local f`n' "code/analysis/14_figure_4_figures_F1_F2.do" ; local a`n' "" ;
local ++n ; local s`n' 1 ; local f`n' "code/analysis/15_figure_5_table_I1.do" ;    local a`n' "" ;

/* the appendices' exhibits, Appendices A to L */
local ++n ; local s`n' 1 ; local f`n' "code/analysis/20_table_A1.do" ;             local a`n' "" ;
local ++n ; local s`n' 1 ; local f`n' "code/analysis/21_table_A2.do" ;             local a`n' "" ;
local ++n ; local s`n' 1 ; local f`n' "code/analysis/22_tables_A3_A4.do" ;         local a`n' "" ;
local ++n ; local s`n' 1 ; local f`n' "code/analysis/23_table_B1.do" ;             local a`n' "" ;
local ++n ; local s`n' 1 ; local f`n' "code/analysis/24_table_B2.do" ;             local a`n' "" ;
local ++n ; local s`n' 1 ; local f`n' "code/analysis/25_tables_C1_C2.do" ;         local a`n' "" ;
local ++n ; local s`n' 1 ; local f`n' "code/analysis/26_tables_D1_D3_figure_D1.do" ; local a`n' "" ;
local ++n ; local s`n' 1 ; local f`n' "code/analysis/27_table_D4_figure_D3.do" ;   local a`n' "" ;
local ++n ; local s`n' 1 ; local f`n' "code/analysis/28_table_D5.do" ;             local a`n' "" ;
local ++n ; local s`n' 1 ; local f`n' "code/analysis/29_tables_E1_E4.do" ;         local a`n' "" ;
local ++n ; local s`n' 1 ; local f`n' "code/analysis/30_table_F1.do" ;             local a`n' "" ;
local ++n ; local s`n' 1 ; local f`n' "code/analysis/31_table_G1.do" ;             local a`n' "" ;
local ++n ; local s`n' 1 ; local f`n' "code/analysis/32_table_G2.do" ;             local a`n' "" ;
local ++n ; local s`n' 1 ; local f`n' "code/analysis/33_table_G3.do" ;             local a`n' "" ;
local ++n ; local s`n' 1 ; local f`n' "code/analysis/34_tables_G4_G5.do" ;         local a`n' "" ;
local ++n ; local s`n' 1 ; local f`n' "code/analysis/35_table_H1.do" ;             local a`n' "" ;
local ++n ; local s`n' 1 ; local f`n' "code/analysis/36_table_H2.do" ;             local a`n' "" ;
local ++n ; local s`n' 1 ; local f`n' "code/analysis/37_figures_J1_J2_table_J1.do" ; local a`n' "" ;
local ++n ; local s`n' 1 ; local f`n' "code/analysis/38_figures_K1_K2.do" ;        local a`n' "" ;
local ++n ; local s`n' 1 ; local f`n' "code/analysis/39_table_K1.do" ;             local a`n' "" ;
local ++n ; local s`n' 1 ; local f`n' "code/analysis/40_table_L1.do" ;             local a`n' "" ;

/* -----------------------------------------------------------------------------
   Run them, timing each
   ----------------------------------------------------------------------------- */
forvalues i = 1/`n' {;
    if `s`i'' {;
        display as result _newline "=== master: `f`i'' `a`i''" ;
        local t0 = clock("`c(current_date)' `c(current_time)'", "DMYhms") ;
        do "`f`i''" `a`i'' ;
        local t1 = clock("`c(current_date)' `c(current_time)'", "DMYhms") ;
        local rt`i' = round((`t1' - `t0') / 60000, 0.1) ;
    } ;
} ;

display as result _newline "=== master: runtime of each stage (minutes)" ;
forvalues i = 1/`n' {;
    if `s`i'' display as text %8.1f `rt`i'' "  `f`i'' `a`i''" ;
} ;

local end_all = clock("`c(current_date)' `c(current_time)'", "DMYhms") ;
local elapsed = (`end_all' - `start_all') / 1000 ;
local hrs  = floor(`elapsed' / 3600) ;
local mins = floor(mod(`elapsed', 3600) / 60) ;
local secs = round(mod(`elapsed', 60), 1) ;
display _newline as text "Total runtime: `hrs'h `mins'm `secs's" ;

log close master ;

/* End of master.do */
