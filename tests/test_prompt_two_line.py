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
# Reproduce a real install rather than sourcing the rc by hand.
#
# liquidprompt sources its own config from ${XDG_CONFIG_HOME:-$HOME/.config},
# from *inside* itself, once its internals exist. Sourcing the rc beforehand --
# as this fixture used to -- means the powerline theme file gets sourced before
# liquidprompt is loaded, so it cannot register, `lp_theme` is not yet defined,
# and liquidprompt silently falls back to its default bracket theme. Every
# prompt test then exercises the wrong theme without ever failing, which is
# exactly how a missing-theme bug shipped past the whole suite.
#
# Shell.make_zdotdir points HOME at the throwaway dir, so dropping the rc at
# $HOME/.config/liquidpromptrc is what an installed setup looks like.
EXTRA = f"""
LIQUIDPROMPT_DIR={os.path.dirname(LIQUIDPROMPT)!r}
mkdir -p $HOME/.config
ln -sf {os.path.join(REPO, 'prompt', 'liquidpromptrc')!r} $HOME/.config/liquidpromptrc
source {LIQUIDPROMPT!r}
LPT_ENABLE_TRANSIENT=0
source {os.path.join(REPO, 'prompt', 'liquidprompt-transient.plugin.zsh')!r}
"""


def _capture_ps1(extra=EXTRA):
    zdotdir = make_zdotdir(REPO, modules=[], extra=extra)
    with Shell(zdotdir) as sh:
        sh.read(2.0)
        sh.send("print -rn -- $PS1 > $ZDOTDIR/ps1.raw\n")
        sh.read(1.0)
        with open(os.path.join(zdotdir, "ps1.raw"), encoding="utf-8") as fh:
            return fh.read()


def test_powerline_theme_is_actually_active():
    # Regression guard for a bug that shipped past all 75 other tests: setting
    # LP_THEME=powerline_full does NOT activate the theme on its own, and
    # neither does sourcing the theme file -- lp_theme must also be called.
    # When it isn't, liquidprompt silently falls back to its default bracket
    # theme (`[user:/path]`), every POWERLINE_* colour is ignored, and nothing
    # is printed to say why. The other prompt tests all still passed, because
    # they assert on the newline and the collapse, never on the bar itself.
    ps1 = _capture_ps1()
    assert "" in ps1, (
        "no U+E0B0 powerline separator in PS1 - liquidprompt fell back to its "
        f"default theme: {strip_ansi(ps1)!r}"
    )
    assert "" in ps1, (
        "no U+E0B1 soft separator in PS1 - powerline path segments missing: "
        f"{strip_ansi(ps1)!r}"
    )
    assert "48;5;" in ps1, (
        f"no 256-colour background segments in PS1: {strip_ansi(ps1)!r}"
    )


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
    # A pty echoes typed keystrokes (and ZLE redraws them as-you-type) whether or
    # not the command is ever executed, so asserting a literal that also appears
    # in the sent text proves nothing (see tests/test_harness.py). Force real
    # shell *evaluation* into the marker: "TWO_LINE_OK_42" never appears in the
    # keystrokes we send, only in what the shell computes and prints.
    zdotdir = make_zdotdir(REPO, modules=[], extra=EXTRA)
    with Shell(zdotdir) as sh:
        sh.read(2.0)
        sh.send("echo TWO_LINE_OK_$((40+2))\n")
        out = strip_ansi(sh.read(1.5))
    assert "TWO_LINE_OK_42" in out, f"shell became unusable: {out!r}"


if __name__ == "__main__":
    sys.exit(run_tests(globals()))
