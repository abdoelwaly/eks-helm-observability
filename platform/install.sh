#!/usr/bin/env bash
# Installs the monitoring stack and the demo app with its SLOs.
# Needs: kubectl pointed at the cluster, helm, and these env vars:
#   GRAFANA_ADMIN_PASSWORD
#   SLACK_PAGE_WEBHOOK, SLACK_TICKET_WEBHOOK (optional; alerts go nowhere without them)
set -euo pipefail

KPS_VERSION="93.3.0"
PODINFO_VERSION="6.17.0"
here="$(cd "$(dirname "$0")" && pwd)"

: "${GRAFANA_ADMIN_PASSWORD:?set GRAFANA_ADMIN_PASSWORD}"

kubectl apply -f "$here/storageclass-gp3.yaml"
kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -

kubectl -n monitoring create secret generic grafana-admin \
  --from-literal=admin-user=admin \
  --from-literal=admin-password="$GRAFANA_ADMIN_PASSWORD" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl -n monitoring create secret generic alertmanager-slack \
  --from-literal=page-url="${SLACK_PAGE_WEBHOOK:-http://localhost/disabled}" \
  --from-literal=ticket-url="${SLACK_TICKET_WEBHOOK:-http://localhost/disabled}" \
  --dry-run=client -o yaml | kubectl apply -f -

helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null
helm repo update prometheus-community >/dev/null

helm upgrade --install kps prometheus-community/kube-prometheus-stack \
  --version "$KPS_VERSION" \
  --namespace monitoring \
  --values "$here/kube-prometheus-stack.values.yaml" \
  --set 'alertmanager.alertmanagerSpec.secrets={alertmanager-slack}' \
  --wait --timeout 10m

helm upgrade --install podinfo "$here/../charts/podinfo-slo" \
  --namespace demo --create-namespace \
  --set image.tag="$PODINFO_VERSION" \
  --wait --timeout 5m

echo
echo "Grafana:      kubectl -n monitoring port-forward svc/kps-grafana 3000:80"
echo "Prometheus:   kubectl -n monitoring port-forward svc/kps-prometheus 9090:9090"
echo "Load test:    make load"
