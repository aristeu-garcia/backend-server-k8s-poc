# Backend Server — K8s PoC (GitOps com ArgoCD + Kustomize)

Manifests do backend Express, gerenciados via **ArgoCD** em um **minikube local**,
com **Kustomize** para variar dev/prod a partir de uma base única.

## Estrutura

```
k8s/
├── base/                        # manifests comuns a todos os ambientes
│   ├── deployment.yaml
│   ├── service.yaml
│   ├── hpa.yaml
│   └── kustomization.yaml
├── overlays/
│   ├── dev/                     # namespace backend-poc-dev
│   │   ├── kustomization.yaml
│   │   ├── namespace.yaml
│   │   ├── patch-deployment.yaml  # 1 réplica, resources menores, tag "dev"
│   │   ├── patch-hpa.yaml         # min/max 1
│   │   └── patch-service.yaml     # nodePort 30081
│   └── prod/                    # namespace backend-poc-prod
│       ├── kustomization.yaml
│       ├── namespace.yaml
│       └── patch-service.yaml     # nodePort 30080 (usa a base como está)
├── argocd-application-dev.yaml  # Application do ArgoCD -> overlays/dev
├── argocd-application-prod.yaml # Application do ArgoCD -> overlays/prod
└── README.md
```

### Por que Kustomize?

A `base/` tem a definição "canônica" do Deployment/Service/HPA. Cada overlay
referencia a base e aplica só as diferenças (patches) daquele ambiente —
réplicas, requests/limits, tag de imagem, nodePort. Mudou algo comum (porta do
container, probes, nome do app) → edita só a base e os dois ambientes recebem
a mudança. Mudou algo específico de um ambiente → edita só o patch daquele
overlay.

Ver e comparar o resultado final sem aplicar nada:

```bash
kubectl kustomize k8s/overlays/dev
kubectl kustomize k8s/overlays/prod
```

## Fluxo GitOps

```
Git (este repo, pasta k8s/overlays/<env>) ──observa──> ArgoCD ──sincroniza──> minikube
```

O ArgoCD lê o overlay de cada ambiente e mantém o cluster igual ao Git.
Mudou o Git → o Argo aplica no cluster.

## Passo a passo

### 1. Subir o minikube
```bash
minikube start
```

### 2. Instalar o ArgoCD
```bash
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl wait --for=condition=available --timeout=300s -n argocd deployment/argocd-server
```

### 3. Acessar a UI do ArgoCD
```bash
# senha inicial (usuário: admin)
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d; echo

# expõe a UI em https://localhost:8080
kubectl port-forward -n argocd svc/argocd-server 8080:443
```

### 4. Registrar as aplicações
> Ajuste antes o `repoURL` em `argocd-application-dev.yaml` e `argocd-application-prod.yaml`
> para a URL deste repo.
```bash
kubectl apply -f k8s/argocd-application-dev.yaml
kubectl apply -f k8s/argocd-application-prod.yaml
```

> Se você já tinha a Application antiga (`backend-server`, apontando para `k8s`)
> registrada no cluster, remova-a (`kubectl delete application backend-server -n argocd`)
> — ela não existe mais no Git e, com `prune: true`, o Argo já vai marcá-la
> como `OutOfSync`/órfã.

### 5. Acessar o app
```bash
# dev
minikube service backend-server -n backend-poc-dev --url
curl http://$(minikube ip):30081/health

# prod
minikube service backend-server -n backend-poc-prod --url
curl http://$(minikube ip):30080/health
```
