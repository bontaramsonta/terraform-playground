#!/bin/bash
ORG=$1
REPO_NAME=$2
ENV_NAME=$3

echo "Varcheck: tag patterns from environment '$ENV_NAME' in repository '$REPO_NAME' will be removed";

# ensure environment
envs=($(gh api \
  -H "Accept: application/vnd.github+json" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  /repos/$ORG/$REPO_NAME/environments \
  --jq '.environments[] | .name')
)

is_env_available=false

for env in ${envs[@]}; do
  if [[ $env == $ENV_NAME ]]; then
    is_env_available=true
  fi
done

if [[ $is_env_available == false ]]; then
  echo "environment not available"
  exit 0
fi

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

echo "Tags removed"