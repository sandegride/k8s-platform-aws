# k8s-platform-aws

Production-style Kubernetes platform on AWS: EKS provisioned with Terraform, platform add-ons delivered with Helmfile.

## What's inside

| Layer | Components |
|---|---|
| Network | VPC across 3 AZs, private/public subnets, NAT (single for dev, per-AZ for prod) |
| Cluster | EKS 1.30, managed node groups, optional GPU node group (tainted, scales from 0), IRSA, access entries |
| Storage | EBS CSI driver, encrypted `gp3` default StorageClass |
| Ingress | ingress-nginx behind NLB, HPA, PDB, zone spread |
| TLS | cert-manager with Let's Encrypt (HTTP-01) |
| Observability | kube-prometheus-stack (HA Prometheus/Alertmanager, Grafana), Loki on S3 + Promtail, alerts to Telegram |
| Policy | Kyverno: no `:latest`, no privileged pods, required requests/limits |
| CI | `terraform fmt/validate`, tflint, Trivy config scan, `helmfile lint`, kubeconform |

## Layout

```
terraform/   VPC, EKS, IRSA roles, Loki S3 buckets
helm/        values for every add-on
k8s/         StorageClass, ClusterIssuers, Kyverno policies
helmfile.yaml.gotmpl
```

## Usage

Requirements: Terraform >= 1.6, AWS CLI, kubectl, Helm, Helmfile.

```bash
cp terraform/backend.hcl.example terraform/backend.hcl
cp terraform/terraform.tfvars.example terraform/terraform.tfvars

make init plan apply
make kubeconfig
make bootstrap
```

Before installing add-ons, set `grafanaHost`, `acmeEmail`, `telegramChatId` and `lokiRoleArn` (`terraform output loki_role_arn`) in `helmfile.yaml.gotmpl`, then create the secrets:

```bash
kubectl create ns monitoring
kubectl -n monitoring create secret generic grafana-admin \
  --from-literal=admin-user=admin --from-literal=admin-password='<password>'
kubectl -n monitoring create secret generic alertmanager-telegram \
  --from-literal=token='<bot-token>'

make addons
```

## Alerts

Besides the default kube-prometheus-stack rules:

- `PodCrashLooping` — more than 3 restarts in 15 minutes
- `PersistentVolumeFillingUp` — PVC below 10% free space
- `IngressHigh5xxRate` — 5xx above 5% per ingress
- `IngressHighLatencyP95` — p95 above 1s per ingress

## GPU workloads

Set `gpu_nodes_enabled = true`. The node group starts at 0 and is tainted with `nvidia.com/gpu`, so only pods that tolerate it (e.g. vLLM inference) land there. Install the NVIDIA device plugin or GPU Operator on top.
