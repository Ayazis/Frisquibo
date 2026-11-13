#!/usr/bin/env bash
# Run inside a checkout of gh-pages. Removes pr/pr-<n>/ for every PR that is no longer open,
# then commits and pushes. Needs GH_TOKEN and GITHUB_REPOSITORY.
set -euo pipefail
[ -d pr ] || { echo "No previews"; exit 0; }
removed=0
for dir in pr/pr-*/; do
  [ -d "$dir" ] || continue
  n=${dir#pr/pr-}; n=${n%/}
  state=$(gh pr view "$n" --repo "$GITHUB_REPOSITORY" --json state --jq .state)
  if [ "$state" != "OPEN" ]; then
    echo "Removing preview for PR #$n ($state)"
    git rm -rq "$dir"
    removed=1
  fi
done
[ "$removed" = 1 ] || { echo "Nothing to remove"; exit 0; }
git config user.name "github-actions[bot]"
git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
git commit -qm "Remove previews of closed PRs"
git push origin gh-pages
