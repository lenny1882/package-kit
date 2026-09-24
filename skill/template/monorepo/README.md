# __REPO__

<One sentence: what this collection is for, and why these packages share a
repo rather than having one each.>

Every package under `packages/` is versioned, released and installed on its
own. A fault in one says nothing about another, so each can be fixed and
shipped without touching the rest.

## Packages

| Package | What it does |
| --- | --- |
<!-- new-package.sh --monorepo adds a row above this line -->

## Install a package

Needs `curl`, `tar` and `jq`. Set `pkg` to a name from the table:

    pkg=<package>
    v=$(curl -fsSL https://raw.githubusercontent.com/__SLUG__/versions/versions.txt | awk -v p="$pkg" '$1 == p {print $2}')
    curl -fsSL "https://github.com/__SLUG__/releases/download/$pkg-v$v/$pkg.tar.gz" | tar -xz
    cd "$pkg" && ./install.sh

`versions.txt` lists each package's newest stable version. The release workflow
writes a package's line only after that release's tarball is uploaded, so the
lines above never change between versions and always fetch something that
exists. To pin a version instead:

    https://github.com/__SLUG__/releases/download/<package>-vX.Y.Z/<package>.tar.gz

Each package's own README has the same lines with its name filled in, and
covers updating and uninstalling.

## Tests

    ./test/run-tests.sh

Runs every package's own suite, one section each, and fails if any of them
does.

## Releasing

`/release <package>` in this repo — bump `packages/<package>/VERSION` on
`main`, move `release/<package>-vX.x` onto it, and tag `<package>-vX.Y.Z` there.
The tag is what publishes it. See `.claude/skills/release/SKILL.md`.
