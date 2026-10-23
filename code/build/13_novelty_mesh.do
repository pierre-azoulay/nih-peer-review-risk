/* =============================================================================
   code/build/13_novelty_mesh.do

   Purpose: Run code/build/13_novelty_mesh.py, the MeSH-pair novelty of each
            cycle and the birth years of every MeSH descriptor and pair over
            PubMed 2025, as a separate Python process (${python}, config.do):
            its DuckDB job holds up to 90 GB, which a separate process returns
            to the system when it ends. The script's own log is
            logs/13_novelty_mesh_py.log; it is copied into this do-file's log.

   Input:
     - ${data}/build/cycle_papers.dta               (code/build/03_cycle_papers.do)
     - ${pubmed_root}/pubmed/overall_meshterms_2025.dta, overall_dates_2025.dta
                                                   MeSH descriptors and years of PubMed 2025

   Output:
     - ${data}/build/novelty_mesh.dta               one row per cycle with a measure:
       agepair_cyclefrac, agepair_cyclemean, agesingle_cyclemean, n_pair_inst
     - ${data}/build/meshpair_birthyear.parquet     every MeSH pair of PubMed 2025, birth year
     - ${data}/build/meshsingle_birthyear.parquet   every descriptor, birth year
       (read by code/build/32_standout_extras.do)

   Note: about 5 minutes on a 16-core machine with 128 GB of memory. DuckDB's
         temporary files go to a folder under the machine's temporary
         directory, off any synchronized folder.
   ============================================================================= */

#delimit ;
clear all ;
version 19.5 ;
pause on ;
program drop _all ;
set more off ;
capture log close nih_risk ;

include "config.do" ;

log using "logs/13_novelty_mesh.log", replace text name(nih_risk) ;

local start_time = clock("`c(current_date)' `c(current_time)'", "DMYhms") ;

capture erase "${data}/build/novelty_mesh.dta" ;

#delimit cr
python:
import os
import subprocess
import tempfile
from sfi import Macro, SFIToolkit

py = Macro.getGlobal("python")
spill = os.path.join(tempfile.gettempdir(), "duckdb_spill_nihrep_novelty")
args = [py, "-I", "code/build/13_novelty_mesh.py",
        Macro.getGlobal("data"),
        Macro.getGlobal("pubmed_root") + "/pubmed",
        spill,
        "logs/13_novelty_mesh_py.log"]
SFIToolkit.display("running: " + " ".join(args))
r = subprocess.run(args, stdin=subprocess.DEVNULL, capture_output=True, text=True)
if r.returncode != 0:
    SFIToolkit.display(r.stdout[-2000:])
    SFIToolkit.display(r.stderr[-4000:])
    raise SystemExit("13_novelty_mesh.py failed with exit code %d" % r.returncode)
end
#delimit ;

type "logs/13_novelty_mesh_py.log" ;
confirm file "${data}/build/novelty_mesh.dta" ;
confirm file "${data}/build/meshpair_birthyear.parquet" ;
confirm file "${data}/build/meshsingle_birthyear.parquet" ;
describe using "${data}/build/novelty_mesh.dta" ;

local end_time = clock("`c(current_date)' `c(current_time)'", "DMYhms") ;
local elapsed  = (`end_time' - `start_time') / 1000 ;
local hrs  = floor(`elapsed' / 3600) ;
local mins = floor(mod(`elapsed', 3600) / 60) ;
local secs = round(mod(`elapsed', 60), 1) ;
display _newline as text "Total runtime: `hrs'h `mins'm `secs's" ;

log close nih_risk ;

/* End of code/build/13_novelty_mesh.do */
