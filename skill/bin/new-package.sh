#!/usr/bin/env bash
# Scaffold a new Claude Code package following the house layout.
#
#   new-package.sh --name my-thing --kind hook [options]
#
#   --name <name>     package name, kebab-case; becomes the directory, the
#                     script name, and the substring the installer uses to find
#                     its own settings entries
#   --kind <kind>     hook | skill | command
#   --dir <dir>       where to create it (default: the current directory)
#   --slug <slug>     GitHub owner/repo for update.sh and the README
#                     (default: lenny1882/<name>)
#   --payload "<...>" paths included in the release tarball
#                     (default: by kind — hook "hooks lib", skill "skill",
#                     command "bin lib")
#   --no-release      leave out update.sh, lib/update-check.sh, the release
#                     workflow and the release skill — for something that will
#                     never be published
#   --monorepo <root> create it as <root>/packages/<name>, inside a repo made
#                     by new-monorepo.sh. The slug comes from the root's README
#                     unless --slug is given; releases are found through the
#                     root's versions.txt; the root keeps the release workflow
#                     and skill, and the package gets a PAYLOAD file listing
#                     what its tarball carries. --dir does not apply.
#
# Creates the directory, fills in the machinery, and leaves the parts that need
# thought marked EDIT or TODO. It deliberately does not run git init: publishing
# is a separate, deliberate step.
set -euo pipefail

KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMPLATE="$KIT/template"

NAME=""; KIND=""; DIR=""; SLUG=""; PAYLOAD=""; RELEASE=1; MONO=""
while [ $# -gt 0 ]; do
  case "$1" in
    --name)    NAME="${2:-}"; shift 2 ;;
    --kind)    KIND="${2:-}"; shift 2 ;;
    --dir)     DIR="${2:-}"; shift 2 ;;
    --slug)    SLUG="${2:-}"; shift 2 ;;
    --payload) PAYLOAD="${2:-}"; shift 2 ;;
    --no-release) RELEASE=0; shift ;;
    --monorepo) MONO="${2:-}"; shift 2 ;;
    -h|--help) sed -n '2,28p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done

die(){ printf '%s\n' "$*" >&2; exit 1; }

[ -n "$NAME" ] || die "--name is required"
[ -n "$KIND" ] || die "--kind is required (hook, skill or command)"
case "$NAME" in
  *[!a-z0-9-]*|-*|*-) die "--name must be kebab-case: lower case, digits and hyphens" ;;
esac
case "$NAME" in
  *gsd-*) die "'$NAME' contains 'gsd-'. GSD's session-start migration deletes any
hook whose command contains that, and the registration vanishes between
sessions with no error. Pick another name." ;;
esac
[ -f "$TEMPLATE/manifest.$KIND.sh" ] || die "--kind must be hook, skill or command"

if [ -n "$MONO" ]; then
  [ -z "$DIR" ] || die "--dir and --monorepo cannot both be given: a monorepo package always goes in <root>/packages/"
  [ -d "$MONO/packages" ] || die "$MONO has no packages/ directory — is it a monorepo made by new-monorepo.sh?"
  if [ -z "$SLUG" ]; then
    SLUG=$(grep -o 'raw\.githubusercontent\.com/[^/]*/[^/]*/versions/' "$MONO/README.md" 2>/dev/null | head -1 \
      | sed -e 's|^raw\.githubusercontent\.com/||' -e 's|/versions/$||')
    [ -n "$SLUG" ] || die "could not read the repo slug from $MONO/README.md; pass --slug <owner/repo>"
  fi
fi
: "${SLUG:=lenny1882/$NAME}"
if [ -z "$PAYLOAD" ]; then
  case "$KIND" in
    hook)    PAYLOAD="hooks lib" ;;
    skill)   PAYLOAD="skill lib" ;;
    command) PAYLOAD="bin lib" ;;
  esac
fi
[ "$RELEASE" -eq 1 ] || PAYLOAD="${PAYLOAD/ lib/}"

if [ -n "$MONO" ]; then OUT="$MONO/packages/$NAME"; else OUT="${DIR:-.}/$NAME"; fi
[ -e "$OUT" ] && die "$OUT already exists"

REPO_NAME="${SLUG#*/}"
sub(){ sed -e "s|__SLUG__|$SLUG|g" -e "s|__PAYLOAD__|$PAYLOAD|g" -e "s|__PKG__|$NAME|g" -e "s|__REPO__|$REPO_NAME|g"; }

# update.sh and lib/update-check.sh share one way of finding the newest
# release, kept in template/lookup/ and inserted at their __LOOKUP__ line. A
# standalone package asks /releases/latest; a monorepo package reads its line
# in the root's versions.txt, because /releases/latest there returns whichever
# package released last. Only the one lookup is written, so the generated
# scripts carry no code for the other case.
if [ -n "$MONO" ]; then
  LOOKUP="$TEMPLATE/lookup/versions-txt.sh"
