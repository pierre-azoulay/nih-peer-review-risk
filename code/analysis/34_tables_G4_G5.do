/* =============================================================================
   code/analysis/34_tables_G4_G5.do

   Purpose: Appendix Tables G4 and G5: do investigators hedge? The risk of the
            grant's work against the risk of the investigator's other work of
            the same years (code/build/29_other_work_risk.do), for three
            measures: extreme tail outcomes, disruption, pivoting (standing
            out left out: it compares a grant's work with the funded
            applications of its own study section, and the other work has no
            study section of its own). Tails and disruption in units of 10
            percentile points, pivoting as a fraction, on both sides. Standard
            errors clustered by investigator and by grant.
            - Table G4, landscape, twelve columns: the grant's measure
              regressed on the same measure computed on the other work; for
              each measure, (1) all the other work, (2) the same with grant
              fixed effects (investigator x grant), which compare the cycles
              of one grant with each other, (3) her other grants' work alone,
              (4) the same with grant fixed effects. Controls: the fixed
              effects of Table 2 (demographics, evaluation year, cycle
              length, institute x study section), the base controls with
              career citations counted through the year before the cycle
              starts (pi_cites_precycle, as in code/analysis/21_table_A2.do)
              in place of the year before the evaluation, the bins of
              acknowledging papers, bins of the other papers behind the other
              work's measure (1, 2, 3-4, 5-9, 10-19, 20-49, 50+, the bins of
              the lag's paper count in Table G2), and the flag for windows
              past 2018. In brackets, the coefficient times the s.d. of the
              other work's measure on the column's cycles, in s.d. of the
              grant's measure.
              Log only: her other grants' work with investigator fixed
              effects in place of grant fixed effects; pivoting with the bins
              of baseline papers of Appendix D added, the two sides sharing
              the baseline; and the mirror (section 2b): when two of her
              grants are in the sample at once, each cycle's other work is in
              part the other cycle's grant work, which pushes the columns
              with investigator fixed effects toward a negative slope (the
              reason Table G4 uses grant fixed effects), so the log gives the
              share of cycles with a concurrent sample cycle on another grant
              and the three specifications on the cycles without one.
            - Table G5, in the layout of Table G2: renewal on the grant's risk
              alone, the other work's risk alone, and both, on the same
              cycles, with Table 2's controls (career citations at the cycle's
              start, as above) and the bins of the other papers behind the
              other work's measure. In brackets, the coefficient times the
              regressor's s.d. on these cycles. Log only: pivoting with the
              bins of baseline papers.

   Input:
     - ${public}/nih_risk_public.dta          (code/build/34_public_file.do)
       with the variables of risk_other.dta (code/build/29_other_work_risk.do)
   Output:
     - output/tables/table_G4.tex, output/tables/table_G5.tex
       Appendix Tables G4 and G5 (written row by row)
     - estimates/table_G4_*.ster, estimates/table_G5_*.ster

   Note: do code/analysis/34_tables_G4_G5.do [0], the argument 0 redrawing
         the tables from the saved estimates.
   ============================================================================= */

#delimit ;
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

log using "logs/34_tables_G4_G5.log", replace text name(nih_risk) ;

local start_time = clock("`c(current_date)' `c(current_time)'", "DMYhms") ;

/* 1 = estimate and save; 0 = reuse the saved estimates. A first argument
   overrides it (do code/analysis/34_tables_G4_G5.do 0) */
local run_regs = 1 ;
if "`1'" != "" local run_regs = `1' ;

/* -----------------------------------------------------------------------------
   1. Data
   ----------------------------------------------------------------------------- */
use "`afile'", clear ;

/* career citations at the start of the cycle (as in
   code/analysis/21_table_A2.do) */
gen double log_pi_cites_start = ln(pi_cites_precycle + 1) ;
label variable log_pi_cites_start "ln(career citations through cycle_yr - 1 + 1)" ;
local x2s : subinstr local x2 "log_pi_careercites_evalyr" "log_pi_cites_start", count(local nsub) ;
assert `nsub' == 1 ;
local x3s : subinstr local x3 "log_pi_careercites_evalyr" "log_pi_cites_start", count(local nsub) ;
assert `nsub' == 1 ;
display as text "Table G4, continuous controls: `x2s'" ;
display as text "Table G5, continuous controls: `x3s'" ;

/* the three measures on both sides, tails and disruption in units of 10
   percentile points, pivoting as a fraction, and the bins of the other
   papers behind each measure on the other work */
