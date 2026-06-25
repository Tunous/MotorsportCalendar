#!/bin/bash

set -euo pipefail

printf "# Changes\n\n" > /tmp/changes.md
for file in $(git --no-pager diff HEAD~1 HEAD --name-only); do
  printf "<details><summary>%s</summary>\n\n\`\`\`diff\n" "$file" >> /tmp/changes.md
  diff -u <(git --no-pager show HEAD~1:$file | jq) <(git --no-pager show HEAD:$file | jq) >> /tmp/changes.md
  printf "\n\`\`\`\n</details>\n\n" >> /tmp/changes.md
done

printf "@Tunous\n" >> /tmp/changes.md

if pr_number="$(gh pr view --json number --jq .number 2>/dev/null)"; then
  gh pr edit "$pr_number" --title "Update schedule" --body-file /tmp/changes.md
else
  gh pr create --title "Update schedule" --body-file /tmp/changes.md
fi
