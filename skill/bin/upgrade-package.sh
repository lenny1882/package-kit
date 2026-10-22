#!/usr/bin/env bash
# Bring a package's kit-owned files up to date with this kit.
#
#   upgrade-package.sh <package-dir>          dry run: each file's status, and diffs
#   upgrade-package.sh <package-dir> --apply  write what is safe to write
#   upgrade-package.sh --root <monorepo>      the same for a monorepo root's own files
#
#   --force <file>     replace this file with the new render, discarding hand
#                      edits; repeatable
#   --adopt <file>     keep this hand-edited file as it is, and record the new
#                      render as what it came from, so later upgrades merge
#                      into it; for a package with no .kit/ yet; repeatable
#   --kind <kind>      override what .kit/settings says, or what was inferred
#   --slug <slug>      likewise, for the GitHub owner/repo
#   --monorepo <root>  likewise: the package lives in this monorepo
#   --allow-downgrade  run although the package was made by a newer kit
#
# Renders the package again from the current template, in a temp directory,
# and compares each kit-owned file with what is on disk and with the copy in
# .kit/files/ of what was generated last time. Never commits, installs, or runs
# the package's tests. reference/upgrade.md has the design.
set -euo pipefail

KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=kit-lib.sh
. "$KIT/bin/kit-lib.sh"

DIR=""; ROOT_MODE=0; APPLY=0; FORCE=(); ADOPT=(); O_KIND=""; O_SLUG=""; O_MONO=""; DOWNGRADE=0
while [ $# -gt 0 ]; do
  case "$1" in
    --root)     DIR="${2:-}"; ROOT_MODE=1; shift 2 ;;
    --apply)    APPLY=1; shift ;;
    --force)    FORCE+=("${2:-}"); shift 2 ;;
    --adopt)    ADOPT+=("${2:-}"); shift 2 ;;
    --kind)     O_KIND="${2:-}"; shift 2 ;;
    --slug)     O_SLUG="${2:-}"; shift 2 ;;
    --monorepo) O_MONO="${2:-}"; shift 2 ;;
    --allow-downgrade) DOWNGRADE=1; shift ;;
    -h|--help)  sed -n '2,21p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*) echo "unknown option: $1" >&2; exit 2 ;;
    *)  [ -z "$DIR" ] || { echo "one package at a time" >&2; exit 2; }; DIR="$1"; shift ;;
  esac
done

die(){ printf '%s\n' "$*" >&2; exit 1; }
say(){ printf '%s\n' "$*"; }

[ -n "$DIR" ] || die "name the package directory, or --root <monorepo>"
[ -d "$DIR" ] || die "$DIR is not a directory"
DIR="$(cd "$DIR" && pwd)"
command -v git >/dev/null 2>&1 || die "git is needed: hand edits are merged with git merge-file"

# --- settings: from .kit/settings, or read out of the package itself --------

TAIL=" manifest.sh install.sh uninstall.sh update.sh VERSION README.md"
slug_from_readme(){
  grep -o 'raw\.githubusercontent\.com/[^/]*/[^/]*/versions/' "$1" 2>/dev/null | head -1 \
    | sed -e 's|^raw\.githubusercontent\.com/||' -e 's|/versions/$||'
}

MONO_ROOT=""
if [ -f "$DIR/.kit/settings" ]; then
  LEGACY=0
  NAME=$(kit_get "$DIR" name); KIND=$(kit_get "$DIR" kind); SLUG=$(kit_get "$DIR" slug)
  MONOREPO=$(kit_get "$DIR" monorepo); RELEASE=$(kit_get "$DIR" release)
  PAYLOAD=$(kit_get "$DIR" payload); MADE_BY=$(kit_get "$DIR" kit)
  : "${MONOREPO:=0}"
elif [ "$ROOT_MODE" -eq 1 ]; then
  LEGACY=1; MADE_BY=""
  NAME=$(basename "$DIR"); KIND=monorepo; MONOREPO=0; PAYLOAD=""
  SLUG=$(slug_from_readme "$DIR/README.md")
  [ -f "$DIR/.github/workflows/release.yml" ] && RELEASE=1 || RELEASE=0