local o1 "tails" ; local o2 "disr" ; local o3 "pivot" ;
local cn1 "tails" ; local cn2 "disr" ; local cn3 "mesh" ;
local nm 3 ;
forvalues j = 1/`nm' {;
    local sc = cond(`j' <= 2, 10, 1) ;
    gen double G`j' = `m`j'' * `sc' ;
    label variable G`j' "Risk of the grant's work" ;
    foreach s in ow og {;
        gen double `s'`j' = `s'_`o`j'' * `sc' ;
        label variable `s'`j' "Risk of the other work" ;
        local n "n_`s'_`cn`j''" ;
        gen byte b`s'`j' = cond(`n' <= 2, `n', cond(`n' <= 4, 3, cond(`n' <= 9, 5,
                           cond(`n' <= 19, 10, cond(`n' <= 49, 20, 50))))) if !missing(`s'`j') ;
    } ;
} ;

/* -----------------------------------------------------------------------------
   2. The grant's risk on the other work's risk: without fixed effects
      (Table G4, columns 1 and 3 of each measure) and, for the log, her
      other grants' work with investigator fixed effects (og1)
   ----------------------------------------------------------------------------- */
if `run_regs' {;
    forvalues j = 1/`nm' {;
        local t "`t`j''" ;
        foreach c in ow0 og0 og1 {;
            local s = substr("`c'", 1, 2) ;
            local f = substr("`c'", 3, 1) ;
            local fev = cond(`f', "inv_id", "") ;
            capture drop smp ;
            reghdfe G`j' `s'`j' `x2s', absorb(`fe2' bin_ackn authority_partial b`s'`j' `fev') vce(cluster `clus') ;
            gen byte smp = e(sample) ;
            nr_post ;
            quietly summarize `s'`j' if smp ;
            estadd scalar sdx = r(sd) ;
            estadd scalar sdy = e(sddv) ;
            estimates save "estimates/table_G4_`t'_`s'`f'.ster", replace ;
            drop smp ;
        } ;
    } ;
} ;

display as result _newline "=== the grant's risk on the other work's risk: no fixed effects (0), and for the log her other grants' work with investigator fixed effects (og1)" ;
forvalues j = 1/`nm' {;
    local t "`t`j''" ;
    estimates clear ;
    foreach c in ow0 og0 og1 {;
        estimates use "estimates/table_G4_`t'_`c'.ster" ;
        estimates store `c' ;
    } ;
    display as result _newline "--- `l`j''" ;
    esttab ow0 og0 og1, keep(ow`j' og`j') b(%7.4f) se(%7.4f) star(+ 0.10 * 0.05 ** 0.01)
        stats(N ninv meandv sdy sdx r2_a r2_within, fmt(%9.0fc %9.0fc %6.3f %6.3f %6.3f %6.4f %6.4f)) mtitles ;
    foreach c in ow0 og0 og1 {;
        estimates restore `c' ;
        local s = substr("`c'", 1, 2) ;
        display as text "`c': coefficient " %7.4f _b[`s'`j'] ", in s.d. of the grant's measure per s.d. of the other work's " %6.3f _b[`s'`j'] * e(sdx) / e(sdy)
            ", 95% interval " %7.4f _b[`s'`j'] - 1.96 * _se[`s'`j'] " to " %7.4f _b[`s'`j'] + 1.96 * _se[`s'`j'] ;
    } ;
} ;

/* -----------------------------------------------------------------------------
   2b. The mirror in the columns with investigator fixed effects, and the
       grant fixed effects of Table G4.
       When two of an investigator's grants are in the sample with
       overlapping windows, the other work of one cycle is in good part the
       grant's work of the other (her other grants' work above all, since
       ackn_links.dta links papers to the cycle file's grants), so that with
       investigator fixed effects the two cycles enter as mirror images and
       the slope is pushed toward a negative value whatever she does. Grant
       fixed effects (investigator x grant) in place of investigator fixed
       effects compare the cycles of one grant with each other and exclude
       the mirror: they give Table G4's columns 2 and 4 of each measure. Log
       only: the specifications on the cycles without a concurrent sample
       cycle of the same investigator on another grant (windows overlapping
       by at least one year).
   ----------------------------------------------------------------------------- */
