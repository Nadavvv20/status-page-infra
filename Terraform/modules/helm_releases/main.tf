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
  name             = "prometheus-stack"
  repository       = "https://prometheus-community.github.io/helm-charts"
  chart            = "kube-prometheus-stack"
  namespace        = "monitoring"
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
        additionalDataSources = [
          {
            name      = "Loki"
            type      = "loki"
            url       = "http://loki:3100"
            access    = "proxy"
            isDefault = false
          },
          {
            name      = "Thanos"
            type      = "prometheus"
            url       = "http://thanos-query:9090"
            access    = "proxy"
            isDefault = true
          }
        ]
        persistence = {
          enabled          = true
          accessModes      = ["ReadWriteMany"]
          storageClassName = "efs-sc"
          size             = "5Gi"
        }
        envFromSecret = "grafana-github-secret"
        "grafana.ini" = {
          "auth.github" = {
            enabled       = true
            allow_sign_up = true
            allowed_users = "Nadavvv20"
          }
          server = {
            domain              = ""
            root_url            = "http://k8s-statuspagegroup-1e30f316ef-1437681547.us-east-1.elb.amazonaws.com/grafana/"
            serve_from_sub_path = true
          }
        }
        ingress = {
          enabled          = true
          ingressClassName = "alb"
          annotations = {
            "alb.ingress.kubernetes.io/group.name"       = "statuspage-group"
            "alb.ingress.kubernetes.io/order"            = "10"
            "alb.ingress.kubernetes.io/scheme"           = "internet-facing"
            "alb.ingress.kubernetes.io/target-type"      = "ip"
            "alb.ingress.kubernetes.io/healthcheck-path" = "/api/health"
          }
          hosts    = [""]
          path     = "/grafana"
          pathType = "Prefix"
        }
      }
      prometheus = {
        serviceAccount = {
          create = true
          name   = "prometheus-prometheus-stack-kube-prom-prometheus"
          annotations = {
            "eks.amazonaws.com/role-arn" = var.thanos_irsa_role_arn
          }
        }
        prometheusSpec = {
          thanos = {
            objectStorageConfig = {
              name = var.thanos_objstore_secret_name
              key  = "thanos.yaml"
            }
          }
          storageSpec = {
            emptyDir = {
              medium = "Memory"
            }
          }
        }
      }
    })
  ]
}

resource "helm_release" "thanos" {
  name             = "thanos"
  repository       = "https://charts.bitnami.com/bitnami"
  chart            = "thanos"
  namespace        = "monitoring"
  create_namespace = true

  depends_on = [helm_release.prometheus_stack]

  values = [
    yamlencode({
      objstoreConfig = var.thanos_objstore_secret_name
      query = {
        enabled = true
        stores  = ["prometheus-stack-kube-prom-prometheus-thanos:10901"]
      }
      storegateway = {
        enabled = true
        serviceAccount = {
          create = true
          annotations = {
            "eks.amazonaws.com/role-arn" = var.thanos_irsa_role_arn
          }
        }
      }
      compactor = {
        enabled = false 
      }
    })
  ]
}

# Loki - log monitoring
resource "helm_release" "loki" {
  name             = "loki"
  repository       = "https://grafana.github.io/helm-charts"
  chart            = "loki-stack"
  namespace        = "monitoring"
  create_namespace = true

  values = [
    yamlencode({
      loki = {
        image = {
          tag = "2.9.10"
        }
        serviceAccount = {
          create = true
          name   = "loki"
          annotations = {
            "eks.amazonaws.com/role-arn" = var.loki_irsa_role_arn
          }
        }
        config = {
          schema_config = {
            configs = [
              {
                from         = "2020-10-24"
                store        = "boltdb-shipper"
                object_store = "s3"
                schema       = "v11"
                index = {
                  prefix = "index_"
                  period = "24h"
                }
              }
            ]
          }
          storage_config = {
            aws = {
              s3 = "s3://${var.region}/${var.monitoring_data_bucket_id}/loki"
            }
            boltdb_shipper = {
              active_index_directory = "/data/loki/boltdb-shipper-active"
              cache_location         = "/data/loki/boltdb-shipper-cache"
              cache_ttl              = "24h"
              shared_store           = "s3"
            }
          }
        }
        persistence = {
          enabled = false
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