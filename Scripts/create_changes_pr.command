changes="# Changes\n\n"
for file in $(git --no-pager diff HEAD~1 HEAD --name-only); do
  changes+="<details><summary>$file</summary>\n\n\`\`\`diff\n"
  changes+=$(diff -u <(git --no-pager show HEAD~1:$file | jq) <(git --no-pager show HEAD:$file | jq))
  changes+="\n\`\`\`\n</details>\n\n"
done

echo "$changes" > /tmp/changes.md
gh pr create --title "Update schedule" --body-file /tmp/changes.md
