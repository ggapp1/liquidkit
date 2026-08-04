# Directory navigation.

# zoxide: `z <partial>` jumps to a frecently-used directory.
command -v zoxide >/dev/null 2>&1 && eval "$(zoxide init zsh)"

# Parent-directory shortcuts. oh-my-zsh does not define these, and `cd ..` is
# the second most-used command in the author's history.
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'

# p [query] - jump to a project.
#
# Projects live two levels deep: $PROJECTS_DIR/<category>/<project>.
# With a query that matches exactly one directory, jump straight there;
# otherwise hand the candidates to fzf. Without fzf, print them and stop.
p() {
  local root="${PROJECTS_DIR:-$HOME/Projects}"
  [[ -d "$root" ]] || { print -u2 "p: $root does not exist"; return 1; }

  local -a candidates
  candidates=("$root"/*/*(N/))
  (( ${#candidates} )) || { print -u2 "p: no projects under $root"; return 1; }

  local -a matches
  if [[ -n "${1:-}" ]]; then
    matches=(${(M)candidates:#*$1*})
    (( ${#matches} )) || { print -u2 "p: no match for '$1'"; return 1; }
  else
    matches=($candidates)
  fi

  if (( ${#matches} == 1 )); then
    cd "${matches[1]}" || return 1
    return 0
  fi

  if command -v fzf >/dev/null 2>&1; then
    local choice
    choice="$(print -rl -- $matches | fzf --height 40% --reverse --query "${1:-}")"
    [[ -n "$choice" ]] && cd "$choice"
    return 0
  fi

  print -rl -- $matches
  return 0
}
