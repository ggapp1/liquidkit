#!/usr/bin/env python3
"""Executed commands must leave a collapsed prompt behind, not the full bar."""
import os
import re
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
    # zle-vi-cmd-mode. Empirically checked and found to work, including real
    # normal-mode motions (Esc/0/I) and across multiple commands, so this test
    # locks that finding in rather than leaving it a guess. See the "vi-mode"
    # section of ../prompt/README.md for what was verified.
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
    # `Shell.read()` performs a real os.read() and therefore drains the pty's
    # kernel buffer: whatever was printed during a window that gets read but
    # not accumulated into `out` is gone for good, not just unread -- no later
    # read() can ever see it again. A previous version of this test read the
    # 0.8s window right after Ctrl-C (exactly where a wrongly-executed
    # NEVER_RUN would print) and discarded it, capturing only what came after
    # the *next* command was sent. That made the assertion below structurally
    # unable to catch the regression it exists to catch -- confirmed by
    # re-applying the "unconditional accept-line" break to the real plugin
    # and observing the discarding version pass all three times regardless.
    # Every window from the moment Ctrl-C is sent is now accumulated into
    # `out`.
    zdotdir = make_zdotdir(REPO, modules=[], extra=EXTRA)
    with Shell(zdotdir) as sh:
        sh.read(2.0)
        sh.send("echo NEVER_RUN")
        sh.read(0.6)
        sh.send("\x03")                    # Ctrl-C
        raw = sh.read(0.8)                 # capture, do not discard
        sh.send("echo AFTER_INTERRUPT_$((6*7))\n")
        raw += sh.read(2.0)
    out = strip_ansi(raw)
    # A computed value, not a keystroke echo of anything we sent, so the pty
    # echoing our own typed text back at us cannot satisfy this assertion --
    # same reasoning as the multiline/RPROMPT tests above.
    assert "AFTER_INTERRUPT_42" in out, f"shell unusable after Ctrl-C: {out!r}"
    # strip_ansi deletes every bare "\r" (see its regex), so a prior version
    # of this check -- "NEVER_RUN\r" not in out -- could never fail: there is
    # no "\r" left in `out` at all, stripped or not. strip_ansi does collapse
    # "\r\n" down to "\n" though, so real command *output* from `echo` still
    # shows up as a line by itself, bounded by newlines on both sides; the
    # merely-typed "echo NEVER_RUN" text never does, because "echo " sits on
    # the same line immediately before it. That is what distinguishes "it was
    # typed" from "it was executed".
    assert not re.search(r"^NEVER_RUN$", out, re.M), \
        f"interrupted command was executed anyway: {out!r}"


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


def test_rprompt_survives_a_command():
    # liquidprompt 2.2.1 assigns only PS1, never RPROMPT/RPS1 (grep confirms
    # neither name appears in liquidprompt or its themes) -- so nothing
    # rebuilds RPROMPT on the next precmd. If the plugin blanks it for the
    # collapsed view without restoring it, a user-set RPROMPT disappears
    # permanently after the very first command. Read via file redirection,
    # not pty output, so this depends on real shell state, not typed text.
    extra = EXTRA + "\nRPROMPT='XRIGHTX'\n"
    zdotdir = make_zdotdir(REPO, modules=[], extra=extra)
    with Shell(zdotdir) as sh:
        sh.read(2.0)
        sh.send("print -rn -- $RPROMPT > $ZDOTDIR/rprompt.before\n")
        sh.read(1.0)
        sh.send("echo COMMAND_ONE\n")
        sh.read(1.5)
        sh.send("print -rn -- $RPROMPT > $ZDOTDIR/rprompt.after\n")
        sh.read(1.0)
        with open(os.path.join(zdotdir, "rprompt.before"), encoding="utf-8") as fh:
            before = fh.read()
        with open(os.path.join(zdotdir, "rprompt.after"), encoding="utf-8") as fh:
            after = fh.read()
    assert before == "XRIGHTX", f"RPROMPT not set before any command ran: {before!r}"
    assert after == "XRIGHTX", f"RPROMPT lost after a command: {after!r}"


def test_sourcing_twice_stays_functional():
    # A plain `source ~/.zshrc` reload -- the ordinary way people reload their
    # shell -- sources this plugin a second time. Re-aliasing the transient
    # widget to itself would recurse ("maximum nested function level
    # reached"), leaving transient dead (or the shell unusable) from then on.
    extra = EXTRA + (
        f"\nsource {os.path.join(REPO, 'prompt', 'liquidprompt-transient.plugin.zsh')!r}\n"
    )
    zdotdir = make_zdotdir(REPO, modules=[], extra=extra)
    with Shell(zdotdir) as sh:
        sh.read(2.0)
        sh.send("echo DOUBLE_SOURCED\n")
        out = strip_ansi(sh.read(2.0))
    assert "nested function level" not in out.lower(), \
        f"double-sourcing caused zle recursion: {out!r}"
    assert "XCOLLAPSEDX" in out, f"transient broke after double-sourcing: {out!r}"
    assert "DOUBLE_SOURCED" in out, "command output missing after double-sourcing"


def test_sourcing_twice_does_not_duplicate_mark():
    # Companion to the above, isolating the two-line hook specifically: with
    # transient OFF, PS1 is never overwritten by the collapse logic, so it can
    # be inspected directly (as test_prompt_two_line.py does) to confirm a
    # second sourcing did not append a second copy of the second-line hook.
    extra = EXTRA.replace("LPT_TRANSIENT_MARK='XCOLLAPSEDX '",
                          "LPT_TRANSIENT_MARK='XCOLLAPSEDX '\nLPT_ENABLE_TRANSIENT=0")
    extra += f"\nsource {os.path.join(REPO, 'prompt', 'liquidprompt-transient.plugin.zsh')!r}\n"
    zdotdir = make_zdotdir(REPO, modules=[], extra=extra)
    with Shell(zdotdir) as sh:
        sh.read(2.0)
        sh.send("print -rn -- $PS1 > $ZDOTDIR/ps1.raw\n")
        sh.read(1.0)
        with open(os.path.join(zdotdir, "ps1.raw"), encoding="utf-8") as fh:
            ps1 = fh.read()
    assert ps1.count("❯") == 1, f"duplicate second-line mark after re-sourcing: {ps1!r}"


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
