#!/usr/bin/env python3
"""beebasm-fmt — Formatter for BeebASM 6502 assembly source files.

Normalises whitespace and alignment in BeebASM .asm files without changing
any assembled output. Designed for reverse-engineering projects where
consistent formatting aids readability.

Usage:
    beebasm-fmt.py [options] file.asm [file2.asm ...]
    beebasm-fmt.py --check file.asm     # exit 1 if changes needed

Formatting rules:
    - Labels at column 0  (.label, .*label, .^label)
    - Instructions/directives indented to INDENT (default 4 spaces)
    - Extra indent inside FOR/NEXT, IF/ENDIF, MACRO/ENDMACRO blocks
    - Inline comments aligned to COMMENT_COL (default 40)
    - Comment-only lines: leading whitespace preserved
    - Blank lines preserved
    - Scope braces {} at column 0
    - Multi-statement lines (: separator) have spacing normalised
    - EQUB/EQUS/EQUW data treated like instructions
    - Assignments (FOO = expr) padded for alignment

Standalone tool — no dependencies beyond Python 3.6+.
"""

import argparse
import re
import sys
from pathlib import Path

# --- Defaults ---

INDENT = 4
COMMENT_COL = 32
MIN_COMMENT_GAP = 2
LABEL_PAD = 16              # Pad labels to this width when followed by instruction
ASSIGN_PAD = 12             # Pad assignment names to this width
TAB_SIZE = 8
ENCODING = 'latin-1'        # BBC Micro sources may contain high-byte chars

# Both ; and \ are valid BeebASM comment characters.
COMMENT_CHARS = (';', '\\')

# Directives that open a nesting level (body gets extra indent).
NEST_OPEN = {'FOR', 'MACRO', 'IF'}
# Directives that close a nesting level.
NEST_CLOSE = {'NEXT', 'ENDMACRO', 'ENDIF'}
# Directives that close then re-open (same indent as the open/close).
NEST_TOGGLE = {'ELSE', 'ELIF'}

# Top-level directives that should always be at column 0, never indented.
# These are build/assembly-level commands, not code instructions.
TOPLEVEL_DIRECTIVES = {
    'ORG', 'CLEAR', 'GUARD', 'ALIGN', 'CPU',
    'INCLUDE', 'INCBIN', 'SAVE',
    'PUTFILE', 'PUTBASIC', 'PUTTEXT',
    'PRINT', 'ERROR', 'COPYBLOCK',
    'FOR', 'NEXT', 'MACRO', 'ENDMACRO',
    'IF', 'ELIF', 'ELSE', 'ENDIF',
    'MAPCHAR',
}


def expand_tabs(line, tab_size=TAB_SIZE):
    return line.expandtabs(tab_size)


def _find_comment(text):
    """Find the start of an inline comment (; or \\), respecting strings.

    Returns (code_part, comment_part) where comment_part includes the
    delimiter, or (text, None) if no comment found.

    Note: BeebASM's "" escape (doubled quote) works here by coincidence —
    the parser toggles out then immediately back into string mode.
    """
    in_string = False
    string_char = None
    for i, ch in enumerate(text):
        if in_string:
            if ch == string_char:
                in_string = False
            continue
        if ch in ('"', "'"):
            in_string = True
            string_char = ch
            continue
        if ch in COMMENT_CHARS:
            return text[:i].rstrip(), text[i:]
    return text, None


def _split_colon_stmts(code):
    """Split code on : separators, respecting strings."""
    parts = []
    current = []
    in_string = False
    string_char = None
    for ch in code:
        if in_string:
            current.append(ch)
            if ch == string_char:
                in_string = False
            continue
        if ch in ('"', "'"):
            in_string = True
            string_char = ch
            current.append(ch)
            continue
        if ch == ':':
            part = ''.join(current).strip()
            if part:
                parts.append(part)
            current = []
            continue
        current.append(ch)
    part = ''.join(current).strip()
    if part:
        parts.append(part)
    return parts if parts else [code]


