#!/usr/bin/env bash
# Tests for claude-package-kit. Scaffolds one package of each kind in a temp
# directory and checks what comes out actually works. Nothing outside the temp
# directory is touched.
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NEW="$REPO/skill/bin/new-package.sh"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"; mkdir -p "$HOME"

pass=0; fail=0
ok(){ printf '  ok    %s\n' "$1"; pass=$((pass+1)); }
no(){ printf '  FAIL  %s\n    %s\n' "$1" "$2"; fail=$((fail+1)); }

echo "sanity"
bash -n "$NEW" && ok "scaffolder parses" || no "scaffolder parses" "syntax error"
for f in "$REPO"/*.sh; do
  bash -n "$f" && ok "$(basename "$f") parses" || no "$(basename "$f") parses" "syntax error"
done
grep -q '^name: claude-package-kit' "$REPO/skill/SKILL.md" \
  && ok "SKILL.md has frontmatter" || no "SKILL.md has frontmatter" "missing name:"

echo "bad input is refused"
"$NEW" --kind hook --dir "$TMP" >/dev/null 2>&1 \
  && no "--name is required" "accepted it" || ok "--name is required"
"$NEW" --name Bad_Name --kind hook --dir "$TMP" >/dev/null 2>&1 \
  && no "rejects non-kebab-case names" "accepted it" || ok "rejects non-kebab-case names"
"$NEW" --name gsd-thing --kind hook --dir "$TMP" >"$TMP/o" 2>&1 \
  && no "rejects names containing gsd-" "accepted it" || ok "rejects names containing gsd-"
grep -q "session-start migration" "$TMP/o" \
  && ok "and says why" || no "and says why" "no explanation given"
"$NEW" --name thing --kind widget --dir "$TMP" >/dev/null 2>&1 \
  && no "rejects an unknown kind" "accepted it" || ok "rejects an unknown kind"

echo "scaffolding"
for kind in hook skill command; do
  out="$TMP/test-$kind"
  "$NEW" --name "test-$kind" --kind "$kind" --dir "$TMP" >/dev/null 2>&1
  [ -d "$out" ] && ok "$kind: created" || { no "$kind: created" "nothing there"; continue; }

  # Nothing may survive with a placeholder still in it.
  if grep -rl '__PKG__\|__SLUG__\|__PAYLOAD__' "$out" >/dev/null 2>&1; then
    no "$kind: all placeholders substituted" "$(grep -rl '__PKG__\|__SLUG__\|__PAYLOAD__' "$out" | head -3 | tr '\n' ' ')"
  else ok "$kind: all placeholders substituted"; fi

  bad=0
  for f in "$out"/*.sh "$out"/test/*.sh "$out"/lib/*.sh "$out"/hooks/*.sh; do
    [ -f "$f" ] || continue; bash -n "$f" 2>/dev/null || bad=1
  done
  [ "$bad" = 0 ] && ok "$kind: everything generated parses" || no "$kind: everything generated parses" "syntax error"

  for f in install.sh uninstall.sh README.md VERSION manifest.sh test/run-tests.sh .gitignore; do
    [ -e "$out/$f" ] || { no "$kind: has $f" "missing"; bad=1; }
  done
  [ "$bad" = 0 ] && ok "$kind: has the standard files" || true
  [ -x "$out/install.sh" ] && ok "$kind: install.sh is executable" || no "$kind: install.sh is executable" "not +x"
  # The sandbox drops bookkeeping into .claude/, so .gitignore excludes it —
  # but .claude/skills/ is where the release skill lives and must survive that.
  grep -q '^\.claude/\*$' "$out/.gitignore" && grep -q '^!\.claude/skills/$' "$out/.gitignore" \
    && ok "$kind: ignores sandbox noise but keeps .claude/skills" \
    || no "$kind: ignores sandbox noise but keeps .claude/skills" "$(cat "$out/.gitignore")"
done

echo "release machinery"
out="$TMP/test-hook"
for f in update.sh lib/update-check.sh .github/workflows/release.yml .claude/skills/release/SKILL.md; do
  [ -f "$out/$f" ] && ok "carries $f" || no "carries $f" "missing"
done
grep -q 'GITHUB_SLUG="lenny1882/test-hook"' "$out/update.sh" \
  && ok "update.sh points at the right repo" || no "update.sh points at the right repo" "$(grep GITHUB_SLUG "$out/update.sh")"
grep -q -- '-- hooks lib install.sh' "$out/.github/workflows/release.yml" \
  && ok "the tarball payload matches the kind" || no "the tarball payload matches the kind" "$(grep 'TAG" --' "$out/.github/workflows/release.yml")"
# The scaffolder's own release tarball once left lib/ out for skill packages,
# so a tarball install had no update check while hook and command installs did.
grep -q -- '-- skill lib install.sh' "$TMP/test-skill/.github/workflows/release.yml" \
  && ok "a skill's tarball carries lib/ too" || no "a skill's tarball carries lib/ too" "$(grep 'TAG" --' "$TMP/test-skill/.github/workflows/release.yml")"

"$NEW" --name test-bare --kind hook --dir "$TMP" --no-release >/dev/null 2>&1
[ ! -e "$TMP/test-bare/update.sh" ] && ok "--no-release leaves the release machinery out" || no "--no-release leaves the release machinery out" "update.sh present"

echo "the generated package installs and works"
export CLAUDE_DIR="$TMP/claude"; mkdir -p "$CLAUDE_DIR"
printf '{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"someone-elses-thing"}]}]}}\n' > "$CLAUDE_DIR/settings.json"
"$TMP/test-hook/install.sh" --link --yes >"$TMP/o" 2>&1 \
  && ok "generated hook package installs" || no "generated hook package installs" "$(tail -4 "$TMP/o")"
grep -q "someone-elses-thing" "$CLAUDE_DIR/settings.json" \
  && ok "and leaves other packages alone" || no "and leaves other packages alone" "wiped them"
before=$(jq -S . "$CLAUDE_DIR/settings.json")
"$TMP/test-hook/install.sh" --link --yes >/dev/null 2>&1
[ "$before" = "$(jq -S . "$CLAUDE_DIR/settings.json")" ] \
  && ok "installing twice changes nothing" || no "installing twice changes nothing" "settings drifted"
"$TMP/test-hook/install.sh" --dry-run >"$TMP/o" 2>&1
grep -q "dry run" "$TMP/o" && ok "--dry-run stops before writing" || no "--dry-run stops before writing" "$(tail -2 "$TMP/o")"
"$TMP/test-hook/uninstall.sh" --yes >/dev/null 2>&1
grep -q "someone-elses-thing" "$CLAUDE_DIR/settings.json" \
  && ok "uninstall spares other packages" || no "uninstall spares other packages" "removed them"
grep -q "test-hook" "$CLAUDE_DIR/settings.json" \
  && no "uninstall removes its own entries" "still there" || ok "uninstall removes its own entries"

echo "the generated tests fail until behaviour is tested"
"$TMP/test-hook/test/run-tests.sh" >"$TMP/o" 2>&1
grep -q "no behaviour tests written yet" "$TMP/o" \
  && ok "the TODO is a failing test, not a comment" || no "the TODO is a failing test, not a comment" "$(tail -3 "$TMP/o")"
grep -qE '^[1-9][0-9]* passed' "$TMP/o" \
  && ok "the installer tests pass in a fresh package" || no "the installer tests pass in a fresh package" "$(tail -3 "$TMP/o")"
echo "the kit is packaged the way it packages other things"
for f in manifest.sh install.sh uninstall.sh update.sh lib/update-check.sh \
         .github/workflows/release.yml .claude/skills/release/SKILL.md; do
  [ -e "$REPO/$f" ] && ok "carries $f" || no "carries $f" "missing"
done
grep -q 'GITHUB_SLUG="lenny1882/package-kit"' "$REPO/update.sh" \
  && ok "update.sh points at the repo" || no "update.sh points at the repo" "$(grep GITHUB_SLUG "$REPO/update.sh")"
# The repo name and the package name differ, so the tarball is not named after
# the repo. update.sh and the README one-liner both have to agree on which.
grep -q 'TARBALL_NAME="claude-package-kit.tar.gz"' "$REPO/update.sh" \
  && ok "update.sh looks for the right tarball" || no "update.sh looks for the right tarball" "$(grep TARBALL_NAME "$REPO/update.sh")"
grep -q -- '-- skill lib install.sh' "$REPO/.github/workflows/release.yml" \
  && ok "its own tarball payload matches its kind" || no "its own tarball payload matches its kind" "$(grep 'TAG" --' "$REPO/.github/workflows/release.yml")"

echo "the kit installs itself"
export CLAUDE_DIR="$TMP/self"; mkdir -p "$CLAUDE_DIR"
printf '{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"someone-elses-thing"}]}]}}\n' \
  > "$CLAUDE_DIR/settings.json"
"$REPO/install.sh" --link --yes >"$TMP/o" 2>&1 \
  && ok "installs" || no "installs" "$(tail -5 "$TMP/o")"
grep -q "it does what it is supposed to" "$TMP/o" \
  && ok "the probe scaffolds a package for real" || no "the probe scaffolds a package for real" "$(tail -5 "$TMP/o")"
[ -f "$CLAUDE_DIR/skills/claude-package-kit/SKILL.md" ] \
  && ok "the skill lands where Claude Code looks" || no "the skill lands where Claude Code looks" "not in $CLAUDE_DIR/skills"
[ -x "$CLAUDE_DIR/skills/claude-package-kit/bin/new-package.sh" ] \
  && ok "the scaffolder is executable once installed" || no "the scaffolder is executable once installed" "not +x"
[ -x "$HOME/.local/share/claude-package-kit/update-check.sh" ] \
  && ok "the update check is installed" || no "the update check is installed" "missing"
before=$(jq -S . "$CLAUDE_DIR/settings.json")
"$REPO/install.sh" --link --yes >/dev/null 2>&1 \
  && ok "installing twice is safe" || no "installing twice is safe" "second run failed"
[ "$before" = "$(jq -S . "$CLAUDE_DIR/settings.json")" ] \
  && ok "a skill package never touches settings.json" || no "a skill package never touches settings.json" "settings changed"
"$REPO/install.sh" --dry-run >"$TMP/o" 2>&1
grep -q "dry run" "$TMP/o" && ok "--dry-run writes nothing" || no "--dry-run writes nothing" "$(tail -3 "$TMP/o")"
"$REPO/uninstall.sh" --yes >"$TMP/o" 2>&1 \
  && ok "uninstalls" || no "uninstalls" "$(tail -3 "$TMP/o")"
[ -e "$CLAUDE_DIR/skills/claude-package-kit" ] \
  && no "uninstall removes the skill" "still there" || ok "uninstall removes the skill"
grep -q "someone-elses-thing" "$CLAUDE_DIR/settings.json" \
  && ok "and leaves other packages alone" || no "and leaves other packages alone" "removed them"


printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" = 0 ]
