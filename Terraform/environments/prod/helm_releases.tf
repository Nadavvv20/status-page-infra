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
  depends_on = [
    module.root_infrastructure
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

# Statuspage
resource "helm_release" "statuspage" {
  name             = "statuspage"
  chart            = "${path.module}/../../../helm-statuspage"
  namespace        = "statuspage"
  create_namespace = true
  cleanup_on_fail  = true

  values = [
    yamlencode({
      config = {
        useS3        = "False"
        allowedHosts = "*"
      }
      database = {
        host         = module.root_infrastructure.rds_address
        user         = "statuspage"
      }

      redis = {
        host = module.root_infrastructure.redis_address
      }

      secrets = {
        djangoSecretName      = module.root_infrastructure.django_secret_name
        dbPasswordSecretName  = module.root_infrastructure.db_password_secret_name
        djangoAdminSecretName = module.root_infrastructure.django_admin_secret_name
      }
      
      image = {
        tag = "latest"
      }
    })
  ]
  depends_on = [
    module.root_infrastructure,
    helm_release.aws_lb_controller
  ]
}

# Metrics Server
resource "helm_release" "metrics_server" {
  name       = "metrics-server"
  repository = "https://kubernetes-sigs.github.io/metrics-server/"
  chart      = "metrics-server"
  namespace  = "kube-system"

  cleanup_on_fail = true

  values = [
    yamlencode({
      args = [
        "--kubelet-insecure-tls"
      ]
    
      resources = {
        requests = {
          cpu    = "100m"
          memory = "200Mi"
        }
      }
    })
  ]

  depends_on = [
    module.root_infrastructure.eks,
    helm_release.aws_lb_controller
  ]
}

# Prometheus and Grafana
resource "helm_release" "prometheus_stack" {
  name       = "prometheus-stack"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
  namespace  = "monitoring"
  create_namespace = true

  values = [
    yamlencode({
      grafana = {
        envFromSecret = "grafana-github-secret"
        "grafana.ini" = {
          "auth.github" = {
            enabled = true
            allow_sign_up = true
            allowed_users  = "Nadavvv20"
          }
          server = {
            domain              = ""
            root_url            = "http://k8s-statuspagegroup-1e30f316ef-938082504.us-east-1.elb.amazonaws.com/grafana/"
            serve_from_sub_path = true
          }
        }
        
        ingress = {
          enabled = true
          ingressClassName = "alb"
          annotations      = {
            "alb.ingress.kubernetes.io/group.name"       = "statuspage-group"
            "alb.ingress.kubernetes.io/order"            = "10"
            "alb.ingress.kubernetes.io/scheme"           = "internet-facing"
            "alb.ingress.kubernetes.io/target-type"      = "ip"
            "alb.ingress.kubernetes.io/healthcheck-path" = "/api/health"
          }
        hosts = [""] 
        path  = "/grafana"
        pathType = "Prefix"
        }
      }
    })
  ]
}