repo_list = {
  "test_repo" = {
    "repo_name" = "testRepo",
    "env_details_map" = {
      TEST = {
        deployment_tags = ["develop__BAR__*", "develop__FOO__*"]
      },
      DEV = {
        deployment_tags = ["develop_OTHER__*"]
      },
    }
  }
}
