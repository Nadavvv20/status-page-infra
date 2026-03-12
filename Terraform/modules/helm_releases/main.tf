# modules/helm_releases/main.tf
#
# Architecture: 100% Stateless monitoring stack on AWS EKS.
# - All long-term data offloaded to S3 via IRSA (no AWS keys).
# - emptyDir volumes for short-term buffering.
# - Exception: Grafana uses EFS (Multi-AZ) for its SQLite database.

# ============================================================
# AWS Load Balancer Controller
# ============================================================
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

# ============================================================
# External Secrets Operator
# ============================================================
resource "helm_release" "external_secrets" {
  name             = "external-secrets"
  repository       = "https://charts.external-secrets.io"
  chart            = "external-secrets"
  namespace        = "external-secrets"
  create_namespace = true

  force_update    = true
  cleanup_on_fail = true
  wait            = true

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

  depends_on = [helm_release.aws_lb_controller]
}

# ============================================================
# Cluster Autoscaler
# ============================================================
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

# ============================================================
# Metrics Server
# ============================================================
resource "helm_release" "metrics_server" {
  name       = "metrics-server"
  repository = "https://kubernetes-sigs.github.io/metrics-server/"
  chart      = "metrics-server"
  namespace  = "kube-system"

  cleanup_on_fail = true

  values = [
    yamlencode({
      args = ["--kubelet-insecure-tls"]

      resources = {
        requests = {
          cpu    = "100m"
          memory = "200Mi"
        }
      }
    })
  ]

  depends_on = [helm_release.aws_lb_controller]
}

# ============================================================
# kube-prometheus-stack (Prometheus + Grafana + Thanos Sidecar)
# ============================================================
#
# Key architecture decisions:
# 1. Prometheus: Stateless - emptyDir for TSDB, Thanos Sidecar uploads blocks to S3
# 2. Thanos Sidecar: gRPC port (10901) explicitly exposed on the Prometheus Service
#    so Thanos Query can discover it
# 3. Grafana: EXCEPTION - uses EFS PVC for Multi-AZ HA of its SQLite database
# 4. TSDB block boundaries set to 2h for optimal Thanos compaction
resource "helm_release" "prometheus_stack" {
  name             = "prometheus-stack"
  repository       = "https://prometheus-community.github.io/helm-charts"
  chart            = "kube-prometheus-stack"
  namespace        = "monitoring"
  create_namespace = true
  timeout          = 900 # 15min - prevents "context deadline exceeded" during initial setup

  values = [
    yamlencode({

      # ----------------------------------------------------------
      # Grafana Configuration
      # ----------------------------------------------------------
      # EXCEPTION: Grafana uses EFS persistence for Multi-AZ HA.
      # EFS ensures the SQLite DB (dashboards, users, datasources)
      # survives pod rescheduling across any AZ.
      grafana = {

        # -- Sidecar: auto-discover Dashboards & DataSources from ConfigMaps/Secrets --
        sidecar = {
          dashboards = {
            enabled = true
            label   = "grafana_dashboard"
            # Search all namespaces for dashboard ConfigMaps
            searchNamespace = "ALL"
          }
          datasources = {
            enabled                  = true
            label                    = "grafana_datasource"
            defaultDatasourceEnabled = false # We define our own below
          }
        }

        # -- Disable initChownData since EFS handles permissions via fsGroup --
        initChownData = {
          enabled = false
        }

        # -- Security context: fsGroup ensures Grafana can read/write EFS --
        podSecurityContext = {
          fsGroup = 472
        }
        containerSecurityContext = {
          runAsUser  = 472
          runAsGroup = 472
        }

        # -- Recreate strategy avoids EFS mount conflicts during rollout --
        deploymentStrategy = {
          type = "Recreate"
        }

        image = {
          tag = "11.5.0"
        }

        # -- Explicit datasources for Loki and Thanos --
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

        # -- EFS Persistence: Multi-AZ HA for Grafana's SQLite DB --
        persistence = {
          enabled          = true
          type             = "pvc"
          accessModes      = ["ReadWriteMany"]
          storageClassName = "efs-sc" # Must match the EFS CSI StorageClass
          size             = "5Gi"
        }

        # -- GitHub OAuth (loaded from ExternalSecret) --
        envFromSecret = "grafana-github-secret"
        "grafana.ini" = {
          "auth.github" = {
            enabled       = true
            allow_sign_up = false
          }
          server = {
            domain              = ""
            root_url            = "http://k8s-statuspagegroup-1e30f316ef-1437681547.us-east-1.elb.amazonaws.com/grafana/"
            serve_from_sub_path = true
          }
        }

        # -- ALB Ingress for Grafana --
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
      },

      # ----------------------------------------------------------
      # Prometheus Configuration
      # ----------------------------------------------------------
      prometheus = {
        serviceAccount = {
          create = true
          name   = "prometheus-prometheus-stack-kube-prom-prometheus"
          annotations = {
            # IRSA: allows Thanos Sidecar (running alongside Prometheus)
            # to upload TSDB blocks to S3 without static credentials
            "eks.amazonaws.com/role-arn" = var.thanos_irsa_role_arn
            "rebuild-trigger"            = "1"
          }
        }

        # -- CRITICAL FIX: Expose Thanos gRPC port on Prometheus Service --
        # Without this, Thanos Query cannot reach the Sidecar for real-time data.
        # This is nested under prometheus.service (NOT at root level).
        service = {
          additionalPorts = [
            {
              name       = "grpc-thanos"
              port       = 10901
              targetPort = 10901
              protocol   = "TCP"
            }
          ]
        }

        prometheusSpec = {
          # -- Thanos Sidecar: reads blocks from TSDB and ships them to S3 --
          # CRITICAL: The image field MUST be set explicitly. Without it,
          # the Prometheus Operator will NOT inject the sidecar container.
          thanos = {
            image     = "quay.io/thanos/thanos:v0.37.2"
            blockSize = "30m" # CRITICAL: This is what actually sets --storage.tsdb.min/max-block-duration
            objectStorageConfig = {
              existingSecret = {
                name = "thanos-objstore-config"
                key  = "objstore.yml"
              }
            }
          }
          podMetadata = {
            annotations = {
              "rebuild-date" = "2026-03-11"
            }
          }

          # -- TSDB block boundaries: 30m to survive hourly node termination --
          # 30m ensures at least 1 block is cut & uploaded before the node dies.
          # Safe since Thanos Compactor is disabled in this setup.
          storageTsdbMinBlockDuration = "30m"
          storageTsdbMaxBlockDuration = "30m"

          # -- Stateless: emptyDir replaces any PVC for local TSDB --
          # Data survives within the pod lifecycle; after restart,
          # Thanos Store Gateway serves historical data from S3.
          storageSpec = {
            emptyDir = {
              sizeLimit = "5Gi"
            }
          }

          # -- Retention: only keep recent data locally --
          retention = "2h"
        }
      }

      # -- Disable default Prometheus Operator admission webhooks timeout issues --
      prometheusOperator = {
        admissionWebhooks = {
          enabled = true
          patch = {
            enabled = true
          }
        }
      },

      # -- Alertmanager: stateless with emptyDir --
      alertmanager = {
        alertmanagerSpec = {
          storage = {
            emptyDir = {
              sizeLimit = "256Mi"
            }
          }
        }
      }
    })
  ]
}

