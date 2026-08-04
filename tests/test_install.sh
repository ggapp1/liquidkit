#!/usr/bin/env bash
# Tests for install.sh. All runs are retargeted via DOTFILES_INSTALL_HOME
# so the real $HOME is never touched.
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# install.sh's non-dry-run path now also clones liquidprompt over the network
# and (when atuin is on PATH) imports shell history into it. Stub both so
# every test below stays hermetic: no network access, and no real atuin
# database is ever touched, only the throwaway $tmp created per test.
#
# The git stub fakes a successful `clone <dest>` by creating a `.git` marker
# at the destination -- the same marker install_liquidprompt() itself checks
# for "already cloned" -- and, when GIT_STUB_LOG is set, records the full
# argument list so a test can assert on the exact tag/URL used rather than
# trusting install.sh's own log line (which could drift from the real
# command without a test ever noticing).
_stub_bin() {
  local bin="$1"
  mkdir -p "$bin"
  cat > "$bin/git" <<'EOF'
#!/usr/bin/env bash
# install_liquidprompt() invokes `git -c advice.detachedHead=false clone ...`,
# so skip past leading global `-c key=value` options (mirroring real git's
# own arg parsing) before checking whether the subcommand is `clone`.
args=("$@")
while [[ "${args[0]:-}" == "-c" ]]; do
  args=("${args[@]:2}")
done
if [[ "${args[0]:-}" == "clone" ]]; then
  dest=""
  for arg in "${args[@]}"; do dest="$arg"; done
  mkdir -p "$dest/.git"
  [[ -n "${GIT_STUB_LOG:-}" ]] && printf '%s\n' "$*" >> "$GIT_STUB_LOG"
fi
exit 0
EOF
  chmod +x "$bin/git"
}

# The atuin stub records the $HOME it was invoked with (the whole point of
# the fix under test: atuin must run against $TARGET_HOME, never the real
# $HOME) plus its arguments, then drops the history.db marker
# import_atuin_history() checks on a second run.
_stub_atuin() {
  local bin="$1"
  mkdir -p "$bin"
  cat > "$bin/atuin" <<'EOF'
#!/usr/bin/env bash
mkdir -p "$HOME/.local/share/atuin"
{ printf 'HOME=%s\n' "$HOME"; printf 'ARGS=%s\n' "$*"; } >> "$HOME/.local/share/atuin/stub.log"
touch "$HOME/.local/share/atuin/history.db"
exit 0
EOF
  chmod +x "$bin/atuin"
}

test_dry_run_creates_nothing() {
  local tmp; tmp="$(mktemp -d)"
  local output; output="$(DOTFILES_INSTALL_HOME="$tmp" "$REPO/install.sh" --dry-run 2>&1)"
  echo "$output" | grep -q "would: ln -s" || {
    echo "  dry-run output did not name a planned symlink action"; return 1; }
  local count; count="$(find "$tmp" -mindepth 1 | wc -l | tr -d ' ')"
  [[ "$count" == "0" ]] || { echo "  dry-run wrote $count entries"; return 1; }
  rm -rf "$tmp"
}

test_install_creates_symlink() {
  local tmp; tmp="$(mktemp -d)"
  local stub; stub="$(mktemp -d)"; _stub_bin "$stub"
  DOTFILES_INSTALL_HOME="$tmp" PATH="$stub:$PATH" "$REPO/install.sh" >/dev/null 2>&1
  [[ -L "$tmp/.zshrc" ]] || { echo "  .zshrc is not a symlink"; return 1; }
  [[ "$(readlink "$tmp/.zshrc")" == "$REPO/zsh/zshrc" ]] || {
    echo "  .zshrc points at $(readlink "$tmp/.zshrc")"; return 1; }
  rm -rf "$tmp" "$stub"
}

test_backs_up_existing_file() {
  local tmp; tmp="$(mktemp -d)"
  local stub; stub="$(mktemp -d)"; _stub_bin "$stub"
  echo "ORIGINAL CONTENT" > "$tmp/.zshrc"
  DOTFILES_INSTALL_HOME="$tmp" PATH="$stub:$PATH" "$REPO/install.sh" >/dev/null 2>&1
  local backup; backup="$(find "$tmp" -maxdepth 1 -name '.zshrc.bak-*' | head -1)"
  [[ -n "$backup" ]] || { echo "  no backup created"; return 1; }
  grep -q "ORIGINAL CONTENT" "$backup" || {
    echo "  backup lost the original content"; return 1; }
  rm -rf "$tmp" "$stub"
}

