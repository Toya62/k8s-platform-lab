#!/usr/bin/env bash
set -euo pipefail

PROCESSOR_DIR="${PROCESSOR_DIR:-../secure-data-orchestrator-aws/src/processor}"

kind create cluster --name lab --config kind/kind-config.yaml
kubectl create namespace lab

helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
helm upgrade --install kps prometheus-community/kube-prometheus-stack \
  -n monitoring --create-namespace -f monitoring/values.yaml --wait --timeout 10m

kubectl apply -n lab -f k8s/localstack.yaml
kubectl -n lab rollout status deploy/localstack --timeout=300s

docker build -t data-processor:local "$PROCESSOR_DIR"
kind load docker-image data-processor:local --name lab

helm upgrade --install processor charts/processor -n lab --wait --timeout 5m

kubectl apply -n lab -f k8s/otel-collector.yaml -f k8s/statefulset-demo.yaml
kubectl apply -n lab -f k8s/telemetrygen.yaml

kubectl -n lab get pods,jobs,pvc
