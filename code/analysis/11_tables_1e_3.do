/* =============================================================================
   code/analysis/11_tables_1e_3.do

   Purpose: Table 3, the downstream outcomes of renewed and terminated grant
            cycles, and Table 1e, the same outcomes described. The outcomes
            are measured in the five years after the cycle's last payment
            (code/build/33_outcome_windows.do). Four columns per measure:
            first cycles renewed and terminated, later cycles renewed and
            terminated. First and later cycles are those of Table 2
            (cycle_nb == 1; cycle_nb >= 2, the cycles of unknown number out).
            Cycles evaluated by 2020 on which the measure is defined; the
            terminated cycles are those not renewed, less the grants revived
            later (next_revival). For renewed cycles, the five years after
            include work paid for by the renewal; each comparison is within
            one column. Each cell of Table 3 is one Poisson regression
            (ppmlhdfe) of an outcome of the after window on an indicator for
            a cycle above the median of the measure (within evaluation year,
            every cycle where the measure is defined), with the grant output
            controls of Table 2, clustered by investigator and grant. Seven
            outcomes are estimated; Table 3 shows six of them (publications
            left out), in its own order and words.

   Usage: the regressions of each measure j (1 to 4) first, which save their
   results, then the two tables, from the saved results:
       do code/analysis/11_tables_1e_3.do <j>    the regressions of measure j
       do code/analysis/11_tables_1e_3.do 0      Tables 1e and 3
   The four measure runs are independent: run them one after the other, or at
   once, each in its own Stata batch process, before the run with 0:
       python -I code/programs/run_parallel.py code/analysis/11_tables_1e_3.do
           --runs 1 2 3 4 --then 0

   Input:
     - ${public}/nih_risk_public.dta          (code/build/34_public_file.do)
       with the variables of cycle_windows.dta (code/build/33_outcome_windows.do)
   Output:
     - estimates/table_3_med_m<j>.dta   one row per regression of measure j
                                        (argument j)
     - output/tables/table_1e.tex, output/tables/table_3.tex (argument 0; rows
       only: the paper supplies the tabular, caption and notes)
   ============================================================================= */

#delimit ;
args what ;
/* the form of the measure in the regressions of Table 3: an indicator for a
   cycle above the median (med) */
local form "med" ;
clear all ;
version 19.5 ;
set processors 4 ;
pause on ;
program drop _all ;
set more off ;
capture log close nih_risk ;

include "config.do" ;
include "code/programs/_spec.do" ;
include "code/programs/_programs.do" ;

if !inlist("`what'", "0", "1", "2", "3", "4") {;
    display as error "first argument: a measure number 1 to 4, or 0 for the tables" ;
    exit 198 ;
} ;
if "`what'" != "0" & !inlist("`form'", "med", "lin") {;
    display as error "local form: med (above the median) or lin (the measure in s.d. units)" ;
    exit 198 ;
} ;
local lsuf = cond("`what'" == "0", "_tables", "_m`what'") ;

log using "logs/11_tables_1e_3`lsuf'.log", replace name(nih_risk) ;

local start_time = clock("`c(current_date)' `c(current_time)'", "DMYhms") ;

/* the outcomes of the after window, numbered (yi): stem, label */
local ny 7 ;
local yv1 "n_pubs" ;       local yl1 "Publications" ;
local yv2 "cites5" ;       local yl2 "Citations to these publications" ;
local yv3 "pat_cites" ;    local yl3 "Patent citations to these publications" ;
local yv4 "pharma_cites" ; local yl4 "Drug and device patent citations" ;
local yv5 "kpss_value" ;   local yl5 "Value of the citing patents (KPSS)" ;
local yv6 "compot_mean" ;  local yl6 "Commercial potential of the publications" ;
local yv7 "n_grpat" ;      local yl7 "Patents of the grant (NIH RePORTER)" ;

/* -----------------------------------------------------------------------------
   0. The data: the analysis file, the windows, the two forms of each measure,
      and the four columns
   ----------------------------------------------------------------------------- */
use "`afile'", clear ;

/* lin_<t>: the measure in s.d. units, whose non-missing values define the
   sample of every regression (the cycles where the measure is defined);
   med_<t>: above the median within evaluation year, the regressor */
forvalues j = 1/`nmeas' {;
    local t "`t`j''" ;
    quietly summarize `m`j'' ;
    local sd`j' = r(sd) ;
    gen double lin_`t' = (`m`j'' - r(mean)) / r(sd) ;
    gquantiles md_`t' = `m`j'' if !missing(`m`j''), xtile nquantiles(2) by(`pctby') ;
    gen byte med_`t' = (md_`t' == 2) if !missing(md_`t') ;
} ;

/* the columns: 1 first cycles renewed, 2 first terminated, 3 later renewed,
   4 later terminated (first and later as in Table 2,
   code/analysis/12_table_2.do) */
