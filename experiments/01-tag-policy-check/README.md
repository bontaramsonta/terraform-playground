# GitHub deployment tag policy check

Uses the GitHub provider to create a repository environment and enforce
deployment tag policies (which tags may deploy to an environment), driven by
`github_tag_list.json` and the scripts in `bin/`.

Note: this predates the repo's AWS setup — it's a GitHub-provider experiment.