# ============================================================
# Thanos (Query + Store Gateway) - Bitnami Chart
# ============================================================
#
# Architecture:
# - Query: Fanout queries to both the Sidecar (real-time) and
#   Store Gateway (historical from S3). This gives a unified
#   long-term Prometheus view.
# - Store Gateway: Reads blocks from S3, caches index locally
#   in emptyDir. No PVCs.
# - Compactor: Disabled - can be enabled later if needed.
resource "helm_release" "thanos" {
  name             = "thanos"
  repository       = "https://charts.bitnami.com/bitnami"
  chart            = "thanos"
  namespace        = "monitoring"
  create_namespace = true

  timeout = 900 # 15min - Store Gateway needs time for initial S3 index sync
  wait    = true

  depends_on = [helm_release.prometheus_stack]

  values = [
    yamlencode({
      # -- Allow non-Bitnami images if needed --
      global = {
        security = {
          allowInsecureImages = true
        }
      }

      image = {
        registry   = "quay.io"
        repository = "thanos/thanos"
        tag        = "v0.37.2"
      }

      # -- Shared object store secret (created in cluster-addons.tf) --
      existingObjstoreSecret = var.thanos_objstore_secret_name

      # ----------------------------------------------------------
      # Query Component
      # ----------------------------------------------------------
      # Discovers data from two sources:
      # 1. Store Gateway - historical data from S3
      # 2. Prometheus Sidecar - real-time data from live TSDB
      query = {
        enabled = true
        stores = [
          # Store Gateway service (auto-created by this chart)
          "thanos-storegateway:10901",
          # CRITICAL: Prometheus sidecar exposed via the additionalPorts fix above
          "prometheus-stack-kube-prom-prometheus:10901"
        ]

        # -- Resource limits for Query --
        resources = {
          requests = {
            cpu    = "100m"
            memory = "256Mi"
          }
          limits = {
            memory = "512Mi"
          }
        }
      }

      # ----------------------------------------------------------
      # Store Gateway Component
      # ----------------------------------------------------------
      # Reads TSDB blocks from S3. Uses emptyDir for local index cache.
      storegateway = {
        enabled = true

        # -- IRSA: authenticate to S3 without static credentials --
        serviceAccount = {
          create = true
          annotations = {
            "eks.amazonaws.com/role-arn" = var.thanos_irsa_role_arn
          }
        }

        # -- Stateless: no PVCs, emptyDir for index caching --
        persistence = {
          enabled = false
        }

        # -- Probes: generous startup time for initial S3 sync --
        livenessProbe = {
          enabled             = true
          initialDelaySeconds = 120
          failureThreshold    = 10
        }
        readinessProbe = {
          enabled             = true
          initialDelaySeconds = 60
          failureThreshold    = 10
        }

        resources = {
          requests = {
            cpu    = "100m"
            memory = "256Mi"
          }
          limits = {
            memory = "512Mi"
          }
        }
      }

      # -- Compactor: disabled to keep the stack minimal --
      # Enable if you need block downsampling or compaction.
      compactor = {
        enabled = false
      }

      # -- Ruler: disabled (alerting handled by Prometheus Alertmanager) --
      ruler = {
        enabled = false
      }

      # -- Receive: disabled (we use Sidecar, not remote-write) --
      receive = {
        enabled = false
      }
    })
  ]
}