gen byte col = . ;
replace col = 1 if cycle_nb == 1 & renewed == 1 ;
replace col = 2 if cycle_nb == 1 & renewed == 0 & next_revival == 0 ;
replace col = 3 if cycle_nb >= 2 & cycle_nb < . & renewed == 1 ;
replace col = 4 if cycle_nb >= 2 & cycle_nb < . & renewed == 0 & next_revival == 0 ;
gen byte smp = eval_year <= 2020 & !missing(col) ;
display as result "=== the four columns, cycles evaluated by 2020 with an acknowledging paper" ;
tab col if smp & n_ackn >= 1 ;

/* -----------------------------------------------------------------------------
   1. The regressions of one measure, one row per regression (argument j)
   ----------------------------------------------------------------------------- */
capture program drop t3_reg ;
program define t3_reg ;
    args pf ids y x cond fe ctrl ;
    capture noisily ppmlhdfe `y' `x' `ctrl' if `cond', absorb(`fe') vce(cluster inv_id grant_id) ;
    local rc = _rc ;
    local b = . ;
    local se = . ;
    local n = . ;
    if `rc' == 0 {;
        local b  = _b[`x'] ;
        local se = _se[`x'] ;
        local n = e(N) ;
    } ;
    post `pf' `ids' (`b') (`se') (`n') (`rc') ;
end ;

if "`what'" != "0" {;
    local j = `what' ;
    local t "`t`j''" ;
    tempname pf ;
    postfile `pf' byte(j col yi) double(b se) long nobs int rc
        using "estimates/table_3_`form'_m`j'.dta", replace ;
    forvalues c = 1/4 {;
        forvalues i = 1/`ny' {;
            local y "`yv`i''_aft" ;
            display as result _newline "=== `t' (`form'): column `c', `y'" ;
            t3_reg `pf' "(`j') (`c') (`i')" `y' `form'_`t' "smp & col == `c' & !missing(lin_`t')" "`fe3'" "`x3'" ;
        } ;
    } ;
    postclose `pf' ;
    preserve ;
    use "estimates/table_3_`form'_m`j'.dta", clear ;
    count if rc != 0 ;
    display as result "=== measure `j', `form': regressions that failed: " r(N) ;
    list col yi rc if rc != 0, noobs ;
    restore ;
} ;

/* -----------------------------------------------------------------------------
   2. The two tables (argument 0)
   ----------------------------------------------------------------------------- */
