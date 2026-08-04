# dotfiles

A portable macOS zsh setup: a two-line transient prompt built on liquidprompt,
fuzzy everything, and a Claude Code statusline.

## Install

Requires [oh-my-zsh](https://ohmyz.sh) as a prerequisite. This repo does not
install it: `zsh/10-ohmyzsh.zsh` silently no-ops without it, which means no
plugins at all, including all eight git aliases in the table below. Install
it first with:

```bash
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
```

```bash
git clone https://github.com/<you>/dotfiles ~/Projects/tools/dotfiles
cd ~/Projects/tools/dotfiles
brew bundle          # optional; everything degrades gracefully without it
./install.sh
exec zsh
```

`./install.sh --dry-run` shows every action without performing it.
`./install.sh --uninstall` restores the backups it made.

Existing files are moved to `<name>.bak-<timestamp>` before anything is replaced.

Two extra steps run automatically on every install, both idempotent (safe to
re-run) and both respecting `--dry-run`:

- **liquidprompt** is cloned to `~/.local/share/liquidprompt`, pinned to tag
  `v2.2.1`. This matters more than it looks: `zsh/60-prompt.zsh` looks for
  liquidprompt at exactly that path and silently does nothing if it isn't
  there — no error, no warning, just zsh's plain default prompt with no
  colour, no two-line layout, and no transient collapse. Before this step
  existed, a fresh clone of this repo produced that silent, prompt-less state
  with no indication anything was wrong. If the clone fails (no network on a
  first, offline install), the installer does not abort; it logs a warning
  and moves on, and the "Optional tools" report below will list liquidprompt
  as MISSING, with what that costs you, every time you run `./install.sh`
  until it succeeds.
- **atuin history** is imported once, from whatever shell history already
  exists, via `atuin import auto`. It only runs if `atuin` is installed and
  only if it hasn't already imported (detected by the presence of atuin's
  history database), so it is safe on every subsequent install.

After installing, `./install.sh` prints an "Optional tools" report listing
what's missing and exactly what you lose without it — including a dedicated
line for liquidprompt, since it can't be checked the same way as a command on
`$PATH`. Re-run `./install.sh` any time to see the current state, or install
everything at once with `brew bundle`.

## The prompt

```
 19:40  ~/Projects/saas  main ✚2 ⇡1  2.4s
❯ npm run build
```

Once a command runs, its prompt collapses to a bare `❯`, so scrollback stays
readable. liquidprompt supports neither two-line nor transient prompts — see
[`prompt/README.md`](prompt/README.md) for how this works.

Requires a Nerd Font. Import `iterm2/Profile.json` or set your terminal font to
**MesloLGS Nerd Font**; without it the powerline separators render as blanks.

## Git aliases you already have

oh-my-zsh's `git` plugin defines these. This repo deliberately adds no git
aliases of its own, because synonyms make them harder to remember, not easier.

| Alias | Command |
|---|---|
| `gst` | `git status` |
| `gaa` | `git add --all` |
| `gcmsg` | `git commit --message` |
| `gp` | `git push` |
| `gl` | `git pull` |
| `gco` | `git checkout` |
| `gd` | `git diff` |
| `glo` | `git log --oneline --decorate` |

> Prefer `gaa` over `git add *`. The shell expands `*` before git ever sees
> it, so it skips dotfiles (which don't match a bare `*`) and misses deleted
> files (`*` only matches things that still exist on disk). `git add --all`
> stages all three: new, modified, and deleted, dotfiles included.

## Aliases this repo adds

| Alias | Command |
|---|---|
| `..` `...` `....` | `cd ..` and further up |
| `ls` | `eza --group-directories-first --icons=auto` |
| `ll` | `eza -lah --git --group-directories-first --icons=auto` |
| `tree` | `eza --tree --level=2 --icons=auto` |
| `cat` | `bat --paging=never --style=plain` |
| `fr` | `flutter run` |
| `fbi` | `flutter build ipa --release` |
| `fc` | `flutter clean` |
| `fpg` | `flutter pub get` |
| `nrd` | `npm run dev` |

`p [query]` jumps to any project under `$PROJECTS_DIR` (default `~/Projects`),
searching two levels deep.

> **`...`/`....` shadow oh-my-zsh, and the shadowing changes their behaviour.**
> oh-my-zsh's `lib/directories.zsh` defines `...`, `....`, and further dots as
> **global** aliases (`alias -g`), which expand anywhere on a line, not just
> at the start of a command — so `cp foo ...` would expand too. This repo's
> `40-navigation.zsh` loads after oh-my-zsh (`10-` before `40-`, see load
> order below) and redefines `...`/`....` as plain, non-global aliases, which
> only expand in command position. Because the later definition replaces the
> earlier one outright — not just its value, but its type — the net effect
> after both modules load is that `...`/`....` are ordinary aliases
> throughout this setup, and `cp foo ...` does **not** expand. (Verified by
> sourcing both modules and inspecting zsh's `$galiases` vs `$aliases`
> tables directly.) `..` itself is untouched by oh-my-zsh; it only exists
> because this repo defines it.

## Load order

`zsh/zshrc` sources `zsh/[0-9][0-9]-*.zsh` in sorted order. Three constraints are
load-bearing, and **all three fail silently** when violated:

| Constraint | Why |
|---|---|
| `15-fzf.zsh` before `20-history.zsh` | Both bind `Ctrl-R`; the last one wins, and atuin must win |
| `30-completion.zsh` after `compinit`, before autosuggestions | fzf-tab must wrap the completion widget first |
| `60-prompt.zsh` last | The transient prompt binds `zle-line-init` after syntax highlighting is in place |

Do not merge `15-fzf.zsh` into `30-completion.zsh`. It looks like an obvious
tidy-up — both files deal with completion-adjacent fzf integration — and it
silently hands `Ctrl-R` back to fzf: `30-completion.zsh` loads at `30-`,
after `20-history.zsh` at `20-`, so folding fzf's key bindings into it would
invert the ordering this table exists to protect, with no error to mark the
moment it broke.

## Claude Code statusline

Add to `~/.claude/settings.json`:

```json
{ "statusLine": { "type": "command", "command": "~/.claude/statusline.sh" } }
```

Shows model, directory, git branch, session cost, and lines changed. Claude Code
exposes no context-remaining figure — only a `⚠` once the 200k threshold is
crossed. There is no way to show "73% left" or similar from this payload; the
`⚠ 200k` marker is the only signal available, and it only appears after the
threshold is already crossed, not before.

## Machine-local config

`~/.zshrc.local` is sourced last and is not tracked. Put personal paths, tokens,
and machine-specific functions there.

Note that this is *not* a general escape hatch for overriding the modules
above: `zsh/zshrc` sources every numbered module in `zsh/` before it ever
reaches `.zshrc.local`, so anything that needs to run *before* a given module
(e.g. a `PATH` entry a later module's `command -v` check depends on) cannot
live there. `.zshrc.local` is for genuinely last-word, purely personal
config: extra aliases, secrets, one-off functions — not load-order fixes.

## Tests

```bash
./tests/run.sh
```

Interactive prompt behaviour is tested through a real pty (`tests/lib/harness.py`),
because zle widgets do not run without a terminal.
