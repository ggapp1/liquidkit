#!/usr/bin/env python3
"""Every prompt segment must clear WCAG AAA (7:1) contrast.

This is a machine-checkable accessibility invariant, not a style preference.
Powerline segments carry their own background, so unlike ordinary terminal text
the contrast is fully determined by this repo -- there is no terminal theme to
blame and no reason to ship a segment that cannot be read.

It exists because eyeballing failed repeatedly. A branch name rendered green on
green and shipped; the error segment sat at 3.88:1 -- below even WCAG AA -- and
nobody noticed, because "looks fine to me" is not a measurement.

Note the ratio alone is not the whole accessibility story: a *bright* background
filling a large area is what causes glare on a dark theme, independent of its
ratio. That is why the two largest segments (path, error) use dark backgrounds
with light text -- high contrast and low glare at the same time. This test only
enforces the part that can be checked automatically.
"""
import os
import re
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "lib"))
from harness import run_tests  # noqa: E402

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
RC = os.path.join(REPO, "prompt", "liquidpromptrc")

MIN_RATIO = 7.0  # WCAG AAA for normal-size text


def xterm_rgb(n):
    """xterm-256 index -> RGB. Only 16-255 are deterministic.

    0-15 are the terminal's own ANSI palette and change with the user's theme,
    so a segment using them has no knowable contrast. None signals that.
    """
    if 16 <= n <= 231:
        n -= 16
        r, g, b = n // 36, (n // 6) % 6, n % 6
        f = lambda v: 0 if v == 0 else 55 + 40 * v  # noqa: E731
        return (f(r), f(g), f(b))
    if 232 <= n <= 255:
        v = 8 + (n - 232) * 10
        return (v, v, v)
    return None


def relative_luminance(rgb):
    def channel(c):
        c /= 255
        return c / 12.92 if c <= 0.03928 else ((c + 0.055) / 1.055) ** 2.4
    r, g, b = rgb
    return 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b)


def contrast_ratio(fg, bg):
    a, b = relative_luminance(fg), relative_luminance(bg)
    hi, lo = max(a, b), min(a, b)
    return (hi + 0.05) / (lo + 0.05)


def segments():
    """(name, fg, bg) for every POWERLINE_*_COLOR in the shipped config."""
    src = open(RC, encoding="utf-8").read()
    return [(n, int(f), int(b)) for n, f, b
            in re.findall(r"^(POWERLINE_\w+)=\((\d+) (\d+)", src, re.M)]


def test_palette_is_not_empty():
    # Guard the guard: if the regex stops matching (a format change in the rc),
    # every other test here would pass vacuously against zero segments.
    found = segments()
    assert len(found) >= 10, f"only parsed {len(found)} segments from {RC}"


def test_every_segment_meets_wcag_aaa():
    failures = []
    for name, fg, bg in segments():
        a, b = xterm_rgb(fg), xterm_rgb(bg)
        if a is None or b is None:
            continue  # covered by the system-colour test below
        r = contrast_ratio(a, b)
        if r < MIN_RATIO:
            failures.append(f"{name}: fg {fg} on bg {bg} = {r:.2f}:1")
    assert not failures, (
        "segments below WCAG AAA (%.1f:1):\n  %s" % (MIN_RATIO, "\n  ".join(failures))
    )


def test_no_segment_uses_theme_dependent_system_colours():
    # xterm 0-15 are remapped by the user's terminal theme, so a segment using
    # them has no contrast this repo can guarantee -- the measurement above
    # would be fiction.
    offenders = [f"{n}: fg {f} bg {b}" for n, f, b in segments()
                 if xterm_rgb(f) is None or xterm_rgb(b) is None]
    assert not offenders, (
        "segments using theme-dependent system colours 0-15:\n  " + "\n  ".join(offenders)
    )


if __name__ == "__main__":
    sys.exit(run_tests(globals()))
