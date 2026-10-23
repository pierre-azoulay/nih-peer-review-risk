#!/usr/bin/env python3
r"""
format_table.py -- post-processor for the LaTeX table fragments of the package

Post-processes the rows that Stata's esttab writes (booktabs, fragment):
  - GUTTER insertion : an empty column between consecutive groups of models
  - CMIDRULE shift   : each group's \cmidrule shifts by the gutters to its left
  - LABEL splitting  : long labels split on a "|||" marker
  - MULTIROW centering: labels vertically centered over coefficient/SE pairs
  - MIDRULE injection : optional \midrule before a named row

Called from Stata's embedded Python by nr_fmt (code/programs/_programs.do):
    python format_table.py INPUT.tex OUTPUT.tex [options]

Options (regtable mode, the default):
    --groups N1,N2[,...]  Model-group sizes: one gutter between each pair of
                          consecutive groups, and the \cmidrule spans shifted to
                          match. Omit for a single-group (no-gutter) table.
    --no-multirow         Disable label-split + \multirow vertical centering.
    --split-marker STR    Marker used in Stata labels to force a line break
                          (default: "|||").
    --midrule-before STR  Insert a \midrule immediately before the first row whose
                          first cell begins with STR.
    --mode {regtable,descstats}   descstats, a 3+3+2 descriptive-statistics
                          layout, is not used by this package.

LaTeX preamble (regtable): \usepackage{booktabs}; \usepackage{multirow};
\newcommand{\sym}[1]{$^{\scriptstyle #1}$}. The paper supplies the tabular
column specification, including the gutter columns; this tool edits rows only.
"""

import argparse
import re

# Matches a \cmidrule, with optional (lr)-style argument, capturing the span.
_CMIDRULE_RE = re.compile(r'(\\cmidrule(?:\([^)]*\))?)\{(\d+)-(\d+)\}')
# Matches a group-title \multicolumn{N}{c} cell with N >= 2 (excludes the
# \multicolumn{1}{c} cells of the model-number / mtitles rows).
_BIG_MULTICOL_RE = re.compile(r'\\multicolumn\{(\d+)\}\{c\}')


# ------------------------------------------------------------------------------
# regtable mode
# ------------------------------------------------------------------------------

def _boundaries(groups):
    """Last original column of each group except the final one (column 1 is
    the label). A gutter is inserted after each of these columns."""
    out, col = [], 1
    for n in groups[:-1]:
        col += n
        out.append(col)
    return out


def _shift_cmidrules(line, bounds):
    r"""Shift each \cmidrule span by the number of gutters to its left.

    A rule starting at original column a moves right by the number of group
    boundaries before a. With two groups this leaves the first group's rule
    unchanged and moves the second group's rule +1 on both ends.
    """
    def repl(m):
        a, b = int(m.group(2)), int(m.group(3))
        s = sum(1 for c in bounds if c < a)
        return '%s{%d-%d}' % (m.group(1), a + s, b + s)

    return _CMIDRULE_RE.sub(repl, line)


def _is_mgroups_header(line, k):
    r"""True if this is the group-title row: exactly k \multicolumn{N>=2}{c}."""
    big = [int(n) for n in _BIG_MULTICOL_RE.findall(line) if int(n) >= 2]
    return len(big) == k


def _insert_header_gutters(line):
    r"""Insert one empty cell after every group-title \multicolumn cell but the
    last.

    Collapses the inter-group whitespace to a single space on each side so the
    junction reads ``} & & \multicolumn`` -- matching the legacy scripts byte
    for byte.
    """
    parts = line.split('&')
    idxs = [i for i, p in enumerate(parts) if '\\multicolumn' in p]
    for idx in reversed(idxs[:-1]):
        parts[idx] = parts[idx].rstrip() + ' '
        parts[idx + 1] = ' ' + parts[idx + 1].lstrip()
        parts.insert(idx + 1, ' ')
    return '&'.join(parts)


def _apply_multirow(lines, split_marker):
    r"""Wrap each coefficient-row label in \multirow{2}{*}{...} (centering it over
    the coef/SE pair) and clear the SE row's label. Split labels containing the
    marker across two lines via \shortstack. Stats rows (Observations, R^2, ...)
    are left untouched: they are detected by the next row's first cell being
    NON-empty (a coef/SE pair has an empty SE-row first cell)."""
    out = list(lines)
    i = 0
    while i < len(out):
        line = out[i]
        is_data_row = (
            '&' in line
            and '\\multicolumn' not in line
            and '\\cmidrule' not in line
            and '\\midrule' not in line
            and '\\addlinespace' not in line
        )
        if is_data_row and line.split('&')[0].strip():
            if i + 1 < len(out):
                nxt = out[i + 1]
                is_next_data_row = (
                    '&' in nxt
                    and '\\midrule' not in nxt
                    and '\\addlinespace' not in nxt
                )
                if is_next_data_row and not nxt.split('&')[0].strip():
                    first_cell = line.split('&')[0]
                    current_rest = '&'.join(line.split('&')[1:])
                    next_rest = '&'.join(nxt.split('&')[1:])
                    if split_marker in first_cell:
                        p = first_cell.split(split_marker)
                        label = ('\\multirow{2}{*}{\\shortstack[l]{'
                                 + p[0].strip() + '\\\\' + p[1].strip() + '}}')
                    else:
                        label = '\\multirow{2}{*}{' + first_cell.rstrip() + '}'
                    out[i] = label + '&' + current_rest
                    out[i + 1] = '&' + next_rest
        i += 1
    return out


