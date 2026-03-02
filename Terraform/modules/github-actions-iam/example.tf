# Example usage of GitHub Actions IAM module

module "github_actions_iam" {
  source = "../../modules/github-actions-iam"

  # GitHub Configuration
  github_org       = "YOUR_GITHUB_USERNAME"  # 🔴 שנה את זה!
  app_repo_name    = "status-page-app"
  infra_repo_name  = "status-page-infra"

  # Project Configuration
  project_name = "statuspage"

  # AWS Resources (from other modules)
  ecr_repository_arn = module.ecr.repository_arn
  eks_cluster_name   = module.eks.cluster_name

  # Or hardcode if not using modules:
  # ecr_repository_arn = "arn:aws:ecr:us-east-1:992382545251:repository/nadav-statuspage"
  # eks_cluster_name   = "Nadav-Statuspage-Project-DEV-cluster-dev"
}

# Output the role ARN for easy copy-paste
output "copy_to_github_secrets" {
  description = "Copy this ARN to GitHub Secrets as AWS_ROLE_ARN"
  value       = module.github_actions_iam.github_actions_role_arn
}

# Show setup instructions
output "setup_instructions" {
  value = module.github_actions_iam.setup_instructions
}
