#!/usr/bin/env bash
# Waits until GitHub Pages has published the current head of gh-pages.
# Needs GH_TOKEN and GITHUB_REPOSITORY.
set -euo pipefail
sha=$(git ls-remote "https://github.com/${GITHUB_REPOSITORY}.git" refs/heads/gh-pages | cut -f1)
for _ in $(seq 1 60); do
  read -r commit status < <(gh api "repos/${GITHUB_REPOSITORY}/pages/builds/latest" --jq '"\(.commit) \(.status)"')
  echo "Pages build for ${commit:0:7} (want ${sha:0:7}): $status"
  if [ "$commit" = "$sha" ] && [ "$status" = "built" ]; then exit 0; fi
  if [ "$commit" = "$sha" ] && [ "$status" = "errored" ]; then exit 1; fi
  sleep 10
done
echo "Timed out waiting for Pages"
exit 1
