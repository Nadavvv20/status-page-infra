# dev/helm_releases.tf

# AWS LB Controller
resource "helm_release" "aws_lb_controller" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  namespace  = "kube-system"

  values = [
    yamlencode({
      clusterName = module.root_infrastructure.cluster_name
      serviceAccount = {
        create = true
        name   = "aws-load-balancer-controller"
        annotations = {
          "eks.amazonaws.com/role-arn" = module.root_infrastructure.load_balancer_controller_role_arn
        }
      }
    })
  ]
}

# External Secrets Operator
resource "helm_release" "external_secrets" {
  name             = "external-secrets"
  repository       = "https://charts.external-secrets.io"
  chart            = "external-secrets"
  namespace        = "external-secrets"
  create_namespace = true
  

  force_update     = true
  cleanup_on_fail  = true
  wait             = true 

  values = [
    yamlencode({
      installCRDs = true 
      
      serviceAccount = {
        create = true
        name   = "external-secrets"
        annotations = {
          "eks.amazonaws.com/role-arn" = module.root_infrastructure.external_secrets_irsa_role_arn
        }
      }
    })
  ]
}

# Cluster Autoscaler
resource "helm_release" "cluster_autoscaler" {
  name       = "cluster-autoscaler"
  repository = "https://kubernetes.github.io/autoscaler"
  chart      = "cluster-autoscaler"
  namespace  = "kube-system"

  values = [
    yamlencode({
      autoDiscovery = {
        clusterName = module.root_infrastructure.cluster_name
      }
      awsRegion = var.region
      rbac = {
        serviceAccount = {
          name = "cluster-autoscaler"
          annotations = {
            "eks.amazonaws.com/role-arn" = module.root_infrastructure.cluster_autoscaler_irsa_role_arn
          }
        }
      }
      extraArgs = {
        "balance-similar-node-groups" = "true"
        "skip-nodes-with-system-pods" = "false"
      }
    })
  ]
}