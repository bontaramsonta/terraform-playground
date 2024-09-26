#!/bin/bash

# Check if at least two arguments are passed
if [ "$#" -lt 3 ]; then
  echo "Usage: $0 <org> <repo_name> <env_name> [tags...]"
  exit 1
fi

# Assign the first two arguments
ORG=$1
REPO_NAME=$2
ENV_NAME=$3

# Shift the first two arguments so that the remaining ones are the tags
shift 3

# Remaining arguments are treated as tags
TAGS=("$@")

echo "Varcheck: Environment '$ENV_NAME' in repository '$REPO_NAME' has been configured with tag patterns.";
for TAG in ${TAGS[@]}; do
  # Create or update the environment with the tag pattern
  echo "Tag: $TAG";
  gh api \
    -X POST \
    -H "Accept: application/vnd.github.v3+json" \
    "/repos/$ORG/$REPO_NAME/environments/$ENV_NAME/deployment-branch-policies" \
    -f "name=$TAG" \
    -f "type=tag";

done