#!/usr/bin/env python3
"""Tests for the pty harness itself. If these fail, no prompt test can be trusted."""
import os
import shutil
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "lib"))
from harness import Shell, make_zdotdir, run_tests, strip_ansi  # noqa: E402

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))


def test_strip_ansi_removes_colour_codes():
    assert strip_ansi("\x1b[38;5;141mhello\x1b[0m") == "hello"


def test_strip_ansi_removes_osc_sequences():
    assert strip_ansi("\x1b]0;title\x07text") == "text"


def test_strip_ansi_removes_osc_terminated_by_st():
    # OSC strings may be terminated by ST (ESC \) instead of BEL.
    assert strip_ansi("\x1b]0;title\x1b\\text") == "text"


def test_shell_echoes_command_output():
    # A pty locally echoes whatever bytes it's sent, at the kernel line-discipline
    # level, whether or not any process is even alive to read them -- so a literal
    # marker like "echo MARKER_ONE" would show up in the output even if zsh never
    # started at all. Force real shell *evaluation* into the marker so the
    # assertion can only be satisfied by the executed command, not the raw
    # keystroke echo of the input line (which still reads "$((20+1))" unevaluated).
    zdotdir = make_zdotdir(REPO, modules=[])
    with Shell(zdotdir) as sh:
        sh.read(1.0)
        sh.send("echo MARKER_$((20+1))\n")
        out = sh.read(1.5)
    assert "MARKER_21" in out, f"command output missing from: {out!r}"


def test_shell_loads_requested_module():
    # Same trap as above: "echo BREW_IS_$BREW_PREFIX" with BREW_PREFIX unset still
    # contains the substring "BREW_IS_", both from the raw keystroke echo and from
    # the executed (but empty) expansion -- so asserting on "BREW_IS_" alone would
    # pass even if 00-path.zsh were never sourced. Require the "/" that only a real
    # `brew --prefix` expansion produces.
    if shutil.which("brew") is None:
        return  # nothing to assert without brew, mirrors test_modules.sh's own guard
    zdotdir = make_zdotdir(REPO, modules=["00-path.zsh"])
    with Shell(zdotdir) as sh:
        sh.read(1.0)
        sh.send("echo BREW_IS_$BREW_PREFIX\n")
        out = sh.read(1.5)
    assert "BREW_IS_/" in out, f"module did not load: {out!r}"


if __name__ == "__main__":
    sys.exit(run_tests(globals()))
