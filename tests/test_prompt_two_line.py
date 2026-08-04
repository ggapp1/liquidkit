#!/usr/bin/env python3
"""The prompt must occupy two lines: powerline bar, then a bare input mark."""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "lib"))
from harness import (Shell, find_liquidprompt, make_zdotdir,  # noqa: E402
                     run_tests, strip_ansi)

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
LIQUIDPROMPT = find_liquidprompt()

if LIQUIDPROMPT is None:
    print("  SKIP liquidprompt is not installed")
    sys.exit(0)

# Source the repo's own liquidpromptrc rather than ~/.config, so this test does
# not depend on install.sh having already run.
EXTRA = f"""
source {os.path.join(REPO, 'prompt', 'liquidpromptrc')!r}
source {LIQUIDPROMPT!r}
LPT_ENABLE_TRANSIENT=0
source {os.path.join(REPO, 'prompt', 'liquidprompt-transient.plugin.zsh')!r}
"""


def test_ps1_contains_newline():
    zdotdir = make_zdotdir(REPO, modules=[], extra=EXTRA)
    with Shell(zdotdir) as sh:
        sh.read(2.0)
        sh.send("print -rn -- $PS1 > $ZDOTDIR/ps1.raw\n")
        sh.read(1.0)
        with open(os.path.join(zdotdir, "ps1.raw"), encoding="utf-8") as fh:
            ps1 = fh.read()
    assert "\n" in ps1, f"PS1 has no newline, so it is not two lines: {ps1!r}"


def test_mark_is_last_and_after_the_newline():
    zdotdir = make_zdotdir(REPO, modules=[], extra=EXTRA)
    with Shell(zdotdir) as sh:
        sh.read(2.0)
        sh.send("print -rn -- $PS1 > $ZDOTDIR/ps1.raw\n")
        sh.read(1.0)
        with open(os.path.join(zdotdir, "ps1.raw"), encoding="utf-8") as fh:
            ps1 = fh.read()
    tail = ps1.rsplit("\n", 1)[-1]
    assert "❯" in tail, f"input mark not on the second line: {tail!r}"


def test_two_line_can_be_disabled():
    extra = EXTRA.replace("LPT_ENABLE_TRANSIENT=0",
                          "LPT_ENABLE_TRANSIENT=0\nLPT_ENABLE_TWO_LINE=0")
    zdotdir = make_zdotdir(REPO, modules=[], extra=extra)
    with Shell(zdotdir) as sh:
        sh.read(2.0)
        sh.send("print -rn -- $PS1 > $ZDOTDIR/ps1.raw\n")
        sh.read(1.0)
        with open(os.path.join(zdotdir, "ps1.raw"), encoding="utf-8") as fh:
            ps1 = fh.read()
    assert "\n" not in ps1, f"two-line disabled but PS1 still wraps: {ps1!r}"


def test_commands_still_run():
    zdotdir = make_zdotdir(REPO, modules=[], extra=EXTRA)
    with Shell(zdotdir) as sh:
        sh.read(2.0)
        sh.send("echo TWO_LINE_OK\n")
        out = strip_ansi(sh.read(1.5))
    assert "TWO_LINE_OK" in out, f"shell became unusable: {out!r}"


if __name__ == "__main__":
    sys.exit(run_tests(globals()))
