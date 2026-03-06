# modules/helm_releases/main.tf

# AWS LB Controller
resource "helm_release" "aws_lb_controller" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  namespace  = "kube-system"

  values = [
    yamlencode({
      clusterName = var.cluster_name
      serviceAccount = {
        create = true
        name   = "aws-load-balancer-controller"
        annotations = {
          "eks.amazonaws.com/role-arn" = var.load_balancer_controller_role_arn
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
          "eks.amazonaws.com/role-arn" = var.external_secrets_irsa_role_arn
        }
      }
    })
  ]
  depends_on = [
    helm_release.aws_lb_controller
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
      image = {
        tag = "v1.31.0"
      }
      autoDiscovery = {
        clusterName = var.cluster_name
      }
      awsRegion = var.region
      rbac = {
        serviceAccount = {
          name = "cluster-autoscaler"
          annotations = {
            "eks.amazonaws.com/role-arn" = var.cluster_autoscaler_irsa_role_arn
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

        deploymentStrategy = {
          type = "Recreate"
        }

        image = {
        tag = "11.5.0"
        }
        # Add Loki as a data source
        additionalDataSources = [
          {
            name      = "Loki"
            type      = "loki"
            url       = "http://loki:3100"
            access    = "proxy"
            isDefault = false
          }
        ]


        persistence = {
          enabled          = true
          accessModes = ["ReadWriteOnce"]
          volumeName       = "pvc-161a160d-863b-46d4-a57f-2d7699181914"
          storageClassName = "gp3"
          size             = "5Gi"
          
        }
        envFromSecret = "grafana-github-secret" 
        "grafana.ini" = {
          "auth.github" = {
            enabled = true
            allow_sign_up = true
            allowed_users  = "Nadavvv20"
          }
          server = {
            domain              = ""
            root_url            = "http://k8s-statuspagegroup-1e30f316ef-1437681547.us-east-1.elb.amazonaws.com/grafana/"
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
      prometheus = {
        prometheusSpec = {
          storageSpec = {
            volumeClaimTemplate = {
              spec = {
                storageClassName = "gp3"
                accessModes      = ["ReadWriteOnce"]
                resources = {
                  requests = {
                    storage = "10Gi"
                  }
                }
              }
            }
          }
        }
      }
    })
  ]
}

# Logs Monitoring
resource "helm_release" "loki" {
  name       = "loki"
  repository = "https://grafana.github.io/helm-charts"
  chart      = "loki-stack"
  namespace  = "monitoring"
  create_namespace = true

  values = [
    yamlencode({
      loki = {
        image = {
          tag = "2.9.10" 
        }
        persistence = {
          enabled = true
          size    = "10Gi"
          storageClassName = "gp3"
        }
      }
      promtail = {
        enabled = true
      }
      grafana = {
        enabled = false
        sidecar = {
          datasources = {
            enabled = false
          }
        }
      }
    })
  ]
}