test_is_idempotent() {
  local tmp; tmp="$(mktemp -d)"
  local stub; stub="$(mktemp -d)"; _stub_bin "$stub"
  DOTFILES_INSTALL_HOME="$tmp" PATH="$stub:$PATH" "$REPO/install.sh" >/dev/null 2>&1
  DOTFILES_INSTALL_HOME="$tmp" PATH="$stub:$PATH" "$REPO/install.sh" >/dev/null 2>&1
  [[ -L "$tmp/.zshrc" && "$(readlink "$tmp/.zshrc")" == "$REPO/zsh/zshrc" ]] || {
    echo "  .zshrc is not correctly symlinked after two installs"; return 1; }
  # Re-running over our own correct symlink must not manufacture a backup.
  local backups; backups="$(find "$tmp" -maxdepth 1 -name '.zshrc.bak-*' | wc -l | tr -d ' ')"
  [[ "$backups" == "0" ]] || {
    echo "  second run created $backups backup(s); expected 0"; return 1; }
  rm -rf "$tmp" "$stub"
}

test_uninstall_restores_backup() {
  local tmp; tmp="$(mktemp -d)"
  local stub; stub="$(mktemp -d)"; _stub_bin "$stub"
  echo "ORIGINAL CONTENT" > "$tmp/.zshrc"
  DOTFILES_INSTALL_HOME="$tmp" PATH="$stub:$PATH" "$REPO/install.sh" >/dev/null 2>&1
  [[ -L "$tmp/.zshrc" ]] || {
    echo "  .zshrc did not become a symlink after install"; return 1; }
  DOTFILES_INSTALL_HOME="$tmp" "$REPO/install.sh" --uninstall >/dev/null 2>&1
  [[ ! -L "$tmp/.zshrc" ]] || { echo "  .zshrc is still a symlink"; return 1; }
  grep -q "ORIGINAL CONTENT" "$tmp/.zshrc" || {
    echo "  original content not restored"; return 1; }
  rm -rf "$tmp" "$stub"
}

test_uninstall_removes_link_when_no_backup() {
  local tmp; tmp="$(mktemp -d)"
  local stub; stub="$(mktemp -d)"; _stub_bin "$stub"
  DOTFILES_INSTALL_HOME="$tmp" PATH="$stub:$PATH" "$REPO/install.sh" >/dev/null 2>&1
  [[ -L "$tmp/.zshrc" ]] || {
    echo "  .zshrc did not become a symlink after install"; return 1; }
  DOTFILES_INSTALL_HOME="$tmp" "$REPO/install.sh" --uninstall >/dev/null 2>&1
  [[ ! -e "$tmp/.zshrc" && ! -L "$tmp/.zshrc" ]] || {
    echo "  .zshrc should be gone entirely"; return 1; }
  rm -rf "$tmp" "$stub"
}

test_install_clones_liquidprompt_pinned_tag() {
  # install_liquidprompt() must actually invoke git with the pinned tag and
  # the upstream URL, not just log a line that claims to. Asserting on the
  # stub's captured argv (rather than install.sh's own stdout) is what makes
  # this catch a drift between the log message and the real command.
  local tmp; tmp="$(mktemp -d)"
  local stub; stub="$(mktemp -d)"; _stub_bin "$stub"
  local gitlog="$tmp/git-calls.log"
  DOTFILES_INSTALL_HOME="$tmp" PATH="$stub:$PATH" GIT_STUB_LOG="$gitlog" \
    "$REPO/install.sh" >/dev/null 2>&1
  [[ -d "$tmp/.local/share/liquidprompt/.git" ]] || {
    echo "  liquidprompt was not cloned to \$TARGET_HOME/.local/share/liquidprompt"; return 1; }
  [[ -f "$gitlog" ]] || { echo "  git was never invoked"; return 1; }
  grep -q -- "--branch v2.2.1" "$gitlog" || {
    echo "  git clone was not pinned to v2.2.1: $(cat "$gitlog")"; return 1; }
  grep -q "https://github.com/liquidprompt/liquidprompt.git" "$gitlog" || {
    echo "  git clone did not target the upstream liquidprompt repo: $(cat "$gitlog")"; return 1; }
  rm -rf "$tmp" "$stub"
}

test_install_skips_liquidprompt_clone_when_already_present() {
  local tmp; tmp="$(mktemp -d)"
  local stub; stub="$(mktemp -d)"; _stub_bin "$stub"
  mkdir -p "$tmp/.local/share/liquidprompt/.git"
  local gitlog="$tmp/git-calls.log"
  local out
  out="$(DOTFILES_INSTALL_HOME="$tmp" PATH="$stub:$PATH" GIT_STUB_LOG="$gitlog" \
    "$REPO/install.sh" 2>&1)"
  [[ "$out" == *"ok: liquidprompt already present"* ]] || {
    echo "  expected install.sh to report liquidprompt already present, got:"; echo "$out"; return 1; }
  [[ ! -f "$gitlog" ]] || { echo "  git clone ran even though liquidprompt was already present"; return 1; }
  rm -rf "$tmp" "$stub"
}