def _parse_instruction(text):
    """Parse 'MNEMONIC operand' into (mnemonic, operand|None)."""
    text = text.strip()
    m = re.match(r'([A-Za-z_][A-Za-z0-9_]*)\s*(.*)', text)
    if m:
        return m.group(1), m.group(2).strip() or None
    return text, None


def _append_comment(code, comment, comment_col):
    """Append inline comment at the target column with minimum gap."""
    if not comment:
        return code
    target = max(comment_col, len(code) + MIN_COMMENT_GAP)
    return code.ljust(target) + comment


def _convert_comment_char(comment, target_char):
    """Convert comment delimiter to target style (';' or '\\')."""
    if not comment:
        return comment
    if comment[0] in COMMENT_CHARS and comment[0] != target_char:
        return target_char + comment[1:]
    return comment


def classify_line(line):
    """Classify a source line into components."""
    raw = line.rstrip('\n\r')
    stripped = raw.strip()

    r = {
        'type': 'verbatim', 'label': None, 'instruction': None,
        'operand': None, 'comment': None, 'raw': raw, 'colon_stmts': [],
        'has_colon_sep': False,
    }

    if not stripped:
        r['type'] = 'blank'
        return r

    # Comment-only line — preserve original leading whitespace
    if stripped[0] in COMMENT_CHARS:
        r['type'] = 'comment'
        r['comment'] = raw
        return r

    # Scope brace (possibly with comment)
    if stripped[0] in ('{', '}'):
        code_part, comment = _find_comment(stripped)
        if code_part in ('{', '}'):
            r['type'] = 'brace'
            r['instruction'] = code_part
            r['comment'] = comment
            return r

    # Split code from trailing comment
    code_part, comment = _find_comment(stripped)
    r['comment'] = comment

    # Label at start (.label, .*label, .^label, .*^label)
    m = re.match(r'^(\.[\^*]{0,2}[A-Za-z_][A-Za-z0-9_]*)', code_part)
    if m:
        r['label'] = m.group(1)
        rest = code_part[m.end():]
        # Check for : separator between label and instruction
        rest_stripped = rest.strip()
        if rest_stripped.startswith(':'):
            r['has_colon_sep'] = True
            rest_stripped = rest_stripped[1:].strip()
        code_part = rest_stripped

    # Assignment (NAME = expr) — only if no label prefix
    if not r['label']:
        m = re.match(r'^([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.+)', code_part)
        if m:
            r['type'] = 'assignment'
            r['label'] = m.group(1)
            r['instruction'] = '='
            r['operand'] = m.group(2).strip()
            return r

    if not code_part:
        r['type'] = 'label_only' if r['label'] else 'blank'
        return r

    # Multi-statement or single instruction
    stmts = _split_colon_stmts(code_part)
    if len(stmts) == 1:
        r['instruction'], r['operand'] = _parse_instruction(stmts[0])
    else:
        r['colon_stmts'] = [_parse_instruction(s) for s in stmts]
        r['instruction'], r['operand'] = r['colon_stmts'][0]

    r['type'] = 'label_instr' if r['label'] else 'instr'
    return r


