#!/bin/bash
ORG=$1
REPO_NAME=$2
ENV_NAME=$3

echo "Varcheck: Remove deployment tag patterns from environment '$ENV_NAME' in repository '$REPO_NAME'";

# get list of tag patterns ids for the environment
TAGS=($(gh api \
  -H "Accept: application/vnd.github+json" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  /repos/$ORG/$REPO_NAME/environments/$ENV_NAME/deployment-branch-policies \
  --jq '.branch_policies[] | select(.type == "tag") | .id')
)

for TAG_ID in ${TAGS[@]}; do
  gh api \
    --method DELETE \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    /repos/$ORG/$REPO_NAME/environments/$ENV_NAME/deployment-branch-policies/$TAG_ID
done