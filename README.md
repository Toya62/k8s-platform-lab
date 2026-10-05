# k8s-platform-lab

A small, local Kubernetes learning lab. It runs the batch processor from my AWS project
([secure-data-orchestrator-aws](https://github.com/Toya62/secure-data-orchestrator-aws))
as a Kubernetes Job, packaged with Helm, against a local AWS emulator, with basic
observability (Prometheus, Grafana, OpenTelemetry Collector).

> **Scope and honesty note:** this is a personal lab on a local `kind` cluster. It is **not** a
> production system. It exists to practise Kubernetes, Helm and observability concepts hands-on.

## What it demonstrates

| Topic | Where |
|---|---|
| Helm chart (templates, values, hooks) | `charts/processor/` |
| Kubernetes Job (batch workload) | `charts/processor/templates/job.yaml` |
| ConfigMap and Secret usage | `charts/processor/templates/configmap.yaml`, `secret.yaml` |
| Network segmentation (NetworkPolicy) | `charts/processor/templates/networkpolicy.yaml` |
| Stateful workload (StatefulSet + PersistentVolume) | `k8s/statefulset-demo.yaml` |
| Local AWS (S3, DynamoDB) via LocalStack | `k8s/localstack.yaml` |
| OpenTelemetry Collector (OTLP in, Prometheus out) | `k8s/otel-collector.yaml` |
| Metrics and dashboards (Prometheus, Grafana) | `monitoring/values.yaml` |
| CI (helm lint + helm template) | `.github/workflows/ci.yml` |

## Architecture

```
processor Job (Helm) --> LocalStack (S3 + DynamoDB audit table)
telemetrygen Jobs --OTLP--> OTel Collector --:8889--> Prometheus --> Grafana
StatefulSet demo (PVC) -- shows persistent storage
```

The processor reads `S3_BUCKET`, `S3_KEY`, `JOB_ID`, `DYNAMODB_TABLE` and `ORG_ID`, checks the
object in S3 and writes audit records (`Processing Start`, `Completion`) to DynamoDB.
The `telemetrygen` Jobs send synthetic traces and metrics, because the processor itself is not
instrumented with OpenTelemetry.

## Prerequisites

Docker, [kind](https://kind.sigs.k8s.io/), kubectl, Helm 3, and a local clone of the processor repo:

```bash
git clone https://github.com/Toya62/secure-data-orchestrator-aws ../secure-data-orchestrator-aws
```

## Run it

```bash
./scripts/up.sh
```

Or step by step:

```bash
kind create cluster --name lab --config kind/kind-config.yaml
kubectl create namespace lab

# 1. Monitoring stack
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm upgrade --install kps prometheus-community/kube-prometheus-stack \
  -n monitoring --create-namespace -f monitoring/values.yaml --wait --timeout 10m

# 2. Local AWS
kubectl apply -n lab -f k8s/localstack.yaml
kubectl -n lab rollout status deploy/localstack

# 3. Build and load the processor image
docker build -t data-processor:local ../secure-data-orchestrator-aws/src/processor
kind load docker-image data-processor:local --name lab

# 4. Install the chart (a pre-install hook creates the bucket, object and table)
helm upgrade --install processor charts/processor -n lab

# 5. Collector, stateful demo, synthetic telemetry
kubectl apply -n lab -f k8s/otel-collector.yaml -f k8s/statefulset-demo.yaml
kubectl apply -n lab -f k8s/telemetrygen.yaml
```

## Verify

```bash
kubectl -n lab get jobs,pods
kubectl -n lab logs job/$(kubectl -n lab get jobs -o name | grep processor | head -1 | cut -d/ -f2)
kubectl -n lab get pvc
kubectl -n monitoring port-forward svc/kps-grafana 3000:80   # login admin / admin (lab only)
kubectl -n monitoring port-forward svc/kps-kube-prometheus-stack-prometheus 9090:9090
```

In Prometheus, check Status > Targets for the `otel-collector` target. In Grafana, explore the
Prometheus data source and the built-in Kubernetes dashboards.

## Clean up

```bash
./scripts/down.sh
```

## Known limitations (read before discussing this project)

- Local only; one `kind` cluster, no EKS, no real AWS, no real VPC.
- Credentials are dummy values for LocalStack. A real setup would use IAM roles and a secret manager.
- NetworkPolicy is only enforced if the cluster CNI supports it; the default kind CNI may not.
- The processor container runs as root and Python 3.9, inherited from the original project.
- The processor has no OpenTelemetry instrumentation; telemetry in this lab is synthetic.
- Image tags are pinned for reproducibility, but chart versions of the monitoring stack are not.

## What I would do next

Instrument the processor with the OpenTelemetry SDK, add a Grafana dashboard as code, run as
non-root, add resource-based alerts, and try the same chart on EKS with IAM Roles for Service Accounts.
