#!/bin/sh

set -eu

script_dir=$(CDPATH= cd -P "$(dirname "$0")/.." && pwd)
installer=$script_dir/scripts/install-skill.sh
test_root=$(mktemp -d "${TMPDIR:-/tmp}/rde-install-test.XXXXXX")
trap 'rm -rf "$test_root"' EXIT HUP INT TERM

home=$test_root/home
source_repo=$test_root/source
mkdir -p "$home" "$source_repo"

git -C "$source_repo" init -q
git -C "$source_repo" config user.email test.invalid
git -C "$source_repo" config user.name 'Install Test'
git -C "$source_repo" checkout -q -b main
cat > "$source_repo/SKILL.md" <<'EOF'
---
name: remote-dev-execution
description: Test skill
---
# Test skill
EOF
git -C "$source_repo" add SKILL.md
git -C "$source_repo" commit -q -m initial
initial_commit=$(git -C "$source_repo" rev-parse HEAD)

if env HOME="$home" "$installer" --repo "$source_repo" --ref main --client claude >/dev/null 2>&1; then
  printf '%s\n' 'installer unexpectedly accepted a moving branch ref' >&2
  exit 1
fi
if env HOME="$home" "$installer" --repo "$source_repo" --client claude >/dev/null 2>&1; then
  printf '%s\n' 'installer unexpectedly accepted a missing commit ref' >&2
  exit 1
fi

env HOME="$home" "$installer" \
  --repo "$source_repo" \
  --ref "$initial_commit" \
  --client claude

canonical=$home/code/remote-dev-execution
claude_link=$home/.claude/skills/remote-dev-execution
[ -d "$canonical" ]
[ -L "$claude_link" ]
[ "$(CDPATH= cd -P "$claude_link" && pwd -P)" = "$(CDPATH= cd -P "$canonical" && pwd -P)" ]

printf '%s\n' '# updated' >> "$source_repo/SKILL.md"
git -C "$source_repo" add SKILL.md
git -C "$source_repo" commit -q -m update
updated_commit=$(git -C "$source_repo" rev-parse HEAD)
env HOME="$home" "$installer" --repo "$source_repo" --ref "$updated_commit" --client both
[ -L "$home/.agents/skills/remote-dev-execution" ]
grep -Fqx '# updated' "$canonical/SKILL.md"
[ ! -e "$canonical/remote-dev-execution" ]
[ -z "$(git -C "$canonical" status --porcelain)" ]

tag_home=$test_root/tag-home
mkdir -p "$tag_home"
env HOME="$tag_home" "$installer" \
  --repo "$source_repo" \
  --ref "$updated_commit" \
  --client claude
tag_canonical=$tag_home/code/remote-dev-execution
git -C "$tag_canonical" symbolic-ref --quiet --short HEAD >/dev/null 2>&1 && {
  printf '%s\n' 'installer unexpectedly left a pinned commit on a branch' >&2
  exit 1
}
grep -Fqx '# updated' "$tag_canonical/SKILL.md"

printf '%s\n' 'local change' > "$canonical/local-change"
if env HOME="$home" "$installer" --repo "$source_repo" --ref "$updated_commit" --client claude >/dev/null 2>&1; then
  printf '%s\n' 'installer unexpectedly updated a dirty checkout' >&2
  exit 1
fi
[ -f "$canonical/local-change" ]
rm -f "$canonical/local-change"

rm "$claude_link"
mkdir -p "$claude_link"
printf '%s\n' 'keep me' > "$claude_link/sentinel"
if env HOME="$home" "$installer" --repo "$source_repo" --ref "$updated_commit" --no-update --client claude >/dev/null 2>&1; then
  printf '%s\n' 'installer unexpectedly replaced an existing target' >&2
  exit 1
fi
[ -f "$claude_link/sentinel" ]

printf '%s\n' 'test-install-skill: all checks passed'