else
  LOOKUP="$TEMPLATE/lookup/releases-latest.sh"
fi
with_lookup(){ sed -e '/^__LOOKUP__$/{' -e "r $LOOKUP" -e 'd' -e '}' "$1" | sub; }

mkdir -p "$OUT/test"
sub < "$TEMPLATE/install.sh"        > "$OUT/install.sh"
sub < "$TEMPLATE/uninstall.sh"      > "$OUT/uninstall.sh"
sub < "$TEMPLATE/test/run-tests.sh" > "$OUT/test/run-tests.sh"
sub < "$TEMPLATE/manifest.$KIND.sh" > "$OUT/manifest.sh"
if [ -n "$MONO" ]; then
  # The root owns .gitignore, and the README's install and release sections
  # go through versions.txt and the root's /release.
  sub < "$TEMPLATE/monorepo/package-README.md" > "$OUT/README.md"
else
  sub < "$TEMPLATE/README.md"       > "$OUT/README.md"
  sub < "$TEMPLATE/gitignore"       > "$OUT/.gitignore"
fi
cp     "$TEMPLATE/VERSION"            "$OUT/VERSION"

case "$KIND" in
  hook)
    mkdir -p "$OUT/hooks"
    sub < "$TEMPLATE/starters/hooks/__PKG__.sh" > "$OUT/hooks/$NAME.sh" ;;
  skill)
    mkdir -p "$OUT/skill/bin"
    sub < "$TEMPLATE/starters/skill/SKILL.md" > "$OUT/skill/SKILL.md" ;;
  command)
    mkdir -p "$OUT/bin"
    sub < "$TEMPLATE/starters/bin/__PKG__" > "$OUT/bin/$NAME" ;;
esac

if [ "$RELEASE" -eq 1 ]; then
  mkdir -p "$OUT/lib"
  with_lookup "$TEMPLATE/update.sh"                      > "$OUT/update.sh"
  with_lookup "$TEMPLATE/lib/update-check.sh"            > "$OUT/lib/update-check.sh"
  if [ -n "$MONO" ]; then
    # One workflow at the root serves every package, so each package says what
    # its own tarball carries — the same list a standalone workflow spells out.
    printf '%s manifest.sh install.sh uninstall.sh update.sh VERSION README.md\n' "$PAYLOAD" > "$OUT/PAYLOAD"
  else
    mkdir -p "$OUT/.github/workflows" "$OUT/.claude/skills/release"
    sub < "$TEMPLATE/dot-github/workflows/release.yml"   > "$OUT/.github/workflows/release.yml"
    sub < "$TEMPLATE/dot-claude/skills/release/SKILL.md" > "$OUT/.claude/skills/release/SKILL.md"
  fi
fi

# The root README's package table gets a row, above the marker line.
if [ -n "$MONO" ] && grep -q '^<!-- new-package.sh --monorepo adds a row' "$MONO/README.md"; then
  tmp=$(mktemp)
  awk -v row="| [\`$NAME\`](packages/$NAME/) | TODO: one line on what it does |" \
    '/^<!-- new-package.sh --monorepo adds a row/ { print row } { print }' "$MONO/README.md" > "$tmp"
  cat "$tmp" > "$MONO/README.md"; rm -f "$tmp"
fi

chmod +x "$OUT"/*.sh "$OUT/test/run-tests.sh"
[ -d "$OUT/lib" ]   && chmod +x "$OUT/lib/"*.sh
[ -d "$OUT/hooks" ] && chmod +x "$OUT/hooks/"*.sh
[ -f "$OUT/bin/$NAME" ] && chmod +x "$OUT/bin/$NAME"

printf '\n== %s (%s) created at %s\n\n' "$NAME" "$KIND" "$OUT"
printf 'Next, in order:\n'
printf '  1. Write the thing itself, and the comment saying why it exists.\n'
printf '  2. Fill in manifest.sh — the parts marked EDIT decide what gets\n'
printf '     registered and how the installer proves it works.\n'
printf '  3. Replace the TODO in test/run-tests.sh with tests of the behaviour.\n'
printf '     It fails until you do, deliberately.\n'
printf '  4. ./test/run-tests.sh, then ./install.sh --link\n'
printf '  5. Add a row to INVENTORY.md naming the installed file exactly.\n'
if [ -n "$MONO" ]; then
  printf '  6. Fill in its row in %s/README.md.\n' "$MONO"
  [ "$RELEASE" -eq 1 ] && printf '  7. Publishing (/release %s at the repo root) needs asking first.\n' "$NAME"
else
  [ "$RELEASE" -eq 1 ] && printf '  6. Publishing (git init, a GitHub repo, /release) needs asking first.\n'
fi
printf '\n'
