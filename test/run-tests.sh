#!/usr/bin/env bash
# Tests for claude-package-kit. Scaffolds one package of each kind in a temp
# directory and checks what comes out actually works. Nothing outside the temp
# directory is touched.
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NEW="$REPO/skill/bin/new-package.sh"
NEWMONO="$REPO/skill/bin/new-monorepo.sh"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"; mkdir -p "$HOME"

REPO_SNAPSHOT=$(find "$REPO" -path "$REPO/.git" -prune -o -print | sort)
pass=0; fail=0
ok(){ printf '  ok    %s\n' "$1"; pass=$((pass+1)); }
no(){ printf '  FAIL  %s\n    %s\n' "$1" "$2"; fail=$((fail+1)); }

echo "sanity"
bash -n "$NEW" && ok "scaffolder parses" || no "scaffolder parses" "syntax error"
bash -n "$NEWMONO" && ok "monorepo scaffolder parses" || no "monorepo scaffolder parses" "syntax error"
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
grep -q -- '-- hooks lib manifest.sh' "$out/.github/workflows/release.yml" \
  && ok "the tarball payload matches the kind" || no "the tarball payload matches the kind" "$(grep 'TAG" --' "$out/.github/workflows/release.yml")"
# install.sh sources manifest.sh, so a tarball built without it cannot install
# at all — and nothing in a git checkout ever shows that up.
grep -q -- 'manifest.sh install.sh uninstall.sh update.sh VERSION README.md' "$out/.github/workflows/release.yml" \
  && ok "the tarball carries what the installer reads" || no "the tarball carries what the installer reads" "$(grep 'TAG" --' "$out/.github/workflows/release.yml")"
# The scaffolder's own release tarball once left lib/ out for skill packages,
# so a tarball install had no update check while hook and command installs did.
grep -q -- '-- skill lib manifest.sh' "$TMP/test-skill/.github/workflows/release.yml" \
  && ok "a skill's tarball carries lib/ too" || no "a skill's tarball carries lib/ too" "$(grep 'TAG" --' "$TMP/test-skill/.github/workflows/release.yml")"

echo "the release lookup"
# update.sh and lib/update-check.sh get their lookup inserted by the
# scaffolder. A standalone package gets /releases/latest and nothing else.
for f in update.sh lib/update-check.sh; do
  bash -n "$out/$f" && ok "$f parses" || no "$f parses" "syntax error"
  grep -q '__LOOKUP__' "$out/$f" \
    && no "$f has its lookup inserted" "marker left in" || ok "$f has its lookup inserted"
  grep -q 'releases/latest' "$out/$f" && ! grep -q 'versions.txt' "$out/$f" \
    && ok "$f asks /releases/latest only" || no "$f asks /releases/latest only" "$(grep -n 'releases/latest\|versions.txt' "$out/$f")"
done
bash -n "$REPO/skill/template/lookup/versions-txt.sh" \
  && ok "the monorepo lookup parses" || no "the monorepo lookup parses" "syntax error"
# A stub curl stands in for the GitHub API, so this runs without network.
mkdir -p "$TMP/stub"
printf '#!/bin/sh\nprintf %s\n' "'{\"tag_name\":\"v9.9.9\",\"html_url\":\"https://example.invalid/r\"}\n200'" > "$TMP/stub/curl"
chmod +x "$TMP/stub/curl"
PATH="$TMP/stub:$PATH" "$out/update.sh" --check >"$TMP/o" 2>&1
grep -q "v9.9.9 is available" "$TMP/o" \
  && ok "update.sh reports a newer release" || no "update.sh reports a newer release" "$(tail -3 "$TMP/o")"
export XDG_STATE_HOME="$TMP/state"
"$out/lib/update-check.sh" record-install 0.1.0 "$out"
PATH="$TMP/stub:$PATH" "$out/lib/update-check.sh" check --force
"$out/lib/update-check.sh" status >"$TMP/o"
grep -q 'available: *9.9.9' "$TMP/o" \
  && ok "update-check.sh records it" || no "update-check.sh records it" "$(cat "$TMP/o")"
