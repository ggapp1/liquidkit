# liquidprompt-transient

Two-line and transient prompt support for [liquidprompt](https://github.com/liquidprompt/liquidprompt) 2.2.1,
which offers neither. Self-contained: depends on liquidprompt and nothing else.

## Use

```zsh
source /path/to/liquidprompt
source /path/to/liquidprompt-transient.plugin.zsh
```

Order matters — liquidprompt first.

## Settings

| Variable | Default | Meaning |
|---|---|---|
| `LPT_ENABLE_TWO_LINE` | `1` | Put the input mark on its own line |
| `LPT_ENABLE_TRANSIENT` | `1` | Collapse the prompt once a command runs |
| `LPT_MARK` | `%F{141}❯%f ` | The live input mark |
| `LPT_TRANSIENT_MARK` | `%F{240}❯%f ` | The collapsed mark left in scrollback |

Set them before sourcing.

## How it works

**Two-line.** liquidprompt assigns `PS1` from `__lp_set_prompt`, registered in
`precmd_functions`. Appending our own hook after it means ours runs last and
receives the finished bar, so we can append a newline and the mark.

`LP_PS1_POSTFIX` cannot be used: the powerline theme renders it as a coloured
section *inside* the bar (`powerline.theme:338`), so it cannot carry a newline.

**Transient.** Takes over `zle-line-init` and runs the line editor through
`zle .recursive-edit`, then repaints with a collapsed prompt before accepting.
This is the technique starship uses.

## What does not work

`add-zle-hook-widget line-finish` is the obvious approach and **does nothing at
all** — no error, no effect, the prompt simply never collapses. Recorded here so
nobody rediscovers it.

## Bracketed paste

Taking over `zle-line-init` and driving the editor through `.recursive-edit`
moves the actual typing window outside zsh's normal bracketed-paste pairing.
zsh only wraps its *own* built-in line-init/line-finish with the
enable/disable escape sequences — it enables bracketed paste once
`zle-line-init` returns, and this plugin never lets it return until the line
is finished, because `.recursive-edit` runs the entire edit session from
inside our own `zle-line-init` widget. Verified with a raw escape-sequence
trace: without an explicit fix, paste mode is **off** for the entire time the
user is typing, where normally it would be on. The practical effect is bad —
pasting multi-line text has each line auto-executed as soon as it's inserted,
instead of landing in the buffer as a block of text — so the plugin
explicitly re-enables bracketed paste around the `.recursive-edit` call
(`$zle_bracketed_paste[1]` before, `$zle_bracketed_paste[2]` after), the same
fix starship uses for the same underlying reason.

## vi-mode

Supported, verified, no opt-out needed. `.recursive-edit` was the highest-risk
interaction to check, since it could plausibly conflict with `zle-vi-cmd-mode`
internals — tested directly with `bindkey -v`: normal-mode motions (`Esc`,
`0`, `I`) work, multiple commands in a row work, and `zle .accept-line`
correctly accepts the line regardless of whether the editor is left in
`vicmd` or `viins` state when `.recursive-edit` returns. No vi-specific
branch exists in the plugin because none was needed.

## Compatibility

Composes with zsh-autosuggestions and zsh-syntax-highlighting; both are covered
by the test suite. An existing `zle-line-init` binding is preserved and called
first rather than clobbered.