else
  LEGACY=1; MADE_BY=""
  [ -f "$DIR/manifest.sh" ] || die "$DIR has no manifest.sh and no .kit/ — not a package made by this kit"
  NAME=$(sed -n 's/^PKG="\(.*\)"$/\1/p' "$DIR/manifest.sh" | head -1)
  [ -n "$NAME" ] || die "no PKG=\"...\" line in $DIR/manifest.sh"
  code=$(grep -v '^[[:space:]]*#' "$DIR/manifest.sh")
  if   printf '%s\n' "$code" | grep -q '\$CLAUDE_DIR/skills/'; then KIND=skill
  elif printf '%s\n' "$code" | grep -q '\.local/bin/';          then KIND=command
  else KIND=hook; fi
  [ -f "$DIR/PAYLOAD" ] && MONOREPO=1 || MONOREPO=0
  [ -f "$DIR/update.sh" ] && RELEASE=1 || RELEASE=0
  SLUG=$(sed -n 's/^GITHUB_SLUG="\(.*\)"$/\1/p' "$DIR/update.sh" 2>/dev/null | head -1)
  if [ -f "$DIR/PAYLOAD" ]; then
    PAYLOAD=$(head -1 "$DIR/PAYLOAD")
  else
    PAYLOAD=$(sed -n 's/^ *"\$TAG" -- //p' "$DIR/.github/workflows/release.yml" 2>/dev/null | head -1)
  fi
  PAYLOAD="${PAYLOAD%"$TAIL"}"
fi

[ -n "$O_KIND" ] && KIND="$O_KIND"
[ -n "$O_SLUG" ] && SLUG="$O_SLUG"
if [ -n "$O_MONO" ]; then MONOREPO=1; MONO_ROOT="$(cd "$O_MONO" && pwd)"; fi
if [ "$MONOREPO" = 1 ] && [ -z "$MONO_ROOT" ]; then MONO_ROOT="$(cd "$DIR/../.." && pwd)"; fi
if [ -z "$SLUG" ] && [ "$MONOREPO" = 1 ]; then SLUG=$(slug_from_readme "$MONO_ROOT/README.md"); fi
: "${SLUG:=lenny1882/$NAME}"

if [ "$ROOT_MODE" -eq 1 ]; then
  [ "$KIND" = monorepo ] || die "$DIR is a $KIND package, not a monorepo root; drop --root"
else
  [ "$KIND" != monorepo ] || die "$DIR is a monorepo root; use --root $DIR"
fi

THIS=$(kit_version)
if [ "$LEGACY" -eq 0 ] && kit_newer_than "$THIS" "$MADE_BY" && [ "$DOWNGRADE" -eq 0 ]; then
  die "$NAME was made by kit v$MADE_BY, newer than this kit (v$THIS). Upgrading would write
older files over newer ones. Update the kit first, or pass --allow-downgrade."
fi

say "== $NAME ($KIND) at $DIR"
if [ "$LEGACY" -eq 0 ]; then
  say "   settings from .kit/settings, made by kit v$MADE_BY; this kit is v$THIS"
else
  say "   no .kit/ — settings read from the package; check them, and override with"
  say "   --kind, --slug or --monorepo if any is wrong. This kit is v$THIS."
fi
say "   slug=$SLUG monorepo=$MONOREPO release=$RELEASE${PAYLOAD:+ payload=$PAYLOAD}"

# --- render it again, the way the scaffolder would --------------------------

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
if [ "$ROOT_MODE" -eq 1 ]; then
  args=(--name "$NAME" --dir "$TMP" --slug "$SLUG")
  [ "$RELEASE" = 1 ] || args+=(--no-release)
  "$KIT/bin/new-monorepo.sh" "${args[@]}" >"$TMP/render.log" 2>&1 \
    || die "rendering failed: $(tail -3 "$TMP/render.log")"
  R="$TMP/$NAME"