preserve ;
keep inv_id grant_id cycle span_start eval_year ;
rename grant_id pn2 ;
rename cycle cy2 ;
rename span_start s2 ;
rename eval_year e2 ;
tempfile oth ;
save `oth' ;
restore ;
preserve ;
keep inv_id grant_id cycle span_start eval_year ;
joinby inv_id using `oth' ;
keep if pn2 != grant_id & s2 <= eval_year & e2 >= span_start ;
gcollapse (count) n_conc = cy2, by(inv_id grant_id cycle) ;
tempfile conc ;
save `conc' ;
restore ;
merge 1:1 inv_id grant_id cycle using `conc' ;
assert _merge != 2 ;
drop _merge ;
replace n_conc = 0 if n_conc == . ;
gen byte conc = n_conc > 0 ;
gegen long gid = group(inv_id grant_id) ;
display as result _newline "=== the mirror: share of cycles with a concurrent sample cycle on another grant, among the cycles with both measures, and among those whose investigator has at least two such cycles (the columns with investigator fixed effects, singletons aside)" ;
forvalues j = 1/`nm' {;
    local t "`t`j''" ;
    foreach s in ow og {;
        capture drop ninvc ;
        gegen long ninvc = count(G`j') if !missing(G`j') & !missing(`s'`j'), by(inv_id) ;
        quietly summarize conc if !missing(G`j') & !missing(`s'`j') ;
        local a = r(mean) ;
        local na = r(N) ;
        quietly summarize conc if !missing(G`j') & !missing(`s'`j') & ninvc >= 2 ;
        display as text "`t' `s': share with a concurrent sample cycle " %5.3f `a' " (N " %9.0fc `na' "), investigators with two or more " %5.3f r(mean) " (N " %9.0fc r(N) ")" ;
    } ;
} ;
capture drop ninvc ;
if `run_regs' {;
    forvalues j = 1/`nm' {;
        local t "`t`j''" ;
        foreach s in ow og {;
            capture drop smp ;
            reghdfe G`j' `s'`j' `x2s', absorb(`fe2' bin_ackn authority_partial b`s'`j' gid) vce(cluster `clus') ;
            gen byte smp = e(sample) ;
            nr_post ;
            quietly summarize `s'`j' if smp ;
            estadd scalar sdx = r(sd) ;
            estadd scalar sdy = e(sddv) ;
            estimates save "estimates/table_G4_`t'_`s'g.ster", replace ;
            drop smp ;
            reghdfe G`j' `s'`j' `x2s' if conc == 0, absorb(`fe2' bin_ackn authority_partial b`s'`j') vce(cluster `clus') ;
            nr_post ;
            estimates save "estimates/table_G4_`t'_`s'0nc.ster", replace ;
            reghdfe G`j' `s'`j' `x2s' if conc == 0, absorb(`fe2' bin_ackn authority_partial b`s'`j' inv_id) vce(cluster `clus') ;
            nr_post ;
            estimates save "estimates/table_G4_`t'_`s'1nc.ster", replace ;
            reghdfe G`j' `s'`j' `x2s' if conc == 0, absorb(`fe2' bin_ackn authority_partial b`s'`j' gid) vce(cluster `clus') ;
            nr_post ;
            estimates save "estimates/table_G4_`t'_`s'gnc.ster", replace ;
        } ;
    } ;
} ;
display as result _newline "=== the mirror: investigator fixed effects (1, her other grants' work), grant fixed effects (g), none (0), on all cycles and on those without a concurrent sample cycle (nc)" ;
forvalues j = 1/`nm' {;
    local t "`t`j''" ;
    foreach s in ow og {;
        local cl = cond("`s'" == "og", "0 1 g 0nc 1nc gnc", "0 g 0nc 1nc gnc") ;
        foreach c of local cl {;
            estimates use "estimates/table_G4_`t'_`s'`c'.ster" ;
            display as text "`t' `s' `c': " %7.4f _b[`s'`j'] " (" %6.4f _se[`s'`j'] "), N " %9.0fc e(N) ", investigators " %9.0fc e(ninv) ;
        } ;
    } ;
} ;

/* log only: pivoting with the bins of baseline papers with MeSH of
   Appendix D (code/analysis/26_tables_D1_D3_figure_D1.do), since the
   grant's pivoting and the other work's are measured against the same
   baseline, so that a thin baseline raises both */
gen byte nprior_bin = 1 if n_base_mesh == 1 ;
replace nprior_bin = 2 if n_base_mesh == 2 ;
replace nprior_bin = 3 if inrange(n_base_mesh, 3, 4) ;
replace nprior_bin = 4 if inrange(n_base_mesh, 5, 9) ;
replace nprior_bin = 5 if inrange(n_base_mesh, 10, 19) ;
replace nprior_bin = 6 if inrange(n_base_mesh, 20, 49) ;
replace nprior_bin = 7 if n_base_mesh >= 50 & !missing(n_base_mesh) ;
if `run_regs' {;
    foreach s in ow og {;
        forvalues f = 0/1 {;
            local fev = cond(`f', "inv_id", "") ;
            reghdfe G3 `s'3 `x2s', absorb(`fe2' bin_ackn authority_partial b`s'3 nprior_bin `fev') vce(cluster `clus') ;
            nr_post ;
            estimates save "estimates/table_G4_pivot_`s'`f'nb.ster", replace ;
        } ;
    } ;
} ;
display as result _newline "=== the grant's risk on the other work's risk, pivoting, with the bins of baseline papers (log only)" ;
foreach c in ow0 ow1 og0 og1 {;
    estimates use "estimates/table_G4_pivot_`c'nb.ster" ;
    local s = substr("`c'", 1, 2) ;
    display as text "`c' with baseline bins: " %7.4f _b[`s'3] " (" %6.4f _se[`s'3] "), N " %9.0fc e(N) ;
} ;

/* -----------------------------------------------------------------------------
   3. Table G5: renewal on the grant's risk and the other work's risk
   ----------------------------------------------------------------------------- */
if `run_regs' {;
    forvalues j = 1/`nm' {;
        local t "`t`j''" ;
        /* both, which defines the cycles of the three columns */
        capture drop smp ;
        reghdfe `dv' G`j' ow`j' `x3s', absorb(`fe3' bow`j') vce(cluster `clus') ;
        gen byte smp = e(sample) ;
        quietly summarize G`j' if smp ;
        local sdg = r(sd) ;
        quietly summarize ow`j' if smp ;
        local sdo = r(sd) ;
        nr_post ;
        estadd scalar sdg = `sdg' ;
        estadd scalar sdo = `sdo' ;
        estimates save "estimates/table_G5_`t'_c.ster", replace ;
        reghdfe `dv' G`j' `x3s' if smp, absorb(`fe3' bow`j') vce(cluster `clus') ;
        nr_post ;
        estadd scalar sdg = `sdg' ;
        estadd scalar sdo = `sdo' ;
        estimates save "estimates/table_G5_`t'_a.ster", replace ;
        reghdfe `dv' ow`j' `x3s' if smp, absorb(`fe3' bow`j') vce(cluster `clus') ;
        nr_post ;
        estadd scalar sdg = `sdg' ;
        estadd scalar sdo = `sdo' ;
        estimates save "estimates/table_G5_`t'_b.ster", replace ;
        drop smp ;
    } ;
    /* log only: pivoting with the bins of baseline papers (section 2) */
    reghdfe `dv' G3 ow3 `x3s', absorb(`fe3' bow3 nprior_bin) vce(cluster `clus') ;
    gen byte smp = e(sample) ;
    estimates save "estimates/table_G5_pivot_cnb.ster", replace ;
    reghdfe `dv' G3 `x3s' if smp, absorb(`fe3' bow3 nprior_bin) vce(cluster `clus') ;
    estimates save "estimates/table_G5_pivot_anb.ster", replace ;
    drop smp ;
} ;
estimates use "estimates/table_G5_pivot_anb.ster" ;
local b0 = _b[G3] ;
estimates use "estimates/table_G5_pivot_cnb.ster" ;
display as result "=== Table G5, pivoting with the bins of baseline papers (log only): the grant's risk " %7.4f `b0' " alone, "
    %7.4f _b[G3] " (" %6.4f _se[G3] ") with the other work's (" %5.1f 100 * _b[G3] / `b0' "%), the other work's " %7.4f _b[ow3] " (" %6.4f _se[ow3] "), N " %9.0fc e(N) ;

display as result _newline "=== Table G5: the grant's risk alone (a), the other work's alone (b), both (c)" ;
forvalues j = 1/`nm' {;
    local t "`t`j''" ;
    estimates clear ;
    foreach c in a b c {;
        estimates use "estimates/table_G5_`t'_`c'.ster" ;
        estimates store `c' ;
    } ;
    display as result _newline "--- `l`j''" ;
    esttab a b c, keep(G`j' ow`j') b(%7.4f) se(%7.4f) star(+ 0.10 * 0.05 ** 0.01)
        stats(N ninv meandv r2_a, fmt(%9.0fc %9.0fc %6.3f %6.4f)) mtitles ;
    estimates restore a ;
    local ba = _b[G`j'] ;
    local sdg = e(sdg) ;
    local sdo = e(sdo) ;
    estimates restore b ;
    local bb = _b[ow`j'] ;
    estimates restore c ;
    display as text "the grant's risk keeps " %5.1f 100 * _b[G`j'] / `ba' "% of its coefficient with the other work's risk held fixed"
        ", the other work's keeps " %5.1f 100 * _b[ow`j'] / `bb' "%" ;
    display as text "one s.d.: the grant's risk " %7.4f `ba' * `sdg' " alone, " %7.4f _b[G`j'] * `sdg' " with the other work's (s.d. " %6.3f `sdg'
        "), the other work's risk " %7.4f `bb' * `sdo' " alone, " %7.4f _b[ow`j'] * `sdo' " with the grant's (s.d. " %6.3f `sdo' ")" ;
} ;

/* -----------------------------------------------------------------------------
   4. The tables, written row by row
   ----------------------------------------------------------------------------- */
/* Appendix Table G4: landscape, twelve columns, four per measure, with grant
   fixed effects in the second column of each pair, since the mirror of
   section 2b drives the columns with investigator fixed effects. The loop
   over versions runs on this version alone (v = 2) */
local tf2 "table_G4" ; local fe_lab2 "Grant fixed effects" ;        local cols2 "ow0 owg og0 ogg" ;
tempname fh ;
forvalues v = 2/2 {;
    file open `fh' using "output/tables/`tf`v''.tex", write replace text ;
    file write `fh' " & \multicolumn{4}{c}{`l1'} & & \multicolumn{4}{c}{`l2'} & & \multicolumn{4}{c}{`l3'} \\" _n ;
    file write `fh' "\cmidrule(lr){2-5}\cmidrule(lr){7-10}\cmidrule(lr){12-15}" _n ;
    file write `fh' " & (1) & (2) & (3) & (4) & & (5) & (6) & (7) & (8) & & (9) & (10) & (11) & (12) \\" _n ;
    file write `fh' "\midrule" _n ;
    local Brow "Risk of the other work" ; local Bse "" ; local Bsd "" ;
    local wrow "Other work" ;
    local frow "`fe_lab`v''" ;
    local mrow "Mean of the grant's measure" ;
    local irow "Nb.\ of investigators" ;
    local nrow "Nb.\ of grant cycles" ;
    local arow "Adjusted \(R^2\)" ;
    forvalues j = 1/`nm' {;
        local t "`t`j''" ;
        if `j' > 1 {;
            foreach r in Brow Bse Bsd wrow frow mrow irow nrow arow {;
                local `r' "``r'' &" ;
            } ;
        } ;
        foreach c of local cols`v' {;
            estimates use "estimates/table_G4_`t'_`c'.ster" ;
            local s = substr("`c'", 1, 2) ;
            local f = substr("`c'", 3, 1) ;
            nr_star `=_b[`s'`j']' `=_se[`s'`j']' ;
            local Brow "`Brow' & `=strtrim(string(_b[`s'`j'], "%6.3f"))'`r(star)'" ;
            local Bse  "`Bse' & (`=strtrim(string(_se[`s'`j'], "%5.3f"))')" ;
            local Bsd  "`Bsd' & {\footnotesize [`=strtrim(string(_b[`s'`j'] * e(sdx) / e(sdy), "%6.3f"))']}" ;
            local wrow "`wrow' & `=cond("`s'" == "ow", "All", "Other grants")'" ;
            local frow "`frow' & `=cond("`f'" == "0", "No", "Yes")'" ;
            local mrow "`mrow' & `=strtrim(string(e(meandv), "%5.3f"))'" ;
            local irow "`irow' & `=strtrim(string(e(ninv), "%9.0fc"))'" ;
            local nrow "`nrow' & `=strtrim(string(e(N), "%9.0fc"))'" ;
            local arow "`arow' & `=strtrim(string(e(r2_a), "%5.3f"))'" ;
        } ;
    } ;
    file write `fh' "`Brow' \\" _n "`Bse' \\" _n "`Bsd' \\" _n "\midrule" _n ;
    file write `fh' "`wrow' \\" _n "`frow' \\" _n "\midrule" _n ;
    file write `fh' "`mrow' \\" _n "`irow' \\" _n "`nrow' \\" _n "`arow' \\" _n ;
    file close `fh' ;
    type "output/tables/`tf`v''.tex" ;
} ;

/* Appendix Table G5: in the layout of Table G2, three columns per measure */
file open `fh' using "output/tables/table_G5.tex", write replace text ;
file write `fh' " & \multicolumn{3}{c}{`l1'} & & \multicolumn{3}{c}{`l2'} & & \multicolumn{3}{c}{`l3'} \\" _n ;
file write `fh' "\cmidrule(lr){2-4}\cmidrule(lr){6-8}\cmidrule(lr){10-12}" _n ;
file write `fh' " & (1) & (2) & (3) & & (4) & (5) & (6) & & (7) & (8) & (9) \\" _n ;
file write `fh' "\midrule" _n ;
local Grow "Risk of the grant's work" ; local Gse "" ; local Gsd "" ;
local Orow "Risk of the other work" ;   local Ose "" ; local Osd "" ;
local mrow "Mean of dependent variable" ;
local irow "Nb.\ of investigators" ;
local nrow "Nb.\ of grant cycles" ;
local arow "Adjusted \(R^2\)" ;
forvalues j = 1/`nm' {;
    local t "`t`j''" ;
    if `j' > 1 {;
        foreach r in Grow Gse Gsd Orow Ose Osd mrow irow nrow arow {;
            local `r' "``r'' &" ;
        } ;
    } ;
    foreach c in a b c {;
        estimates use "estimates/table_G5_`t'_`c'.ster" ;
        if "`c'" == "b" {;
            local Grow "`Grow' & " ;
            local Gse  "`Gse' & " ;
            local Gsd  "`Gsd' & " ;
        } ;
        else {;
            nr_star `=_b[G`j']' `=_se[G`j']' ;
            local Grow "`Grow' & `=strtrim(string(_b[G`j'], "%7.4f"))'`r(star)'" ;
            local Gse  "`Gse' & (`=strtrim(string(_se[G`j'], "%6.4f"))')" ;
            local Gsd  "`Gsd' & {\footnotesize [`=strtrim(string(_b[G`j'] * e(sdg), "%7.4f"))']}" ;
        } ;
        if "`c'" == "a" {;
            local Orow "`Orow' & " ;
            local Ose  "`Ose' & " ;
            local Osd  "`Osd' & " ;
        } ;
        else {;
            nr_star `=_b[ow`j']' `=_se[ow`j']' ;
            local Orow "`Orow' & `=strtrim(string(_b[ow`j'], "%7.4f"))'`r(star)'" ;
            local Ose  "`Ose' & (`=strtrim(string(_se[ow`j'], "%6.4f"))')" ;
            local Osd  "`Osd' & {\footnotesize [`=strtrim(string(_b[ow`j'] * e(sdo), "%7.4f"))']}" ;
        } ;
        local mrow "`mrow' & `=strtrim(string(e(meandv), "%5.3f"))'" ;
        local irow "`irow' & `=strtrim(string(e(ninv), "%9.0fc"))'" ;
        local nrow "`nrow' & `=strtrim(string(e(N), "%9.0fc"))'" ;
        local arow "`arow' & `=strtrim(string(e(r2_a), "%6.4f"))'" ;
    } ;
} ;
file write `fh' "`Grow' \\" _n "`Gse' \\" _n "`Gsd' \\" _n "\addlinespace" _n ;
file write `fh' "`Orow' \\" _n "`Ose' \\" _n "`Osd' \\" _n "\midrule" _n ;
file write `fh' "`mrow' \\" _n "`irow' \\" _n "`nrow' \\" _n "`arow' \\" _n ;
file close `fh' ;
type "output/tables/table_G5.tex" ;

local end_time = clock("`c(current_date)' `c(current_time)'", "DMYhms") ;
local elapsed  = (`end_time' - `start_time') / 1000 ;
local hrs  = floor(`elapsed' / 3600) ;
local mins = floor(mod(`elapsed', 3600) / 60) ;
local secs = round(mod(`elapsed', 60), 1) ;
display _newline as text "Total runtime: `hrs'h `mins'm `secs's" ;

log close nih_risk ;

/* End of 34_tables_G4_G5.do */
