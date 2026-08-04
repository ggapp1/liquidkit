#!/usr/bin/env python3
"""zsh/60-prompt.zsh's trailing conditional must not leave a nonzero exit
status on `source` when the transient plugin file is absent.

This is a load-safety test, not a prompt-behaviour test (see
test_prompt_transient.py / test_prompt_two_line.py for those, which source
liquidprompt directly and bypass this module entirely). It exists because
the module's own guard makes the bug hard to reach:

    LIQUIDPROMPT_DIR="${LIQUIDPROMPT_DIR:-$HOME/.local/share/liquidprompt}"
    [[ $- == *i* && -r "$LIQUIDPROMPT_DIR/liquidprompt" ]] || return 0
    source "$LIQUIDPROMPT_DIR/liquidprompt"

    # Two-line and transient behaviour. Must come after liquidprompt.
    [[ -r "$DOTFILES_DIR/prompt/liquidprompt-transient.plugin.zsh" ]] \\
      && source "$DOTFILES_DIR/prompt/liquidprompt-transient.plugin.zsh"

`$- == *i*` is false in a non-interactive `zsh -c`, so the module always
takes the early `return 0` there -- the trailing conditional at the end of
the file is never even reached. That is exactly why the existing
test_prompt_module_sources_cleanly_without_liquidprompt in test_modules.sh
cannot catch a regression here: it uses `zsh -c` and LIQUIDPROMPT_DIR=
/nonexistent, both of which take the SAME early return, never the trailing
one. Reaching the trailing conditional needs all three at once: an
interactive shell, a readable $LIQUIDPROMPT_DIR/liquidprompt, and the
plugin file absent from $DOTFILES_DIR/prompt/ -- this file's Shell (a real
pty, so `$-` genuinely contains `i`), a stub liquidprompt file, and a
scratch $DOTFILES_DIR whose prompt/ subdirectory is empty, all three at
once.

The exit status of `source` -- not whether the interactive session as a
whole "aborts" -- is what's asserted: a real interactive .zshrc loop does
not run under `set -e` (that would kill the terminal on every mistyped
command), so the observable, caller-visible symptom this bug produces
inside a real shell is `source zsh/60-prompt.zsh`'s own nonzero exit status,
exactly as it would be observed by any future caller that does check it
(the way tests/test_modules.sh's `zsh -c "set -e; ...; source ...` wrapper
already does for every other module).
"""
import os
import shutil
import sys
import tempfile

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "lib"))
from harness import Shell, make_zdotdir, run_tests, strip_ansi  # noqa: E402

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
MODULE = os.path.join(REPO, "zsh", "60-prompt.zsh")


def _scratch_env():
    """Build a scratch (dotfiles_dir, liquidprompt_dir) satisfying the two
    non-interactivity-independent preconditions:

    dotfiles_dir: a throwaway directory with an empty prompt/ subdirectory,
    so $DOTFILES_DIR/prompt/liquidprompt-transient.plugin.zsh does not
    exist -- the exact branch the bug lives in. Never the real repo: the
    real repo always has that file, which would take the OTHER branch and
    prove nothing about this one.

    liquidprompt_dir: a throwaway directory containing a minimal, harmless,
    readable stand-in for liquidprompt, so the module's first guard passes
    and execution actually reaches the trailing conditional at all. A real
    liquidprompt clone is not needed and is not used -- this test does not
    depend on liquidprompt being installed, unlike test_prompt_transient.py
    and test_prompt_two_line.py.
    """
    tmp = tempfile.mkdtemp(prefix="dotfiles-60prompt-test-")
    dotfiles_dir = os.path.join(tmp, "dotfiles")
    os.makedirs(os.path.join(dotfiles_dir, "prompt"))
    liquidprompt_dir = os.path.join(tmp, "liquidprompt")
    os.makedirs(liquidprompt_dir)
    with open(os.path.join(liquidprompt_dir, "liquidprompt"), "w") as fh:
        fh.write("# stub liquidprompt for tests/test_prompt_module_load.py: "
                  "minimal, readable, a harmless no-op when sourced.\n")
    return tmp, dotfiles_dir, liquidprompt_dir


def test_sources_cleanly_when_transient_plugin_file_is_absent():
    tmp, dotfiles_dir, liquidprompt_dir = _scratch_env()
    try:
        extra = f"""
DOTFILES_DIR={dotfiles_dir!r}
LIQUIDPROMPT_DIR={liquidprompt_dir!r}
source {MODULE!r}
print -r -- "PROMPT_MODULE_SOURCE_EXIT:$?"
"""
        zdotdir = make_zdotdir(REPO, modules=[], extra=extra)
        with Shell(zdotdir) as sh:
            out = strip_ansi(sh.read(2.0))
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    assert "PROMPT_MODULE_SOURCE_EXIT:0" in out, (
        "sourcing 60-prompt.zsh left a nonzero exit status when the "
        f"transient plugin file is absent (interactive shell): {out!r}"
    )


if __name__ == "__main__":
    sys.exit(run_tests(globals()))
