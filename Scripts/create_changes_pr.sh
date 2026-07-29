#!/bin/bash

printf "# Changes\n\n" > /tmp/changes.md
for file in $(git --no-pager diff HEAD~1 HEAD --name-only); do
  printf "<details><summary>%s</summary>\n\n\`\`\`diff\n" "$file" >> /tmp/changes.md
  diff -u <(git --no-pager show HEAD~1:$file | jq) <(git --no-pager show HEAD:$file | jq) >> /tmp/changes.md
  printf "\n\`\`\`\n</details>\n\n" >> /tmp/changes.md
done

printf "@Tunous\n" >> /tmp/changes.md

# Try to find an existing PR for the current branch. If one exists and is still open, edit it.
# Otherwise create a new PR.
pr_info="$(gh pr view --json number,state 2>/dev/null || true)"
if [[ -n "$pr_info" ]]; then
  pr_number=$(jq -r '.number // empty' <<<"$pr_info")
  pr_state=$(jq -r '.state // empty' <<<"$pr_info")
  if [[ -n "$pr_number" && ("$pr_state" == "OPEN" || "$pr_state" == "open") ]]; then
    gh pr edit "$pr_number" --title "Update schedule" --body-file /tmp/changes.md
    exit 0
  fi
fi

# No open PR found — create a new one
gh pr create --title "Update schedule" --body-file /tmp/changes.md
