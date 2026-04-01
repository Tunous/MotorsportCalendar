#!/bin/bash

set -euo pipefail

printf "# Changes\n\n" > /tmp/changes.md
for file in $(git --no-pager diff HEAD~1 HEAD --name-only); do
  printf "<details><summary>%s</summary>\n\n\`\`\`diff\n" "$file" >> /tmp/changes.md
  diff -u <(git --no-pager show HEAD~1:$file | jq) <(git --no-pager show HEAD:$file | jq) >> /tmp/changes.md
  printf "\n\`\`\`\n</details>\n\n" >> /tmp/changes.md
done

branch_name="$(git rev-parse --abbrev-ref HEAD)"
existing_pr_number="$(
  gh pr list \
    --state open \
    --head "$branch_name" \
    --json number \
    --jq '.[0].number // empty'
)"

if [[ -n "$existing_pr_number" ]]; then
  gh pr edit "$existing_pr_number" --title "Update schedule" --body-file /tmp/changes.md
else
  gh pr create --title "Update schedule" --body-file /tmp/changes.md
fi
