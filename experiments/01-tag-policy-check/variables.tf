variable "github_token" {
  description = "github token"
  type        = string
}

variable "github_owner" {
  description = "github user / org value"
  default     = "amalgam-rx"
}

variable "repo_list" {
  type = map(object({
    repo_name = string
    env_details_map = optional(map(object({
      deployment_tags = optional(list(string), []),
    })), {})
  }))
}
