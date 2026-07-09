#!/usr/bin/env bash
set -euo pipefail

NS="backend-poc"
SVC="backend-server"
WORKERS="${WORKERS:-50}"
DURATION="${DURATION:-180}"
LOADGEN="load-gen"
URL="http://${SVC}.${NS}.svc.cluster.local/items"

log() { printf '\033[1;36m==>\033[0m %s\n' "$*"; }

cleanup() {
  log "removendo o pod de carga (${LOADGEN})..."
  kubectl delete pod "${LOADGEN}" -n "${NS}" --ignore-not-found --wait=false >/dev/null 2>&1 || true
}
trap cleanup EXIT INT TERM

if ! kubectl top pods -n "${NS}" >/dev/null 2>&1; then
  log "metrics-server não respondeu. Tentando habilitar no minikube..."
  if command -v minikube >/dev/null 2>&1; then
    minikube addons enable metrics-server || true
    log "aguardando o metrics-server subir (até 90s)..."
    kubectl -n kube-system rollout status deployment/metrics-server --timeout=90s || true
  else
    echo "!! metrics-server indisponível e minikube não encontrado."
    echo "   Habilite manualmente antes de rodar (o HPA precisa de métricas de CPU)."
    exit 1
  fi
fi

log "aplicando o HPA..."
kubectl apply -f "$(dirname "$0")/../k8s/hpa.yaml"

cleanup
log "subindo o pod de carga: ${WORKERS} workers batendo em ${URL} por ${DURATION}s"
kubectl run "${LOADGEN}" -n "${NS}" \
  --image=busybox:1.36 --restart=Never \
  --command -- /bin/sh -c "
    i=0
    while [ \$i -lt ${WORKERS} ]; do
      ( end=\$(( \$(date +%s) + ${DURATION} ))
        while [ \$(date +%s) -lt \$end ]; do
          wget -q -O /dev/null ${URL} || true
        done ) &
      i=\$((i+1))
    done
    wait
  "

kubectl wait --for=condition=Ready "pod/${LOADGEN}" -n "${NS}" --timeout=60s

log "gerando carga... acompanhe abaixo (Ctrl+C interrompe e limpa)."
echo
deadline=$(( $(date +%s) + DURATION + 30 ))
while [ "$(date +%s)" -lt "$deadline" ]; do
  hpa=$(kubectl get hpa "${SVC}" -n "${NS}" \
        -o jsonpath='{.status.currentReplicas}/{.spec.maxReplicas} pods | CPU {.status.currentMetrics[0].resource.current.averageUtilization}% (alvo {.spec.metrics[0].resource.target.averageUtilization}%)' 2>/dev/null || echo "sem dados")
  ready=$(kubectl get pods -n "${NS}" -l app="${SVC}" \
          --field-selector=status.phase=Running -o name 2>/dev/null | wc -l | tr -d ' ')
  printf '\r\033[K[%s] HPA: %s | pods Running: %s' "$(date +%T)" "$hpa" "$ready"

  replicas=$(kubectl get hpa "${SVC}" -n "${NS}" -o jsonpath='{.status.currentReplicas}' 2>/dev/null || echo 0)
  if [ "${replicas:-0}" -ge 2 ]; then
    echo
    log "🎉 escalou! agora estão rodando ${replicas} pods."
    echo "   (a carga continua até acabar; o HPA volta pra 1 sozinho depois que a CPU baixar)"
    break
  fi
  sleep 3
done
echo
log "estado final:"
kubectl get hpa "${SVC}" -n "${NS}"
kubectl get pods -n "${NS}" -l app="${SVC}"