def format_line(c, indent=INDENT, comment_col=COMMENT_COL, comment_style=None):
    """Format a classified line."""
    if c['type'] == 'blank':
        return ''

    if c['type'] == 'comment':
        text = c['comment']
        if comment_style:
            # Convert leading comment char, preserving whitespace
            stripped = text.lstrip()
            ws = text[:len(text) - len(stripped)]
            stripped = _convert_comment_char(stripped, comment_style)
            return ws + stripped
        return text

    if c['type'] == 'brace':
        return _append_comment(c['instruction'], c.get('comment'), comment_col)

    if c['type'] == 'assignment':
        code = c['label'].ljust(max(len(c['label']), ASSIGN_PAD))
        code += f" {c['instruction']} {c['operand']}"
        comment = c['comment']
        if comment_style:
            comment = _convert_comment_char(comment, comment_style)
        return _append_comment(code, comment, comment_col)

    # Build instruction text
    if c['colon_stmts']:
        instr_text = ' : '.join(
            f"{i} {o}" if o else i for i, o in c['colon_stmts']
        )
    elif c['instruction']:
        instr_text = c['instruction']
        if c['operand']:
            instr_text += ' ' + c['operand']
    else:
        instr_text = None

    # Top-level directives at column 0 — but only when not nested
    # inside a FOR/MACRO/IF block (where they're part of the body).
    instr_upper = (c['instruction'] or '').upper()
    is_toplevel = instr_upper in TOPLEVEL_DIRECTIVES and indent <= INDENT
    effective_indent = 0 if is_toplevel else indent

    # Assemble line
    if c['label'] and instr_text:
        if c['has_colon_sep']:
            code = c['label']
            pad = max(LABEL_PAD, effective_indent, len(code) + 1)
            code = code.ljust(pad) + ': ' + instr_text
        else:
            code = c['label']
            pad = max(LABEL_PAD, effective_indent, len(code) + 1)
            code = code.ljust(pad) + instr_text
    elif instr_text:
        code = ' ' * effective_indent + instr_text
    elif c['label']:
        code = c['label']
    else:
        return c['raw']

    comment = c['comment']
    if comment_style:
        comment = _convert_comment_char(comment, comment_style)
    return _append_comment(code, comment, comment_col)


def format_file(lines, indent=INDENT, comment_col=COMMENT_COL, comment_style=None):
    """Format all lines. Returns list of formatted lines."""
    result = []
    nesting = 0

    for line in lines:
        line = expand_tabs(line)
        c = classify_line(line)

        instr_upper = (c['instruction'] or '').upper()

        # Decrease nesting BEFORE formatting the closing directive
        if instr_upper in NEST_CLOSE or instr_upper in NEST_TOGGLE:
            nesting = max(0, nesting - 1)

        effective_indent = indent + indent * nesting
        formatted = format_line(c, effective_indent, comment_col, comment_style)

        # Increase nesting AFTER formatting the opening directive
        if instr_upper in NEST_OPEN or instr_upper in NEST_TOGGLE:
            nesting += 1

        result.append(formatted)
    return result


def main():
    parser = argparse.ArgumentParser(
        description='Format BeebASM 6502 assembly source files.',
        epilog='Standalone tool — no dependencies beyond Python 3.6+.',
    )
    parser.add_argument('files', nargs='+', type=Path,
                        help='Files to format')
    parser.add_argument('--check', action='store_true',
                        help='Exit 1 if changes needed (no modifications)')
    parser.add_argument('--diff', action='store_true',
                        help='Show unified diff of changes')
    parser.add_argument('--indent', type=int, default=INDENT,
                        help=f'Instruction indent (default: {INDENT})')
    parser.add_argument('--comment-col', type=int, default=COMMENT_COL,
                        help=f'Inline comment column (default: {COMMENT_COL})')
    parser.add_argument('--comment-style', choices=[';', '\\'],
                        help='Unify comment delimiter (default: preserve)')
    parser.add_argument('--stdout', action='store_true',
                        help='Write to stdout instead of modifying files')
    args = parser.parse_args()

    any_changes = False

    for path in args.files:
        if not path.exists():
            print(f"Error: {path} not found", file=sys.stderr)
            sys.exit(1)

        original = path.read_text(encoding=ENCODING).splitlines(keepends=False)
        formatted = format_file(
            original, args.indent, args.comment_col, args.comment_style,
        )

        if original != formatted:
            any_changes = True
            if args.stdout:
                print('\n'.join(formatted))
            elif args.diff:
                import difflib
                diff = difflib.unified_diff(
                    original, formatted,
                    fromfile=f'{path} (original)',
                    tofile=f'{path} (formatted)',
                    lineterm='',
                )
                print('\n'.join(diff))
            elif args.check:
                print(f'{path}: needs formatting')
            else:
                path.write_text('\n'.join(formatted) + '\n', encoding=ENCODING)
                print(f'{path}: formatted')
        elif not args.check and not args.diff:
            print(f'{path}: unchanged')

    if args.check and any_changes:
        sys.exit(1)


if __name__ == '__main__':
    main()
