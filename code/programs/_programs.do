/* --------------------------------------------------------------------------
   _programs.do  --  small helpers every analysis do-file shares

   Purpose : nr_post    adds the summary rows of a regression table to the
                        current estimates: mean and standard deviation of the
                        outcome, investigators and grants (the two cluster
                        counts), and each named coefficient in standard
                        deviations of the outcome. Call it right after the
                        estimation, while e(sample) is valid, then save the
                        estimates: the rows travel with the .ster file.
             nr_fmt     runs the table formatter (format_table.py) on the
                        esttab fragment estimates/tex/<name>.tex and writes
                        the exhibit, output/tables/<name>.tex. It goes
                        through Stata's embedded Python (python script).
             nr_gexport saves the current graph and writes the exhibit,
                        output/figures/<name>.pdf.
             nr_star    the significance marks of a coefficient written into
                        a table by hand.
             nr_pctlab  the percent labels of a histogram's y axis.
   Used by : every do-file of code/analysis, via
             `include "code/programs/_programs.do"' after
             `include "code/programs/_spec.do"'.
   -------------------------------------------------------------------------- */

#delimit ;

capture program drop nr_post ;
program define nr_post ;
    syntax [, Coefs(namelist)] ;
    quietly summarize `e(depvar)' if e(sample) ;
    local sd = r(sd) ;
    estadd scalar meandv = r(mean) ;
    estadd scalar sddv   = `sd' ;
    estadd scalar ninv   = e(N_clust1) ;
    estadd scalar ngrant = e(N_clust2) ;
    local k = 0 ;
    foreach c of local coefs {;
        local ++k ;
        estadd scalar sdeff`k' = _b[`c'] / `sd' ;
    } ;
end ;

/* nr_fmt <name>: format estimates/tex/<name>.tex (the rows written by
   esttab) into output/tables/<name>.tex. groups() inserts gutter columns
   between groups of models, midrule() a rule before the row that starts
   with the given text, nomultirow keeps each label on its coefficient's row */
capture program drop nr_fmt ;
program define nr_fmt ;
    syntax namelist(name=stub max=1 id="table stub") [, Groups(string) MIDrule(string) NOMULTIrow] ;
    local a `""estimates/tex/`stub'.tex" "output/tables/`stub'.tex""' ;
    if "`groups'"     != "" local a `"`a' "--groups" "`groups'""' ;
    if `"`midrule'"'  != "" local a `"`a' "--midrule-before" "`midrule'""' ;
    if "`nomultirow'" != "" local a `"`a' "--no-multirow""' ;
    capture erase "output/tables/`stub'.tex" ;
    python script "${tools}/format_table.py", args(`a') ;
    confirm file "output/tables/`stub'.tex" ;
    display as text "formatted: output/tables/`stub'.tex" ;
end ;

/* nr_gexport <name>: save the current graph as graphs/gph/<name>.gph, export
   graphs/svg/<name>.svg, and convert the SVG to output/figures/<name>.pdf in
   CMU Sans Serif (code/programs/svg2pdf.py, Inkscape). The PNG
   (graphs/png/<name>.png) is exported only when the global nr_png is 1: no
   exhibit uses it. */
capture program drop nr_gexport ;
program define nr_gexport ;
    syntax namelist(name=g max=1 id="graph name") ;
    graph save "graphs/gph/`g'.gph", replace ;
    if "${nr_png}" == "1" {;
        capture mkdir "graphs/png" ;
        graph export "graphs/png/`g'.png", replace width(1600) ;
    } ;
    graph export "graphs/svg/`g'.svg", replace ;
    capture erase "output/figures/`g'.pdf" ;
    python script "${tools}/svg2pdf.py", args("graphs/svg/`g'.svg" "output/figures/`g'.pdf") ;
    confirm file "output/figures/`g'.pdf" ;
    display as text "figure: output/figures/`g'.pdf" ;
end ;

/* nr_star <b> <se>: the significance marks of the house style for a
   coefficient written into a table by hand (file write), as r(star): a
   dagger below 0.10, one star below 0.05, two below 0.01 (normal test). */
capture program drop nr_star ;
program define nr_star, rclass ;
    args b se ;
    local p = 2 * normal(-abs(`b' / `se')) ;
    local s "" ;
    if `p' < 0.10 local s "\sym{\dagger}" ;
    if `p' < 0.05 local s "\sym{*}" ;
    if `p' < 0.01 local s "\sym{**}" ;
    return local star "`s'" ;
end ;

/* nr_pctlab <max>: the y axis of a histogram drawn in percent of each
   group's cycles: from 0 to <max> rounded up to a multiple of 5, in steps of
   2.5 up to 20 and of 5 beyond, labelled 0%, 2.5%, 5% ... Returns r(lab),
   for ylabel(), and r(top), for yscale(). The labels are built here because
   mylabels cannot print 2.5% and 5% in one format: a general format pads
   them with blanks, a fixed one gives 5.0%, and its clean option turns 10
   into 1%. */
capture program drop nr_pctlab ;
program define nr_pctlab, rclass ;
    args mx ;
    local top = 5 * ceil(`mx' / 5) ;
    local step = cond(`top' <= 20, 2.5, 5) ;
    local nk = round(`top' / `step') ;
    local lab "" ;
    forvalues k = 0/`nk' {;
        local v = `k' * `step' ;
        local lab `"`lab' `v' "`=strofreal(`v')'%""' ;
    } ;
    return local lab `"`lab'"' ;
    return scalar top = `top' ;
end ;
