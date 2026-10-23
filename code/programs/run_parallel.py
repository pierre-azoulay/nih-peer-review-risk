"""Run one do-file several times at once, each run a Stata batch process with its own arguments.

A do-file whose work splits into independent pieces (the four measures of
code/analysis/11_tables_1e_3.do) can run its pieces side by side: each piece is a
separate Stata batch process, started with the same do-file and its own arguments.
Each job uses about one core, so on a machine with several cores the elapsed time is
that of the slowest piece rather than the sum of all of them. Each run starts in its
own folder under the machine's temporary directory, through a one-line wrapper that
moves Stata to the package's root, because Stata's batch mode writes its own log in
the folder where it starts and the runs would otherwise overwrite each other's.

Run from the package's root, after the build:

    python code/programs/run_parallel.py code/analysis/11_tables_1e_3.do --runs 1 2 3 4 --then 0

--runs lists one argument string per parallel run (quote a string with spaces);
--then gives the arguments of a last run, started once every parallel run has succeeded.
The Stata executable is the one --stata or the environment variable NR_STATA names,
or else the first of StataMP-64, stata-mp, StataSE-64, stata-se found on the PATH.
Exit code 0 when every run ends without a Stata error.
"""

import argparse
import os
import platform
import re
import shutil
import subprocess
import sys
import tempfile
import time

STATA_NAMES = ["StataMP-64", "stata-mp", "StataSE-64", "stata-se"]
ERROR = re.compile(r"^r\((\d+)\);", re.M)


def launch(stata, root, dofile, args, workdir):
    """Write the wrapper in workdir, start one Stata batch process there, return it."""
    wrapper = os.path.join(workdir, "run.do")
    with open(wrapper, "w", encoding="utf-8") as f:
        f.write('cd "%s"\n' % root.replace("\\", "/"))
        f.write('do "%s" %s\n' % (dofile.replace("\\", "/"), args))
    batch = "/e" if platform.system() == "Windows" else "-b"
    cmd = [stata, batch, "do", os.path.abspath(wrapper)]
    kw = {"cwd": workdir, "stdout": subprocess.DEVNULL, "stderr": subprocess.DEVNULL}
    if platform.system() == "Windows":
        si = subprocess.STARTUPINFO()
        si.dwFlags |= subprocess.STARTF_USESHOWWINDOW
        si.wShowWindow = 0  # hidden
        kw["startupinfo"] = si
    return subprocess.Popen(cmd, **kw)


def outcome(workdir):
    """Read the batch log: 'ok', 'error r(NNN)' or 'no end of do-file'."""
    auto = os.path.join(workdir, "run.log")
    if not os.path.exists(auto):
        return "no batch log"
    with open(auto, encoding="latin-1") as f:
        text = f.read()
    m = ERROR.search(text)
    if m:
        return "error r(%s)" % m.group(1)
    return "ok" if "end of do-file" in text else "no end of do-file"


def run_set(stata, root, dofile, arglist, tmp):
    """Run the argument strings of arglist at once; return True if all succeed."""
    pending = []
    for k, args in enumerate(arglist, 1):
        wd = os.path.join(tmp, "run%02d" % k)
        os.makedirs(wd, exist_ok=True)
        pending.append((args, wd, time.time(), launch(stata, root, dofile, args, wd)))
        print("started  [%s]" % args, flush=True)
    good = True
    while pending:
        for run in list(pending):
            args, wd, t0, p = run
            if p.poll() is None:
                continue
            pending.remove(run)
            res = outcome(wd)
            good = good and res == "ok"
            print("finished [%s] %s after %.1f min (batch log %s)" % (args, res, (time.time() - t0) / 60, wd), flush=True)
        if pending:
            time.sleep(2)
    return good


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("dofile")
    ap.add_argument("--runs", nargs="+", required=True)
    ap.add_argument("--then", default=None)
    ap.add_argument("--stata", default=os.environ.get("NR_STATA"))
    a = ap.parse_args()
    if not a.stata:
        a.stata = next((shutil.which(n) for n in STATA_NAMES if shutil.which(n)), None)
    if not a.stata:
        sys.exit("Stata not found: give its path with --stata or the environment variable NR_STATA")
    root = os.getcwd()
    if not os.path.exists(os.path.join(root, "master.do")):
        sys.exit("run from the package's root folder (the one that holds master.do)")
    if not os.path.exists(os.path.join(root, a.dofile)):
        sys.exit("no such do-file: " + a.dofile)
    stem = os.path.splitext(os.path.basename(a.dofile))[0]
    tmp = os.path.join(tempfile.gettempdir(), "nihrep_parallel", stem)
    shutil.rmtree(tmp, ignore_errors=True)
    t0 = time.time()
    good = run_set(a.stata, root, a.dofile, a.runs, os.path.join(tmp, "parallel"))
    if good and a.then:
        good = run_set(a.stata, root, a.dofile, [a.then], os.path.join(tmp, "then"))
    print("%s after %.1f min" % ("all runs ok" if good else "FAILED", (time.time() - t0) / 60), flush=True)
    sys.exit(0 if good else 1)


if __name__ == "__main__":
    main()
