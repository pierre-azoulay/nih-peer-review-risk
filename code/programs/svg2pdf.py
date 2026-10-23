"""
svg2pdf.py -- convert an SVG exported by Stata to PDF with Inkscape.

Called from Stata's embedded Python by nr_gexport (code/programs/_programs.do):
    python script "code/programs/svg2pdf.py", args("graphs/svg/x.svg" "output/figures/x.pdf")
Stata names the font Helvetica in its SVGs; it is replaced by CMU Sans Serif
before conversion, so the PDF matches the paper's typeface. Inkscape runs as a
subprocess with its input and output captured, never through Stata's shell.
Inkscape is found on the PATH, or at the path given by the global inkscape of
config.do.

The edited SVG is written to the system's temporary folder: a file written next
to its source can be locked by a file-synchronization client while it syncs,
and its removal then fails.

Inkscape substitutes another typeface, without a warning, when CMU Sans Serif
is not installed where it looks for fonts. The script therefore reads the fonts
embedded in the PDF and stops with an error unless every one is CMU Sans Serif.
"""
import os
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile

from sfi import Macro

src, dst = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
fd, tmpname = tempfile.mkstemp(prefix=src.stem + '_', suffix='.svg')
os.close(fd)
tmp = pathlib.Path(tmpname)
tmp.write_text(src.read_text(encoding='utf-8').replace('Helvetica', 'CMU Sans Serif'),
               encoding='utf-8')
exe = shutil.which('inkscape') or Macro.getGlobal('inkscape')
if not exe:
    raise SystemExit('Inkscape not found: put it on the PATH or set global inkscape in config.do')
try:
    r = subprocess.run([exe, str(tmp), '--export-filename=' + str(dst)],
                       stdin=subprocess.DEVNULL, capture_output=True, text=True)
finally:
    tmp.unlink(missing_ok=True)
if r.returncode != 0 or not dst.exists():
    raise SystemExit('inkscape failed on %s: %s' % (src, r.stderr[-800:]))
fonts = set(re.findall(rb'/BaseFont\s*/([^\s/\[\]<>()]+)', dst.read_bytes()))
other = sorted(f.decode('latin-1') for f in fonts if b'CMUSansSerif' not in f)
if not fonts or other:
    raise SystemExit('%s is not set in CMU Sans Serif (fonts: %s): install the font '
                     'where Inkscape finds it (README, Software)'
                     % (dst, ', '.join(other) or 'none found'))
