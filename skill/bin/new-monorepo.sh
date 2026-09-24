#!/usr/bin/env bash
# Scaffold the root of a repo that holds several independently released
# packages, following the house layout.
#
#   new-monorepo.sh --name my-hooks [options]
#
#   --name <name>     repo name, kebab-case; becomes the directory
#   --dir <dir>       where to create it (default: the current directory)
#   --slug <slug>     GitHub owner/repo for the README's install lines and the
#                     packages added later (default: lenny1882/<name>)
#   --no-release      leave out the release workflow and the release skill —
#                     for a repo that will never be published
#
# Creates the root — README, a test runner over every package, .gitignore, an
# empty packages/ and, unless --no-release, the release workflow and skill —
# and no packages. Add each package with new-package.sh --monorepo. It
# deliberately does not run git init: publishing is a separate, deliberate
# step.
set -euo pipefail

KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMPLATE="$KIT/template"
MONO="$TEMPLATE/monorepo"

NAME=""; DIR="."; SLUG=""; RELEASE=1
while [ $# -gt 0 ]; do
  case "$1" in
    --name)    NAME="${2:-}"; shift 2 ;;
    --dir)     DIR="${2:-}"; shift 2 ;;
    --slug)    SLUG="${2:-}"; shift 2 ;;
    --no-release) RELEASE=0; shift ;;
    -h|--help) sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done

die(){ printf '%s\n' "$*" >&2; exit 1; }

[ -n "$NAME" ] || die "--name is required"
case "$NAME" in
  *[!a-z0-9-]*|-*|*-) die "--name must be kebab-case: lower case, digits and hyphens" ;;
esac

: "${SLUG:=lenny1882/$NAME}"

OUT="$DIR/$NAME"
[ -e "$OUT" ] && die "$OUT already exists"

sub(){ sed -e "s|__SLUG__|$SLUG|g" -e "s|__REPO__|$NAME|g"; }

mkdir -p "$OUT/test" "$OUT/packages"
sub < "$MONO/README.md"         > "$OUT/README.md"
sub < "$MONO/test/run-tests.sh" > "$OUT/test/run-tests.sh"
cp     "$TEMPLATE/gitignore"      "$OUT/.gitignore"
chmod +x "$OUT/test/run-tests.sh"

if [ "$RELEASE" -eq 1 ]; then
  mkdir -p "$OUT/.github/workflows" "$OUT/.claude/skills/release"
  sub < "$MONO/dot-github/workflows/release.yml"   > "$OUT/.github/workflows/release.yml"
  sub < "$MONO/dot-claude/skills/release/SKILL.md" > "$OUT/.claude/skills/release/SKILL.md"
fi

printf '\n== %s (monorepo) created at %s\n\n' "$NAME" "$OUT"
printf 'Next, in order:\n'
printf '  1. Replace the placeholder sentence at the top of README.md.\n'
printf '  2. Add each package:\n'
printf '       %s/bin/new-package.sh --name <package> --kind hook|skill|command --monorepo %s\n' "$KIT" "$OUT"
[ "$RELEASE" -eq 1 ] && printf '  3. Publishing (git init, a GitHub repo, /release) needs asking first.\n'
printf '\n'
