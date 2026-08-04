# liquidkit

**A two-line transient zsh prompt for [liquidprompt](https://github.com/liquidprompt/liquidprompt), on macOS** — plus `atuin`, `fzf-tab` and `zoxide`, wired in the right order.

[![ci](https://github.com/ggapp1/liquidkit/actions/workflows/ci.yml/badge.svg)](https://github.com/ggapp1/liquidkit/actions/workflows/ci.yml)
![platform: macOS](https://img.shields.io/badge/platform-macOS-lightgrey)
![shell: zsh](https://img.shields.io/badge/shell-zsh-89e051)

liquidprompt has no transient prompt and no two-line mode. This adds both **on
top of it**, without patching it — so you keep liquidprompt's segments and
config and still get a prompt that gets out of the way. Around that sits a
complete zsh setup: `eza`, `bat`, a Claude Code statusline, an installer that
backs up everything it touches, and 75 tests.

```
 19:40  ~/Projects/saas  main ✚2 ⇡1  2.4s
❯ npm run build
```

…and once that command runs, its prompt collapses to just `❯ npm run build`, so
a long session's scrollback stays readable instead of repeating a full status
bar forty times.

<!-- Add a real screenshot here — it is the single biggest thing you can do for
     adoption. A terminal recording (asciinema / vhs) showing the collapse in
     action is better still. Colour is the product; ASCII can't show it. -->

## Why

[powerlevel10k](https://github.com/romkatv/powerlevel10k) and
[starship](https://starship.rs) both have transient prompts. liquidprompt does
not — and if you're already on liquidprompt, switching themes to get one means
giving up its segment set and config. This repo adds transient and two-line
support **on top of** liquidprompt 2.2.1, without patching it.

| | this repo | powerlevel10k | starship |
|---|---|---|---|
| Transient prompt | ✅ (added here) | ✅ built-in | ✅ `enable_transience` |
| Built on liquidprompt | ✅ | ❌ | ❌ |
| Keeps liquidprompt's config | ✅ | ❌ | ❌ |
| Standalone plugin | ✅ [`prompt/`](prompt/) | n/a | n/a |

The prompt module is dependency-free and extractable — see
[`prompt/README.md`](prompt/README.md) if you only want that part.

## Features

- **Transient prompt** — old prompts collapse to `❯`; clean scrollback
- **Two-line layout** — full width to type, however long the path
- **`Ctrl-R` → atuin** — SQLite history with dir, exit code and duration
- **`Tab` → fzf-tab** — fuzzy completions with previews (`eza` trees, `bat` files, `git diff`)
- **`p <query>`** — jump to any project two levels under `~/Projects`
- **Claude Code statusline** — model, dir, branch, session cost, lines changed
- **Safe installer** — timestamped backups, `--dry-run`, `--uninstall`
- **Degrades gracefully** — every tool is optional; missing ones no-op, never error
- **75 tests**, including a real-pty harness for the zle code

## Requirements

- **macOS** (Intel or Apple Silicon — the Homebrew prefix is resolved, not hardcoded)
- **zsh** and [**oh-my-zsh**](https://ohmyz.sh) — not installed by this repo
- **A Nerd Font** — without one the powerline separators render as blank space

```bash
# oh-my-zsh, if you don't have it
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
```

## Install

```bash
git clone https://github.com/ggapp1/liquidkit ~/liquidkit
cd ~/liquidkit
brew bundle            # optional — everything degrades gracefully without it
./install.sh --dry-run # see every action first
./install.sh
exec zsh
```

Set your terminal font to **MesloLGS Nerd Font**, or import
[`iterm2/Profile.json`](iterm2/Profile.json).

**Nothing is destroyed.** Every file `install.sh` replaces is moved to
`<name>.bak-<timestamp>` first, and `./install.sh --uninstall` puts them back.
Re-running is always safe.

The installer also clones liquidprompt (pinned to `v2.2.1`) and, if `atuin` is
present, imports your existing shell history once. It finishes by printing an
**Optional tools** report saying what's missing and exactly what each absence
costs you.

<details>
<summary>Why liquidprompt is cloned rather than installed from Homebrew</summary>

Homebrew ships liquidprompt 2.3.0; this repo pins `v2.2.1`, because the
transient plugin hooks `powerline_full`'s internals and those were verified
against that version. Installing both would put two copies on disk and
reintroduce exactly the version drift the pin exists to prevent.

`zsh/60-prompt.zsh` looks for liquidprompt at `~/.local/share/liquidprompt` and
**silently does nothing** if it isn't there — no error, just zsh's plain default
prompt. If the clone fails (offline first install), the installer logs a warning
rather than aborting, and the Optional tools report keeps flagging it until it
succeeds.
</details>

## Aliases

### Git aliases you already have

oh-my-zsh's `git` plugin defines these. **This repo deliberately adds none of
its own** — a fifth name for something that already has three makes it harder to
remember, not easier.

| Alias | Command | | Alias | Command |
|---|---|---|---|---|
| `gst` | `git status` | | `gl` | `git pull` |
| `gaa` | `git add --all` | | `gco` | `git checkout` |
| `gcmsg` | `git commit --message` | | `gd` | `git diff` |
| `gp` | `git push` | | `glo` | `git log --oneline --decorate` |

> **Prefer `gaa` over `git add *`.** The shell expands `*` before git sees it, so
> it skips dotfiles and misses deleted files. `git add --all` stages new,
> modified and deleted — dotfiles included.

### Aliases this repo adds

| Alias | Command |
|---|---|
| `..` `...` `....` | `cd ..` and further up |
| `ls` | `eza --group-directories-first --icons=auto` |
| `ll` | `eza -lah --git --group-directories-first --icons=auto` |
| `tree` | `eza --tree --level=2 --icons=auto` |
| `cat` | `bat --paging=never --style=plain` |
| `fr` `fbi` `fc` `fpg` | `flutter run` / `build ipa --release` / `clean` / `pub get` |
| `nrd` | `npm run dev` |

Every one is guarded on its binary existing. `p [query]` jumps to any project
under `$PROJECTS_DIR` (default `~/Projects`), searching two levels deep.

<details>
<summary><code>...</code> and <code>....</code> shadow oh-my-zsh, and that changes their behaviour</summary>

oh-my-zsh's `lib/directories.zsh` defines `...`, `....` and further dots as
**global** aliases (`alias -g`), which expand anywhere on a line — so `cp foo ...`
would expand too. This repo's `40-navigation.zsh` loads later and redefines
`...`/`....` as plain, non-global aliases, which only expand in command position.

The later definition replaces the earlier one outright — not just its value, its
type — so after both modules load, `...`/`....` are ordinary aliases and
`cp foo ...` does **not** expand. (Verified by sourcing both modules and
inspecting zsh's `$galiases` and `$aliases` tables directly.)

`..` is untouched by oh-my-zsh; it exists only because this repo defines it.
</details>

## Claude Code statusline

Add to `~/.claude/settings.json`:

```json
{ "statusLine": { "type": "command", "command": "~/.claude/statusline.sh" } }
```

```
Opus 5 | liquidkit main | $1.23 | +42/-7
```

Model, directory, git branch, session cost and lines changed — colourised, and
honouring [`NO_COLOR`](https://no-color.org).

Hide the cost segment by setting `LIQUIDKIT_STATUSLINE_COST=0` in the command:

```json
{ "statusLine": { "type": "command",
                  "command": "LIQUIDKIT_STATUSLINE_COST=0 ~/.claude/statusline.sh" } }
```

Two display details worth knowing:

- In a **git worktree**, directories are conventionally named after their branch,
  so `dir + branch` reads as a stutter (`api feat/api`). When the branch's last
  segment matches the directory, only the branch is shown — it carries strictly
  more information.
- In `$HOME` the directory shows as `~`, not your username.

> Claude Code's status payload exposes **no context-remaining figure** — there is
> no way to render "73% left". A `⚠ 200k` marker is the only signal available,
> and it appears only after the threshold is already crossed.

## Configuration

`~/.zshrc.local` is sourced last and never tracked. Put personal paths, tokens
and one-off functions there.

It is **not** a general override hook: `zsh/zshrc` sources every numbered module
before reaching it, so anything that must run *before* a module — a `PATH` entry
a later `command -v` check depends on, say — cannot live there.

## How it works

`zsh/zshrc` sources `zsh/[0-9][0-9]-*.zsh` in sorted order:

| Module | Does |
|---|---|
| `00-path` | `PATH`, resolves `$BREW_PREFIX` |
| `10-ohmyzsh` | oh-my-zsh + plugins (`git`, `flutter`, `uv`, …) |
| `15-fzf` | fzf key bindings and completion |
| `20-history` | `HIST_*` options, atuin |
| `30-completion` | `compinit`, fzf-tab previews |
| `40-navigation` | zoxide, `..`, the `p` jumper |
| `50-aliases` | eza/bat/flutter/npm aliases |
| `60-prompt` | autosuggestions, syntax highlighting, liquidprompt, transient plugin |

**Three ordering constraints are load-bearing, and all three fail silently:**

| Constraint | Why |
|---|---|
| `15-fzf` before `20-history` | Both bind `Ctrl-R`; last wins, and atuin must win |
| `30-completion` after `compinit`, before autosuggestions | fzf-tab must wrap the completion widget first |
| `60-prompt` last | Transient binds `zle-line-init` after syntax highlighting is in place |

> **Do not merge `15-fzf.zsh` into `30-completion.zsh`.** It looks like an obvious
> tidy-up — both deal with fzf — and it silently hands `Ctrl-R` back to fzf,
> because `30-` loads after `20-`. No error marks the moment it breaks.

## Troubleshooting

**The prompt shows blank gaps instead of separators.**
Your font has no Nerd Font glyphs. Set the terminal font to MesloLGS Nerd Font.

**`Ctrl-R` opens fzf, not atuin.**
Load order is inverted — check `15-fzf.zsh` still sorts before `20-history.zsh`.

**No colours, no two-line prompt, nothing.**
liquidprompt isn't at `~/.local/share/liquidprompt`. Re-run `./install.sh` and
read the Optional tools report.

**I want out.**
`./install.sh --uninstall` restores the backups it made.

## Tests

```bash
./tests/run.sh    # 75 tests, ~70s
```

Interactive prompt behaviour runs against a **real pty**
([`tests/lib/harness.py`](tests/lib/harness.py)) — zle widgets don't execute
without a terminal, so there is no other way to test them honestly.

## Credits

Built on [oh-my-zsh](https://ohmyz.sh) and
[liquidprompt](https://github.com/liquidprompt/liquidprompt). The transient
prompt technique is the one [starship](https://starship.rs) uses:
`zle-line-init` plus `.recursive-edit`.

## License

MIT — see [LICENSE](LICENSE).
