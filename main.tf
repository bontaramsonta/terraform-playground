provider "github" {
  token = var.github_token
  owner = var.github_owner
}

locals {
  # to flatten the repo_list map structure to generate repo - env
  repo_env_flatten = flatten([
    for repo_name, envs in var.repo_list : [
      for env_name, team in envs.env_details_map :
      {
        repo_name = envs.repo_name
        env_name  = env_name
      }
    ]
    ]
  )
}

resource "github_repository_environment" "repo_environment" {
  for_each = {
    for RepoEnvDetails in local.repo_env_flatten : "${RepoEnvDetails.repo_name}.${RepoEnvDetails.env_name}" => RepoEnvDetails
  }
  environment       = each.value.env_name
  repository        = each.value.repo_name
  can_admins_bypass = false
  deployment_branch_policy {
    protected_branches     = false
    custom_branch_policies = true
  }
}

locals {
  # to flatten the repo_list map structure to generate repo - env - tag mapping
  repo_env_tags_flatten = flatten([
    for repo_name, envs in var.repo_list : [
      for env_name, env_details in envs.env_details_map :
      {
        repo_name   = envs.repo_name
        env_name    = env_name
        deploy_tags = env_details.deployment_tags
      }
    ]
    ]
  )
}

resource "terraform_data" "repo_deployment_tags_updater" {
  for_each = {
    for RepoEnvTagsDetails in local.repo_env_tags_flatten : "${RepoEnvTagsDetails.repo_name}.${RepoEnvTagsDetails.env_name}" => RepoEnvTagsDetails
  }
  input = each.value.deploy_tags
}

resource "null_resource" "repo_deployment_tags_policy" {
  for_each = {
    for RepoEnvTagsDetails in local.repo_env_tags_flatten : "${RepoEnvTagsDetails.repo_name}.${RepoEnvTagsDetails.env_name}" => RepoEnvTagsDetails
  }

  triggers = {
    repo_name = each.value.repo_name
    env_name  = each.value.env_name
    org       = "amalgam-rx"
    tags      = join(" ", each.value.deploy_tags)
  }

  provisioner "local-exec" {
    command = "./bin/create_tag_policy.sh ${self.triggers.org} ${self.triggers.repo_name} ${self.triggers.env_name} ${self.triggers.tags}"
  }
  provisioner "local-exec" {
    when    = destroy
    command = "./bin/delete_tag_policy.sh ${self.triggers.org} ${self.triggers.repo_name} ${self.triggers.env_name}"
  }

  depends_on = [github_repository_environment.repo_environment]
  lifecycle {
    replace_triggered_by = [terraform_data.repo_deployment_tags_updater]
  }
}