else
  args=(--name "$NAME" --kind "$KIND" --slug "$SLUG" --payload "$PAYLOAD")
  [ "$RELEASE" = 1 ] || args+=(--no-release)
  if [ "$MONOREPO" = 1 ]; then
    # A bare stand-in for the root: new-package.sh only needs packages/ to
    # exist, and with no README it adds no row anywhere.
    mkdir -p "$TMP/root/packages"
    args+=(--monorepo "$TMP/root"); R="$TMP/root/packages/$NAME"
  else
    args+=(--dir "$TMP/out"); mkdir -p "$TMP/out"; R="$TMP/out/$NAME"
  fi
  "$KIT/bin/new-package.sh" "${args[@]}" >"$TMP/render.log" 2>&1 \
    || die "rendering failed: $(tail -3 "$TMP/render.log")"
fi

KEYS=$(cd "$R/.kit/files" && find . -type f | sed 's|^\./||' | sort)

forced(){ local f; for f in ${FORCE[@]+"${FORCE[@]}"}; do [ "$f" = "$1" ] && return 0; done; return 1; }
adopted(){ local f; for f in ${ADOPT[@]+"${ADOPT[@]}"}; do [ "$f" = "$1" ] && return 0; done; return 1; }
for f in ${FORCE[@]+"${FORCE[@]}"} ${ADOPT[@]+"${ADOPT[@]}"}; do
  printf '%s\n' "$KEYS" | grep -qxF "$(kit_key "$f")" || die "$f: not a file this kit owns"
done

# --- compare each kit-owned file --------------------------------------------

declare -A WRITE=() RECORD=()
mkdir -p "$TMP/work"
n_ok=0; n_write=0; n_left=0
report=(); diffs=()

note(){ report+=("$(printf '  %-12s %s' "$1" "$2")"); }
show(){ diffs+=("$(diff -u --label "$1 (on disk)" --label "$1 ($2)" "$3" "$4" || true)"); }

for k in $KEYS; do
  p=$(kit_path "$k"); cur="$DIR/$p"; new="$R/.kit/files/$k"; base="$DIR/.kit/files/$k"
  if [ ! -e "$cur" ]; then
    note new "$p"; WRITE[$p]="$R/$p"; RECORD[$k]="$new"; n_write=$((n_write+1))
  elif cmp -s "$cur" "$new"; then
    note "up to date" "$p"; RECORD[$k]="$new"; n_ok=$((n_ok+1))
  elif forced "$p"; then
    note forced "$p"; show "$p" "new kit" "$cur" "$new"
    WRITE[$p]="$new"; RECORD[$k]="$new"; n_write=$((n_write+1))
  elif [ -f "$base" ] && cmp -s "$cur" "$base"; then
    note stale "$p"; show "$p" "new kit" "$cur" "$new"
    WRITE[$p]="$new"; RECORD[$k]="$new"; n_write=$((n_write+1))
  elif [ -f "$base" ]; then
    m="$TMP/work/$k"; mkdir -p "$(dirname "$m")"; cp "$cur" "$m"
    rc=0; git merge-file -L "on disk" -L "as generated" -L "new kit" "$m" "$base" "$new" || rc=$?
    [ "$rc" -ge 0 ] && [ "$rc" -lt 128 ] || die "git merge-file failed on $p"
    if [ "$rc" -eq 0 ] && cmp -s "$m" "$cur"; then
      # The kit has not changed this file since it was generated; the hand
      # edits stand as they are.
      note "up to date" "$p  (hand edits kept)"; RECORD[$k]="$base"; n_ok=$((n_ok+1))
    elif [ "$rc" -eq 0 ]; then
      note merged "$p"; show "$p" "merged" "$cur" "$m"
      WRITE[$p]="$m"; RECORD[$k]="$new"; n_write=$((n_write+1))
    else
      note conflict "$p  — $rc conflicting hunk(s); --force $p takes the new kit's version"
      show "$p" "merged, with conflicts" "$cur" "$m"
      RECORD[$k]="$base"; n_left=$((n_left+1))
    fi
  elif [ "$p" = .gitignore ]; then
    # No record of what was generated, but a .gitignore is a set of lines more
    # than a sequence: appending the kit's missing ones cannot undo a hand edit.
    m="$TMP/work/gitignore"; cp "$cur" "$m"; added=0
    while IFS= read -r line; do
      case "$line" in ''|'#'*) continue ;; esac
      grep -qxF -- "$line" "$cur" && continue
      [ "$added" -eq 1 ] || { [ -z "$(tail -c1 "$m")" ] || echo >> "$m"; printf '\n# Added by claude-package-kit upgrade-package.sh\n' >> "$m"; }
      printf '%s\n' "$line" >> "$m"; added=1
    done < "$new"
    RECORD[$k]="$new"
    if [ "$added" -eq 1 ]; then
      note "lines added" "$p"; show "$p" "kit lines added" "$cur" "$m"
      WRITE[$p]="$m"; n_write=$((n_write+1))
    else
      note "up to date" "$p  (has every kit line)"; n_ok=$((n_ok+1))
    fi
  elif adopted "$p"; then
    note adopted "$p  — kept as it is; the new render is recorded as its origin"
    RECORD[$k]="$new"; n_ok=$((n_ok+1))
  else
    note hand-edited "$p  — no record of what was generated; --force $p takes the new kit's version, --adopt $p keeps yours"
    show "$p" "new kit" "$cur" "$new"
    n_left=$((n_left+1))
  fi