printf '#!/bin/sh\nprintf %s\n' "'{}\n404'" > "$TMP/stub/curl"
PATH="$TMP/stub:$PATH" "$out/update.sh" --check >"$TMP/o" 2>&1 \
  && no "update.sh stops when there is no release" "exited 0" \
  || { grep -q "no releases yet" "$TMP/o" && ok "update.sh stops when there is no release" \
       || no "update.sh stops when there is no release" "$(tail -2 "$TMP/o")"; }
unset XDG_STATE_HOME

"$NEW" --name test-bare --kind hook --dir "$TMP" --no-release >/dev/null 2>&1
[ ! -e "$TMP/test-bare/update.sh" ] && ok "--no-release leaves the release machinery out" || no "--no-release leaves the release machinery out" "update.sh present"

echo "monorepo root"
"$NEWMONO" --dir "$TMP" >/dev/null 2>&1 \
  && no "--name is required" "accepted it" || ok "--name is required"
"$NEWMONO" --name Bad_Name --dir "$TMP" >/dev/null 2>&1 \
  && no "rejects non-kebab-case names" "accepted it" || ok "rejects non-kebab-case names"
"$NEWMONO" --name test-mono --dir "$TMP" >"$TMP/o" 2>&1 \
  && ok "scaffolds a monorepo root" || no "scaffolds a monorepo root" "$(tail -3 "$TMP/o")"
M="$TMP/test-mono"
for f in README.md test/run-tests.sh .gitignore .github/workflows/release.yml .claude/skills/release/SKILL.md; do
  [ -f "$M/$f" ] && ok "carries $f" || no "carries $f" "missing"
done
[ -d "$M/packages" ] && [ -z "$(ls -A "$M/packages")" ] \
  && ok "packages/ exists and is empty" || no "packages/ exists and is empty" "$(ls -A "$M/packages" 2>&1)"
[ ! -e "$M/install.sh" ] && ok "has no root installer" || no "has no root installer" "install.sh present"
grep -rq '__[A-Z]*__' "$M" \
  && no "no placeholder left unfilled" "$(grep -rn '__[A-Z]*__' "$M" | head -3)" || ok "no placeholder left unfilled"
grep -q 'raw.githubusercontent.com/lenny1882/test-mono/versions/versions.txt' "$M/README.md" \
  && ok "the README installs through versions.txt" || no "the README installs through versions.txt" "$(grep -n versions.txt "$M/README.md")"
grep -q -- '--monorepo' "$TMP/o" \
  && ok "says how to add a package" || no "says how to add a package" "$(tail -4 "$TMP/o")"
"$M/test/run-tests.sh" >"$TMP/o" 2>&1 \
  && ok "its test runner passes with no packages" || no "its test runner passes with no packages" "$(tail -2 "$TMP/o")"
"$NEWMONO" --name test-mono --dir "$TMP" >/dev/null 2>&1 \
  && no "refuses an existing directory" "overwrote it" || ok "refuses an existing directory"
"$NEWMONO" --name test-mono-bare --dir "$TMP" --no-release >/dev/null 2>&1
[ ! -e "$TMP/test-mono-bare/.github" ] && [ ! -e "$TMP/test-mono-bare/.claude" ] \
  && ok "--no-release leaves the release machinery out" || no "--no-release leaves the release machinery out" "present"
"$NEWMONO" --name test-mono-slug --dir "$TMP" --slug someone/elsewhere >/dev/null 2>&1
grep -q 'someone/elsewhere' "$TMP/test-mono-slug/README.md" \
  && ok "--slug reaches the README" || no "--slug reaches the README" "not there"

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

