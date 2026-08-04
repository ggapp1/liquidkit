#!/usr/bin/env python3
"""Executed commands must leave a collapsed prompt behind, not the full bar."""
import os
import sys
import time

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "lib"))
from harness import (Shell, find_liquidprompt, make_zdotdir,  # noqa: E402
                     run_tests, strip_ansi)

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
LIQUIDPROMPT = find_liquidprompt()

if LIQUIDPROMPT is None:
    print("  SKIP liquidprompt is not installed")
    sys.exit(0)

# A distinctive mark makes assertions unambiguous in raw terminal output.
EXTRA = f"""
source {os.path.join(REPO, 'prompt', 'liquidpromptrc')!r}
source {LIQUIDPROMPT!r}
LPT_TRANSIENT_MARK='XCOLLAPSEDX '
source {os.path.join(REPO, 'prompt', 'liquidprompt-transient.plugin.zsh')!r}
"""


def test_prompt_collapses_after_command():
    zdotdir = make_zdotdir(REPO, modules=[], extra=EXTRA)
    with Shell(zdotdir) as sh:
        sh.read(2.0)
        sh.send("echo ALPHA\n")
        out = sh.read(2.0)
    assert "XCOLLAPSEDX" in out, f"prompt did not collapse: {strip_ansi(out)!r}"
    assert "ALPHA" in out, "command output missing"


def test_prompt_collapses_after_command_vi_mode():
    # Spec risk #2: .recursive-edit could in principle conflict with
    # zle-vi-cmd-mode. Empirically checked (see task-8-report.md) and found to
    # work, including real normal-mode motions (Esc/0/I) and across multiple
    # commands, so this test locks that finding in rather than leaving it a
    # guess.
    zdotdir = make_zdotdir(REPO, modules=[], extra=EXTRA + "\nbindkey -v\n")
    with Shell(zdotdir) as sh:
        sh.read(2.0)
        sh.send("echo VIMODE\n")
        out = sh.read(2.0)
    assert "XCOLLAPSEDX" in out, f"prompt did not collapse under vi-mode: {strip_ansi(out)!r}"
    assert "VIMODE" in out, "command output missing under vi-mode"


def test_collapses_once_per_command():
    zdotdir = make_zdotdir(REPO, modules=[], extra=EXTRA)
    with Shell(zdotdir) as sh:
        sh.read(2.0)
        sh.send("echo ONE\n")
        sh.read(1.5)
        sh.send("echo TWO\n")
        out = sh.read(1.5)
    assert out.count("XCOLLAPSEDX") >= 1, "second command did not collapse"


def test_multiline_command_still_runs():
    # 13 commands in the author's history end with a trailing backslash, always
    # preceded by a space (e.g. "gh release create ... \" / "  --notes-file ...").
    # zsh's line-continuation elides the backslash and the newline with no
    # inserted whitespace, so the sent text must supply that space itself, or
    # the continued words legitimately concatenate with none (verified against
    # a bare zsh with no plugin loaded at all: "MULTI\" + "LINE_OK" -> "MULTILINE_OK").
    zdotdir = make_zdotdir(REPO, modules=[], extra=EXTRA)
    with Shell(zdotdir) as sh:
        sh.read(2.0)
        sh.send("echo MULTI \\\n")
        sh.read(0.6)
        sh.send("LINE_OK\n")
        out = strip_ansi(sh.read(2.0))
    assert "MULTI LINE_OK" in out, f"multi-line command broke: {out!r}"


def test_ctrl_c_does_not_hang_shell():
    zdotdir = make_zdotdir(REPO, modules=[], extra=EXTRA)
    with Shell(zdotdir) as sh:
        sh.read(2.0)
        sh.send("echo NEVER_RUN")
        sh.send("\x03")                    # Ctrl-C
        sh.read(0.8)
        sh.send("echo AFTER_INTERRUPT\n")
        out = strip_ansi(sh.read(2.0))
    assert "AFTER_INTERRUPT" in out, f"shell unusable after Ctrl-C: {out!r}"
    assert "NEVER_RUN\r" not in out, "interrupted command was executed anyway"


def test_ctrl_d_exits_cleanly():
    # Checking for a leaked error string alone is not enough: a plugin that
    # silently swallows Ctrl-D (leaving the shell running forever) would also
    # print no error, so this must independently confirm the process actually
    # terminated -- checked *before* Shell.close(), which sends its own
    # "exit\n" and would otherwise mask a hang.
    zdotdir = make_zdotdir(REPO, modules=[], extra=EXTRA)
    sh = Shell(zdotdir)
    sh.read(2.0)
    sh.send("\x04")                        # Ctrl-D on an empty line
    out = sh.read(1.5)
    exited = False
    for _ in range(15):
        pid, _ = os.waitpid(sh.pid, os.WNOHANG)
        if pid == sh.pid:
            exited = True
            break
        time.sleep(0.1)
    sh.close()
    assert "recursive-edit" not in out.lower(), f"zle error leaked on Ctrl-D: {out!r}"
    assert exited, "shell process did not terminate after Ctrl-D on an empty line"


def test_transient_can_be_disabled():
    extra = EXTRA.replace("LPT_TRANSIENT_MARK='XCOLLAPSEDX '",
                          "LPT_TRANSIENT_MARK='XCOLLAPSEDX '\nLPT_ENABLE_TRANSIENT=0")
    zdotdir = make_zdotdir(REPO, modules=[], extra=extra)
    with Shell(zdotdir) as sh:
        sh.read(2.0)
        sh.send("echo BETA\n")
        out = sh.read(2.0)
    assert "XCOLLAPSEDX" not in out, "transient disabled but prompt still collapsed"
    assert "BETA" in out, "command output missing"


def test_coexists_with_syntax_highlighting():
    brew = os.popen("brew --prefix 2>/dev/null").read().strip()
    hl = f"{brew}/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"
    if not brew or not os.path.exists(hl):
        print("  SKIP zsh-syntax-highlighting not installed")
        return
    extra = EXTRA + f"\nsource {hl!r}\n"
    zdotdir = make_zdotdir(REPO, modules=[], extra=extra)
    with Shell(zdotdir) as sh:
        sh.read(2.0)
        sh.send("echo GAMMA\n")
        out = sh.read(2.0)
    assert "XCOLLAPSEDX" in out, "transient broke under syntax highlighting"
    assert "GAMMA" in out, "command output missing"


if __name__ == "__main__":
    sys.exit(run_tests(globals()))