if "`what'" == "0" {;

    /* the cycles of each column, and the share above the median */
    forvalues j = 1/`nmeas' {;
        forvalues c = 1/4 {;
            quietly summarize med_`t`j'' if smp & col == `c' & !missing(lin_`t`j'') ;
            local nc_`j'_`c' : display %9.0fc r(N) ;
            local nc_`j'_`c' = strtrim("`nc_`j'_`c''") ;
            local sh_`j'_`c' : display %3.0f 100 * r(mean) ;
            local sh_`j'_`c' = strtrim("`sh_`j'_`c''") ;
            display as text "`t`j'' column `c': `nc_`j'_`c'' cycles, `sh_`j'_`c'' percent above the median" ;
        } ;
    } ;

    /* Table 1e: the outcomes of Table 3 described on its cycles: cycles
       evaluated by 2020 with an acknowledging publication and a known number
       within the grant, renewed or terminated (not renewed and not revived
       later). Two panels, renewed and terminated cycles; mean, median,
       standard deviation, minimum, maximum, and the number of cycles behind
       each row, since commercial potential starts with the publications of
       1990 */
    local dv1 "cites5_aft" ;       local dl1 "Article Citations" ;    local df1 "%12.1fc" ;
    local dv2 "n_grpat_aft" ;      local dl2 "Direct Grant Patents" ; local df2 "%9.2f" ;
    local dv3 "pat_cites_aft" ;    local dl3 "Patent Citations" ;     local df3 "%12.2fc" ;
    local dv4 "pharma_cites_aft" ; local dl4 "FDA Patent Citations" ; local df4 "%9.2f" ;
    local dv5 "kpss_value_aft" ;   local dl5 "KPSS Patent Value" ;    local df5 "%12.1fc" ;
    local dv6 "compot_mean_aft" ;  local dl6 "Commercial Potential" ; local df6 "%9.3f" ;
    tempname fe ;
    file open `fe' using "output/tables/table_1e.tex", write replace ;
    file write `fe' " & Mean & Median & Std. Dev. & Min. & Max. & Cycles \\" _n "\midrule" _n ;
    local gl1 "A. Renewed cycles" ;
    local gl2 "B. Terminated cycles" ;
    forvalues g = 1/2 {;
        if `g' == 2 file write `fe' "\addlinespace" _n ;
        file write `fe' "\multicolumn{7}{l}{\textit{`gl`g''}} \\" _n ;
        local gc = cond(`g' == 1, "inlist(col, 1, 3)", "inlist(col, 2, 4)") ;
        forvalues r = 1/6 {;
            quietly summarize `dv`r'' if smp & n_ackn >= 1 & `gc', detail ;
            local row "\quad `dl`r''" ;
            foreach s in mean p50 sd min max {;
                local v : display `df`r'' r(`s') ;
                local row "`row' & `=strtrim("`v'")'" ;
            } ;
            local v : display %12.0fc r(N) ;
            file write `fe' "`row' & `=strtrim("`v'")' \\" _n ;
        } ;
    } ;
    file close `fe' ;
    type "output/tables/table_1e.tex" ;

    /* the rows of Table 3: the outcome's number above (yi) and its label;
       publications are left out */
    local nrow 6 ;
    local ro1 2 ; local rl1 "Article Citations" ;
    local ro2 7 ; local rl2 "Direct Grant Patents" ;
    local ro3 3 ; local rl3 "Patent Citations" ;
    local ro4 4 ; local rl4 "FDA Patent Citations" ;
    local ro5 5 ; local rl5 "KPSS Patent Value" ;
    local ro6 6 ; local rl6 "Commercial Potential" ;
    foreach form in med {;
        clear ;
        forvalues j = 1/`nmeas' {;
            append using "estimates/table_3_`form'_m`j'.dta" ;
        } ;
        gisid j col yi ;
        count if rc != 0 ;
        display as result "=== `form': regressions that failed: " r(N) ;
        list j col yi rc if rc != 0, noobs ;

        /* every cell once: the coefficient with its stars, and the standard
           error, for measure j, column c and row r */
        forvalues j = 1/`nmeas' {;
            forvalues c = 1/4 {;
                forvalues r = 1/`nrow' {;
                    local i = `ro`r'' ;
                    quietly summarize b if j == `j' & col == `c' & yi == `i' ;
                    local bb = r(mean) ;
                    quietly summarize se if j == `j' & col == `c' & yi == `i' ;
                    local ss = r(mean) ;
                    if missing(`bb') | missing(`ss') {;
                        local cb_`j'_`c'_`r' "--" ;
                        local cs_`j'_`c'_`r' "" ;
                    } ;
                    else {;
                        nr_star `bb' `ss' ;
                        local cb_`j'_`c'_`r' "`: display %6.3f `bb''`r(star)'" ;
                        local cs_`j'_`c'_`r' "(`: display %5.3f `ss'')" ;
                    } ;
                } ;
            } ;
        } ;

        tempname fh ;

        /* Table 3, in landscape: two measures side by side, tails and
           disruption above, pivoting and standing out below; 12 columns, a
           narrow gutter between first and later cycles and a wider one
           between measures */
        if "`form'" == "med" {;
            file open `fh' using "output/tables/table_3.tex", write replace ;
            foreach pr in "1 2" "3 4" {;
                tokenize `pr' ;
                local ja = `1' ;
                local jb = `2' ;
                if `ja' == 3 file write `fh' "\addlinespace" _n ;
                file write `fh' " & \multicolumn{5}{c}{`l`ja''} & & \multicolumn{5}{c}{`l`jb''} \\" _n ;
                file write `fh' "\cmidrule(lr){2-6}\cmidrule(lr){8-12}" _n ;
                file write `fh' " & \multicolumn{2}{c}{First cycle} & & \multicolumn{2}{c}{Later cycles} & & \multicolumn{2}{c}{First cycle} & & \multicolumn{2}{c}{Later cycles} \\" _n ;
                file write `fh' "\cmidrule(lr){2-3}\cmidrule(lr){5-6}\cmidrule(lr){8-9}\cmidrule(lr){11-12}" _n ;
                file write `fh' " & Renewed & Terminated & & Renewed & Terminated & & Renewed & Terminated & & Renewed & Terminated \\" _n "\midrule" _n ;
                forvalues r = 1/`nrow' {;
                    local r1 "\multirow{2}{*}{`rl`r''}" ;
                    local r2 "" ;
                    foreach j in `ja' `jb' {;
                        forvalues c = 1/4 {;
                            local r1 "`r1' & `cb_`j'_`c'_`r''" ;
                            local r2 "`r2' & `cs_`j'_`c'_`r''" ;
                            if `c' == 2 {;
                                local r1 "`r1' &" ;
                                local r2 "`r2' &" ;
                            } ;
                        } ;
                        if `j' == `ja' {;
                            local r1 "`r1' &" ;
                            local r2 "`r2' &" ;
                        } ;
                    } ;
                    file write `fh' "`r1' \\" _n "`r2' \\" _n ;
                } ;
                local row "\quad{\footnotesize\textit{Cycles}}" ;
                foreach j in `ja' `jb' {;
                    forvalues c = 1/4 {;
                        local row "`row' & {\footnotesize `nc_`j'_`c''}" ;
                        if `c' == 2 local row "`row' &" ;
                    } ;
                    if `j' == `ja' local row "`row' &" ;
                } ;
                file write `fh' "\cmidrule{1-12}" _n "`row' \\" _n ;
                if `ja' == 1 file write `fh' "\midrule" _n ;
            } ;
            file close `fh' ;
            type "output/tables/table_3.tex" ;
        } ;
    } ;
} ;

local end_time = clock("`c(current_date)' `c(current_time)'", "DMYhms") ;
local elapsed  = (`end_time' - `start_time') / 1000 ;
local hrs  = floor(`elapsed' / 3600) ;
local mins = floor(mod(`elapsed', 3600) / 60) ;
local secs = round(mod(`elapsed', 60), 1) ;
display _newline as text "Total runtime: `hrs'h `mins'm `secs's" ;

log close nih_risk ;