echo "a package bundling several hooks"
# The second script's name does not contain the package name, so OWNS alone
# never finds its entry: a reinstall would add a duplicate beside the stale one,
# and uninstall would leave it behind.
"$NEW" --name test-bundle --kind hook --dir "$TMP" >/dev/null 2>&1
B="$TMP/test-bundle"
cp "$B/hooks/test-bundle.sh" "$B/hooks/second-check.sh"
cat >>"$B/manifest.sh" <<'EOF'
FILES+=("hooks/second-check.sh:$CLAUDE_DIR/hooks/second-check.sh")
settings_merge() {
  jq '
    .hooks //= {}
    | .hooks.PreToolUse = ((.hooks.PreToolUse // []) + [
        { matcher: "Bash", hooks: [{ type: "command", command: "~/.claude/hooks/test-bundle.sh" }] },
        { matcher: "Bash", hooks: [{ type: "command", command: "~/.claude/hooks/second-check.sh" }] }
      ])
  '
}
EOF
printf '{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"someone-elses-thing"}]}]}}\n' > "$CLAUDE_DIR/settings.json"
"$B/install.sh" --link --yes >"$TMP/o" 2>&1 \
  && ok "installs" || no "installs" "$(tail -4 "$TMP/o")"
grep -q "someone-elses-thing" "$CLAUDE_DIR/settings.json" \
  && ok "and leaves other packages alone" || no "and leaves other packages alone" "wiped them"
"$B/install.sh" --link --yes >/dev/null 2>&1
n=$(grep -c "second-check.sh" "$CLAUDE_DIR/settings.json")
[ "$n" -eq 1 ] && ok "reinstalling replaces the second script's entry" \
  || no "reinstalling replaces the second script's entry" "$n entries"
"$B/uninstall.sh" --yes >/dev/null 2>&1
grep -q "second-check.sh" "$CLAUDE_DIR/settings.json" \
  && no "uninstall removes the second script's entry" "still there" || ok "uninstall removes the second script's entry"
grep -q "someone-elses-thing" "$CLAUDE_DIR/settings.json" \
  && ok "and spares other packages" || no "and spares other packages" "removed them"

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
grep -q -- '-- skill lib manifest.sh' "$REPO/.github/workflows/release.yml" \
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


echo "the release tarball is enough to install from"
# The question a git checkout can never answer: is the payload list complete?
# CI builds the tarball with git archive at the tag; this builds the same file
# list out of the checkout and installs it, which is the part that matters.
payload=$(sed -n 's/^ *"\$TAG" -- //p' "$REPO/.github/workflows/release.yml")
[ -n "$payload" ] && ok "found the payload list in the workflow" || no "found the payload list in the workflow" "no git archive line"
mkdir -p "$TMP/tarball/claude-package-kit"
( cd "$REPO" && tar -cf - $payload ) | ( cd "$TMP/tarball/claude-package-kit" && tar -xf - )
export CLAUDE_DIR="$TMP/tarball-claude"; mkdir -p "$CLAUDE_DIR"
"$TMP/tarball/claude-package-kit/install.sh" --yes >"$TMP/o" 2>&1 \
  && ok "a tarball install works" || no "a tarball install works" "$(tail -4 "$TMP/o")"
grep -q "it does what it is supposed to" "$TMP/o" \
  && ok "and the probe passes from a copy install" || no "and the probe passes from a copy install" "$(tail -4 "$TMP/o")"
[ -f "$CLAUDE_DIR/skills/claude-package-kit/bin/new-package.sh" ] \
  && ok "the scaffolder survives the round trip" || no "the scaffolder survives the round trip" "missing"

echo "the suite itself"
# A test run must leave the checkout exactly as it found it. This is here
# because one of these suites did not: python's py_compile wrote a __pycache__
# directory into the source tree, which shows up as an untracked file long
# after anyone remembers running the tests.
after=$(find "$REPO" -path "$REPO/.git" -prune -o -print | sort)
[ "$REPO_SNAPSHOT" = "$after" ] \
  && ok "leaves nothing behind in the checkout" || no "leaves nothing behind in the checkout" "$(diff <(printf '%s\n' "$REPO_SNAPSHOT") <(printf '%s\n' "$after") | head -4)"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" = 0 ]