test_dry_run_does_not_clone_liquidprompt() {
  local tmp; tmp="$(mktemp -d)"
  local stub; stub="$(mktemp -d)"; _stub_bin "$stub"
  local gitlog="$tmp/git-calls.log"
  DOTFILES_INSTALL_HOME="$tmp" PATH="$stub:$PATH" GIT_STUB_LOG="$gitlog" \
    "$REPO/install.sh" --dry-run >/dev/null 2>&1
  [[ ! -e "$tmp/.local/share" ]] || { echo "  --dry-run created \$TARGET_HOME/.local/share"; return 1; }
  [[ ! -f "$gitlog" ]] || { echo "  --dry-run actually invoked git clone"; return 1; }
  rm -rf "$tmp" "$stub"
}

test_import_atuin_history_scopes_home_to_target() {
  # The whole point of the HOME override in import_atuin_history(): it must
  # run against $TARGET_HOME, never the real, ambient $HOME -- otherwise
  # every test in this file that installs for real would import into the
  # developer's actual atuin database.
  local tmp; tmp="$(mktemp -d)"
  local stub; stub="$(mktemp -d)"; _stub_bin "$stub"; _stub_atuin "$stub"
  DOTFILES_INSTALL_HOME="$tmp" PATH="$stub:$PATH" "$REPO/install.sh" >/dev/null 2>&1
  local log="$tmp/.local/share/atuin/stub.log"
  [[ -f "$log" ]] || { echo "  atuin was never invoked"; return 1; }
  grep -q "^HOME=$tmp\$" "$log" || {
    echo "  atuin ran with the wrong HOME, expected '$tmp': $(cat "$log")"; return 1; }
  grep -q "^ARGS=import auto\$" "$log" || {
    echo "  atuin was not invoked as 'import auto': $(cat "$log")"; return 1; }
  rm -rf "$tmp" "$stub"
}

test_import_atuin_history_is_idempotent() {
  local tmp; tmp="$(mktemp -d)"
  local stub; stub="$(mktemp -d)"; _stub_bin "$stub"; _stub_atuin "$stub"
  DOTFILES_INSTALL_HOME="$tmp" PATH="$stub:$PATH" "$REPO/install.sh" >/dev/null 2>&1
  local log="$tmp/.local/share/atuin/stub.log"
  [[ -f "$log" ]] || { echo "  atuin was never invoked on the first install"; return 1; }
  local first_calls; first_calls="$(wc -l < "$log" | tr -d ' ')"
  [[ "$first_calls" -gt 0 ]] || { echo "  atuin stub log is empty after the first install"; return 1; }
  local out2
  out2="$(DOTFILES_INSTALL_HOME="$tmp" PATH="$stub:$PATH" "$REPO/install.sh" 2>&1)"
  [[ "$out2" == *"ok: atuin history already imported"* ]] || {
    echo "  second install did not report the history as already imported: $out2"; return 1; }
  local second_calls; second_calls="$(wc -l < "$log" | tr -d ' ')"
  [[ "$first_calls" == "$second_calls" ]] || {
    echo "  atuin import ran again on a second install (log grew from $first_calls to $second_calls lines)"
    return 1; }
  rm -rf "$tmp" "$stub"
}

test_import_atuin_history_noop_without_atuin() {
  # Mirrors the module-level guard tests: without atuin on PATH at all, the
  # import step must be silent, not error. The git stub alone (no atuin
  # stub) means `command -v atuin` genuinely fails here.
  #
  # NOTE: doctor()'s "Optional tools" report legitimately prints "MISSING
  # atuin" regardless -- that's the OPTIONAL_TOOLS loop, a different code
  # path from import_atuin_history(). Asserting "atuin never appears in
  # output" would make this test fail against a correct implementation, so
  # it checks the two specific log lines import_atuin_history() itself can
  # emit, plus the real side effect (no data directory created).
  local tmp; tmp="$(mktemp -d)"
  local stub; stub="$(mktemp -d)"; _stub_bin "$stub"
  local out
  out="$(DOTFILES_INSTALL_HOME="$tmp" PATH="$stub:/usr/bin:/bin" "$REPO/install.sh" 2>&1)"
  echo "$out" | grep -q "import: existing shell history into atuin" && {
    echo "  import_atuin_history attempted an import without atuin on PATH: $out"; return 1; }
  echo "$out" | grep -q "ok: atuin history already imported" && {
    echo "  import_atuin_history reported success without atuin on PATH: $out"; return 1; }
  [[ ! -e "$tmp/.local/share/atuin" ]] || { echo "  atuin data directory was created without atuin installed"; return 1; }
  rm -rf "$tmp" "$stub"
}