def _insert_midrule_before(lines, label):
    r"""Insert a '\midrule' line before the first row whose first cell begins
    with `label` (e.g. 'Estimator')."""
    out = []
    done = False
    for line in lines:
        if (not done and '&' in line
                and line.split('&')[0].strip().startswith(label)):
            out.append('\\midrule\n')
            done = True
        out.append(line)
    return out


def process_regtable(lines, groups, do_multirow, split_marker, midrule_before):
    if groups:
        bounds = _boundaries(groups)   # &-part index of each gutter, data rows
        pass1 = []
        for line in lines:
            if '\\cmidrule' in line:
                line = _shift_cmidrules(line, bounds)
            if _is_mgroups_header(line, len(groups)):
                pass1.append(_insert_header_gutters(line))
                continue
            if '&' in line and '\\cmidrule' not in line:
                parts = line.split('&')
                for g in reversed(bounds):
                    if len(parts) > g:
                        parts.insert(g, ' ')
                line = '&'.join(parts)
            pass1.append(line)
        lines = pass1

    if do_multirow:
        lines = _apply_multirow(lines, split_marker)

    if midrule_before:
        lines = _insert_midrule_before(lines, midrule_before)

    return lines


# ------------------------------------------------------------------------------
# descstats mode  (Deepening | Extending | Global, 3+3+2 -> two gutters)
# ------------------------------------------------------------------------------

def process_descstats(lines):
    r"""The 3+3+2 descriptive-statistics layout (not used by this package).

    Input  (9 cols): label | Deep(Mean,Med,SD) | Ext(Mean,Med,SD) | (Min,Max)
    Output (11 cols): a gutter after Deep-SD and a gutter after Ext-SD, plus the
    tabular colspec and the second \cmidrule shifted to match.
    """
    out = []
    for line in lines:
        if '\\begin{tabular}' in line:
            out.append(line.replace('{l ccc ccc cc}', '{l ccc c ccc c cc}'))
            continue
        if '\\cmidrule' in line:
            out.append(re.sub(r'\\cmidrule\(lr\)\{5-7\}',
                              r'\\cmidrule(lr){6-8}', line))
            continue
        if '&' not in line:
            out.append(line)
            continue
        # group-title row: \multicolumn{3}{c}{Deepening} & \multicolumn{3}{c}{Extending}
        if '\\multicolumn{3}' in line:
            parts = line.split('&')
            if len(parts) >= 5:
                parts.insert(2, ' ')   # gutter after Deepening multicolumn
                parts.insert(4, ' ')   # gutter after Extending multicolumn
                line = '&'.join(parts)
            out.append(line)
            continue
        # stats header row: Mean & Median & Std. Dev. & ...
        if 'Mean' in line and 'Median' in line and 'Std. Dev.' in line:
            parts = line.split('&')
            if len(parts) >= 9:
                parts.insert(4, ' ')   # after first SD
                parts.insert(8, ' ')   # after second SD
                line = '&'.join(parts)
            out.append(line)
            continue
        # data rows
        parts = line.split('&')
        if len(parts) >= 9 and '\\\\' in line:
            parts.insert(4, ' ')
            parts.insert(8, ' ')
            line = '&'.join(parts)
        out.append(line)
    return out


# ------------------------------------------------------------------------------
# CLI
# ------------------------------------------------------------------------------

def _parse_groups(s):
    if s is None:
        return None
    try:
        vals = [int(x) for x in s.split(',') if x.strip() != '']
    except ValueError:
        raise argparse.ArgumentTypeError("--groups must be comma-separated ints, e.g. 5,5")
    if len(vals) < 2:
        raise argparse.ArgumentTypeError("--groups needs at least two sizes, e.g. 6,5 or 3,3,3")
    return vals


def main(argv=None):
    ap = argparse.ArgumentParser(description="Unified esttab LaTeX table post-processor.")
    ap.add_argument('input')
    ap.add_argument('output')
    ap.add_argument('--mode', choices=['regtable', 'descstats'], default='regtable')
    ap.add_argument('--groups', type=_parse_groups, default=None,
                    help="Group sizes, one gutter between consecutive groups, "
                         "e.g. 5,5 or 3,3,3. Omit for no gutter.")
    ap.add_argument('--no-multirow', dest='multirow', action='store_false',
                    help="Disable label-split + multirow centering.")
    ap.add_argument('--split-marker', default='|||')
    ap.add_argument('--midrule-before', default=None,
                    help="Insert a \\midrule before the row starting with this text.")
    args = ap.parse_args(argv)

    with open(args.input, 'r', encoding='utf-8') as f:
        lines = f.readlines()

    if args.mode == 'descstats':
        lines = process_descstats(lines)
    else:
        lines = process_regtable(lines, args.groups, args.multirow,
                                 args.split_marker, args.midrule_before)

    with open(args.output, 'w', encoding='utf-8') as f:
        f.writelines(lines)

    print("format_table.py: %s -> %s (mode=%s, groups=%s)"
          % (args.input, args.output, args.mode, args.groups))


if __name__ == '__main__':
    main()