done

if [ -d "$DIR/.kit/files" ]; then
  while IFS= read -r k; do
    printf '%s\n' "$KEYS" | grep -qxF "$k" || note "not kit's" "$(kit_path "$k")  — this kit no longer owns it; left alone"
  done < <(cd "$DIR/.kit/files" && find . -type f | sed 's|^\./||' | sort)
fi

say; say "Files"
printf '%s\n' "${report[@]}"

if [ "$APPLY" -eq 0 ] && [ "${#diffs[@]}" -gt 0 ]; then
  say; say "Diffs"
  printf '%s\n\n' "${diffs[@]}"
fi

# --- what a person has to carry over ----------------------------------------

if [ "$ROOT_MODE" -eq 0 ]; then
  if [ -f "$DIR/.kit/template/manifest.sh" ]; then
    if ! cmp -s "$DIR/.kit/template/manifest.sh" "$R/.kit/template/manifest.sh"; then
      say; say "manifest.sh — the template for a $KIND package has changed since this one was"
      say "made. manifest.sh is filled in by hand, so carry over what applies yourself:"
      diff -u --label "template (then)" --label "template (now)" \
        "$DIR/.kit/template/manifest.sh" "$R/.kit/template/manifest.sh" || true
    fi
  else
    say; say "manifest.sh — no record of the template it came from. Compare it by hand with"
    say "  $KIT/template/manifest.$KIND.sh"
  fi
  if [ -f "$DIR/test/run-tests.sh" ] && ! grep -Eq '^[[:space:]]*(\.|source)[[:space:]].*installer-tests\.sh' "$DIR/test/run-tests.sh"; then
    say; say "test/run-tests.sh does not source test/installer-tests.sh. Its installer tests"
    say "are the old inline copy; replacing them with"
    say "  . \"\$REPO/test/installer-tests.sh\""
    say "is an edit to a file the package owns, so it is left to you."
  fi
fi

say
say "$n_ok up to date, $n_write to write, $n_left left for you"

if [ "$APPLY" -eq 0 ]; then
  [ "$n_write" -gt 0 ] && say "Dry run — nothing written. Run again with --apply to write them."
  exit 0
fi

# --- write ------------------------------------------------------------------

for p in "${!WRITE[@]}"; do
  src="${WRITE[$p]}"; dst="$DIR/$p"
  if [ -e "$dst" ]; then cat "$src" > "$dst"      # keeps the file's mode
  else mkdir -p "$(dirname "$dst")"; cp -p "$src" "$dst"; fi
done

# .kit/ afterwards: the new settings, the new render of every file written or
# already current, and the old copy of every file left alone, so a later
# upgrade can still merge it.
NK="$TMP/newkit"; mkdir -p "$NK/files"
cp "$R/.kit/settings" "$NK/settings"
for k in "${!RECORD[@]}"; do
  mkdir -p "$(dirname "$NK/files/$k")"; cp "${RECORD[$k]}" "$NK/files/$k"
done
[ -d "$R/.kit/template" ] && cp -r "$R/.kit/template" "$NK/template"
rm -rf "$DIR/.kit"; cp -r "$NK" "$DIR/.kit"

say "Written, and .kit/ updated. Next: ./test/run-tests.sh, then review with git diff."
[ "$n_left" -eq 0 ]
