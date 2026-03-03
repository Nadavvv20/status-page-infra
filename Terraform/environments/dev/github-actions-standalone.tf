# Standalone GitHub Actions IAM Role
# This creates the role without depending on the main infrastructure

module "github_actions_standalone" {
  source = "../../modules/github-actions-iam"

  github_org         = "Nadavvv20"
  app_repo_name      = "status-page-app"
  infra_repo_name    = "status-page-infra"
  project_name       = "Nadav-Statuspage-Project-DEV"
  ecr_repository_arn = "arn:aws:ecr:us-east-1:992382545251:repository/nadav-statuspage"
  eks_cluster_name   = "Nadav-Statuspage-Project-DEV-cluster-dev"
}

output "github_actions_standalone_arn" {
  description = "GitHub Actions IAM Role ARN - Add this to GitHub Secrets as AWS_ROLE_ARN"
  value       = module.github_actions_standalone.github_actions_role_arn
}