# ============================================================
# Loki Stack (Loki + Promtail)
# ============================================================
#
# Architecture:
# - Loki: Stateless - emptyDir for local BoltDB Shipper cache,
#   all chunks and indexes stored in S3.
# - s3forcepathstyle = false prevents SignatureDoesNotMatch errors
#   on AWS (virtual-hosted-style is required).
# - Probes: high initialDelaySeconds to survive initial S3 sync.
resource "helm_release" "loki" {
  name             = "loki"
  repository       = "https://grafana.github.io/helm-charts"
  chart            = "loki-stack"
  namespace        = "monitoring"
  create_namespace = true

  timeout = 900 # 15min - Loki needs time for initial BoltDB index sync from S3
  wait    = true

  depends_on = [helm_release.prometheus_stack]

  values = [
    yamlencode({
      loki = {
        image = {
          tag = "2.9.10"
        }

        # -- IRSA: authenticate to S3 without static credentials --
        serviceAccount = {
          create = true
          name   = "loki"
          annotations = {
            "eks.amazonaws.com/role-arn" = var.loki_irsa_role_arn
          }
        }

        # -- Loki config: S3 backend for chunks + BoltDB Shipper --
        config = {
          # -- Auth disabled for single-tenant mode --
          auth_enabled = false

          # -- Ingester: configure chunk lifecycle --
          ingester = {
            chunk_idle_period   = "1h"
            max_chunk_age       = "1h"
            chunk_retain_period = "30s"
            lifecycler = {
              ring = {
                replication_factor = 1
              }
            }
          }

          # -- Schema: BoltDB Shipper + S3 object store --
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

          # -- Storage: S3 for chunks, BoltDB Shipper for index --
          storage_config = {
            aws = {
              # Virtual-hosted-style URL (s3forcepathstyle = false)
              s3               = "s3://${var.region}/${var.monitoring_data_bucket_id}"
              region           = var.region
              s3forcepathstyle = false # CRITICAL: prevents SignatureDoesNotMatch errors
            }
            boltdb_shipper = {
              active_index_directory = "/data/loki/boltdb-shipper-active"
              cache_location         = "/data/loki/boltdb-shipper-cache"
              cache_ttl              = "24h"
              shared_store           = "s3"
            }
          }

          # -- Limits: prevent OOM on high-cardinality workloads --
          limits_config = {
            reject_old_samples         = true
            reject_old_samples_max_age = "168h" # 7 days
          }

          # -- Compactor: runs locally, ships compacted index to S3 --
          compactor = {
            working_directory      = "/data/loki/compactor"
            shared_store           = "s3"
            compaction_interval    = "10m"
            retention_enabled      = true
            retention_delete_delay = "2h"
          }
        }

        # -- Disable PVC persistence --
        # The loki chart natively provisions an emptyDir named `storage` on `/data`
        # when persistence.enabled is false.
        persistence = {
          enabled = false
        } # -- Probes: generous startup to survive initial index sync from S3 --
        # Without this, the pod enters CrashLoopBackOff during first boot.
        livenessProbe = {
          initialDelaySeconds = 120
          failureThreshold    = 10
          timeoutSeconds      = 5
        }
        readinessProbe = {
          initialDelaySeconds = 120
          failureThreshold    = 10
          timeoutSeconds      = 5
        }
      }

      # -- Promtail: log collector (DaemonSet on every node) --
      promtail = {
        enabled = true
      }

      # -- Grafana: disabled here (managed by kube-prometheus-stack) --
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