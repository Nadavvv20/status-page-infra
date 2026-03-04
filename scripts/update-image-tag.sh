#!/usr/bin/env bash
set -euo pipefail

# Usage: ./scripts/update-image-tag.sh <new-tag>
# Example: ./scripts/update-image-tag.sh 1.2.3

TAG=${1:-"ci-$(date +%s)"}
VALUES_FILE="helm-statuspage/values.yaml"
BRANCH="CI/CD"

if [ ! -f "$VALUES_FILE" ]; then
  echo "values file not found: $VALUES_FILE" >&2
  exit 1
fi

echo "Updating image.tag to '$TAG' in $VALUES_FILE"
sed -i "s/tag: \".*\"/tag: \"$TAG\"/" "$VALUES_FILE"

echo "Committing and pushing to branch $BRANCH"
git fetch origin || true
git checkout -B "$BRANCH"
git add "$VALUES_FILE"
if git commit -m "Update image tag to $TAG [ci skip]"; then
  git push --set-upstream origin "$BRANCH"
  echo "Pushed branch $BRANCH with updated tag: $TAG"
else
  echo "No changes to commit"
fi

echo "Done. Watch GitHub Actions for runs triggered by this push."
