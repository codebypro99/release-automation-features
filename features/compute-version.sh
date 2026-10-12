#!/bin/sh
# Computes the next application version from git tags and writes the files
# consumed by the release pipeline:
#   .version                  semantic version (no v prefix)
#   .tag                      docker image tag (== .version)
#   backend/.build-version    copy inside the backend docker build context
#   frontend/.build-version   copy inside the frontend docker build context
#
# Versioning scheme (bump size is auto-detected from the conventional-commit
# messages since the last release — see the classifier below):
#   main  -> major bump (v1.3.2 -> 2.0.0) on a breaking change; minor bump, zero
#            patch (v1.3.2 -> 1.4.0) on a feat; otherwise a patch bump
#            (v1.3.2 -> 1.3.3). No tags yet -> 1.0.0. The tag itself is pushed by
#            finalize-release only after a successful prod deploy.
#   stage -> same next version with a prerelease suffix: 1.4.0-stage.<sha8>.
#
# Signal a major bump from a commit with the conventional-commits breaking
# marker: a `!` after the type (feat!: ..., refactor!: ...) or a `BREAKING
# CHANGE:` footer in the body.
#
# Override: set RELEASE_TYPE=major|minor|patch on a manual pipeline run to force
# the bump regardless of the commit messages.
set -eu

BRANCH="${CI_COMMIT_BRANCH:-$(git rev-parse --abbrev-ref HEAD)}"
SHA8="$(echo "${CI_COMMIT_SHA:-$(git rev-parse HEAD)}" | cut -c1-8)"

# Woodpecker clones can be shallow/tagless; make sure prod tags are present.
git fetch --tags --force origin >/dev/null 2>&1 || true

# Latest final release tag. `git tag -l` is reachability-independent, so
# stage-branch resets never affect the result (unlike `git describe`).
LATEST="$(git tag -l 'v*' --sort=-v:refname | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | head -1 || true)"

# Decide the bump size from the commits added since $LATEST. A breaking change
# (type! or a BREAKING CHANGE footer) is a major; a feat: is a minor; everything
# else (fix/chore/docs/...) is a patch. A manual RELEASE_TYPE wins outright.
classify_bump() {
  case "${RELEASE_TYPE:-}" in
    major | minor | patch) echo "$RELEASE_TYPE"; return ;;
  esac

  # Raw messages (subject + body) of the commits since the last release. If the
  # range is empty or the tag is unreachable (e.g. a diverged stage branch or a
  # manual re-run), fall back to just HEAD so we still classify something.
  LOG="$(git log --format='%B' "${LATEST}..HEAD" 2>/dev/null || true)"
  [ -n "$LOG" ] || LOG="$(git log -1 --format='%B' HEAD 2>/dev/null || true)"

  # Breaking change -> major: `type!:` / `type(scope)!:` subject, or a
  # BREAKING CHANGE footer.
  # A squash-merged PR carries its commits as "* feat: ..." bullet lines in the
  # body (this is how "Release 1.10" classified as a patch and shipped as
  # v1.9.1), so accept an optional "* " / "- " bullet prefix everywhere.
  if printf '%s\n' "$LOG" | grep -qE '^([*-] )?[a-z]+(\([^)]*\))?!:' \
     || printf '%s\n' "$LOG" | grep -qiE '^([*-] )?BREAKING[ -]CHANGE:'; then
    echo major; return
  fi
  # New feature -> minor.
  if printf '%s\n' "$LOG" | grep -qE '^([*-] )?feat(\([^)]*\))?:'; then
    echo minor; return
  fi
  echo patch
}

if [ -z "$LATEST" ]; then
  NEXT="1.0.0"
  BUMP="initial"
else
  MAJOR="$(echo "$LATEST" | sed -E 's/^v([0-9]+)\..*/\1/')"
  MINOR="$(echo "$LATEST" | sed -E 's/^v[0-9]+\.([0-9]+)\..*/\1/')"
  PATCH="$(echo "$LATEST" | sed -E 's/^v[0-9]+\.[0-9]+\.([0-9]+)$/\1/')"
  BUMP="$(classify_bump)"
  case "$BUMP" in
    major) NEXT="$((MAJOR + 1)).0.0" ;;
    minor) NEXT="${MAJOR}.$((MINOR + 1)).0" ;;
    patch) NEXT="${MAJOR}.${MINOR}.$((PATCH + 1))" ;;
  esac
fi

case "$BRANCH" in
  main) VERSION="$NEXT" ;;
  *) VERSION="${NEXT}-stage.${SHA8}" ;;
esac

# Semantic version — the git tag, changelog, and the APP_VERSION shown in the UI.
printf '%s' "$VERSION" > .version

# Immutable Docker image tag. Swarm pins images by digest at deploy time; if a
# tag is ever re-pushed with new content, its old digest is orphaned and a
# not-yet-converged service's pinned digest 404s ("No such image") — the exact
# outage we hit when the same 1.x.0 tag got rebuilt across retries. Appending the
# commit sha makes every build a write-once tag, so a tag's digest never changes.
# Stage versions already embed the sha (1.4.0-stage.<sha8>), so they're immutable
# as-is; only main needs the suffix.
case "$BRANCH" in
  main) TAG="${VERSION}-${SHA8}" ;;
  *) TAG="$VERSION" ;;
esac
printf '%s' "$TAG" > .tag

printf '%s' "$VERSION" > backend/.build-version
printf '%s' "$VERSION" > frontend/.build-version

# Guard: a merge between main and stage can resurrect an unreleased.md whose
# notes were already released and renamed to <version>.md on the other branch
# (v1.9.1's notes shipped a second time as v1.10.0 this way). The frontmatter
# title is the fingerprint — refuse to build until the duplicate is resolved.
UNRELEASED="frontend/changelogs/unreleased.md"
if [ -f "$UNRELEASED" ]; then
  TITLE="$(sed -n 's/^title:[[:space:]]*//p' "$UNRELEASED" | head -1)"
  if [ -n "$TITLE" ]; then
    for f in frontend/changelogs/[0-9]*.md; do
      [ -f "$f" ] || continue
      if sed -n 's/^title:[[:space:]]*//p' "$f" | head -1 | grep -qxF "$TITLE"; then
        echo "unreleased.md has the same title as $(basename "$f") — already-released notes resurrected by a merge? Fix the changelog before releasing." >&2
        exit 1
      fi
    done
  fi
fi

echo "Branch: $BRANCH, latest tag: ${LATEST:-<none>}, bump: $BUMP, version: $VERSION, image tag: $TAG"
