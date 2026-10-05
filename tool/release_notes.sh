#!/usr/bin/env bash
# Print the CHANGELOG.md section belonging to a released version.
#
#   tool/release_notes.sh v0.1.6-beta
#
# The release workflow feeds this to `gh release create --notes-file`, so the
# GitHub release body is the CHANGELOG entry rather than a second, hand-kept
# copy of it. Exits 1 when the version has no section, which lets the caller
# fall back to generated notes instead of publishing an empty body.
#
# Unreleased is deliberately rejected: tagging a release means that work is
# being cut into a version, and "Unreleased" would publish every pending
# entry under this tag.
set -euo pipefail

CHANGELOG="${CHANGELOG:-CHANGELOG.md}"
version="${1:-}"
version="${version#v}"

if [[ -z "$version" || "$version" == "Unreleased" ]]; then
  echo "usage: $(basename "$0") <version>" >&2
  exit 2
fi

if [[ ! -f "$CHANGELOG" ]]; then
  echo "no changelog at $CHANGELOG" >&2
  exit 1
fi

# Accepts both "## 1.2.3 - date" and the bracketed "## [1.2.3] - date" form.
# The header is matched by comparing the token before the first space, so a
# request for 1.2.3 cannot match a 1.2.3.4 section, and a version containing
# dashes (0.1.4-beta) is not split.
notes="$(awk -v want="$version" '
  /^## / {
    if (inside) exit
    head = substr($0, 4)          # drop the "## " prefix
    sub(/^[[:space:]]+/, "", head)
    sub(/^\[/, "", head)          # bracketed form
    sub(/\][[:space:]]*$/, "", head)
    gap = index(head, " ")
    if (gap > 0) head = substr(head, 1, gap - 1)
    tab = index(head, "\t")
    if (tab > 0) head = substr(head, 1, tab - 1)
    # Only a version heading counts: a version always starts with a digit.
    # Without this, prose sections ("## Developer note") are parsable as a
    # version and could be published as release notes.
    if (head ~ /^[0-9]/ && head == want) inside = 1
    next
  }
  inside { print }
' "$CHANGELOG")"

# A header with nothing under it is as useless as no header at all.
if [[ -z "${notes//[[:space:]]/}" ]]; then
  exit 1
fi

printf '%s\n' "$notes"
