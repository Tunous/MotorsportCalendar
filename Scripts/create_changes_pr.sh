#!/bin/bash

printf "# Changes\n\n" > /tmp/changes.md
for file in $(git --no-pager diff HEAD~1 HEAD --name-only); do
  printf "<details><summary>%s</summary>\n\n\`\`\`diff\n" "$file" >> /tmp/changes.md
  diff -u <(git --no-pager show HEAD~1:$file | jq) <(git --no-pager show HEAD:$file | jq) >> /tmp/changes.md
  printf "\n\`\`\`\n</details>\n\n" >> /tmp/changes.md
done

gh pr create --title "Update schedule" --body-file /tmp/changes.md
