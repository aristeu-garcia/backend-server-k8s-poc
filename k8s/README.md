# Backend Server — K8s PoC (GitOps com ArgoCD)

Manifests do backend Express, gerenciados via **ArgoCD** em um **minikube local**.

## Estrutura

```
k8s/
├── namespace.yaml            # namespace backend-poc
├── deployment.yaml           # Deployment (imagem aristeukafka/backend-server-k8s-poc:1.0.0)
├── service.yaml              # Service NodePort (30080 -> 3000)
├── argocd-application.yaml   # Application do ArgoCD apontando para este repo
└── README.md
```

## Fluxo GitOps

```
Git (este repo, pasta k8s/) ──observa──> ArgoCD ──sincroniza──> minikube
```

O ArgoCD lê os manifests do repositório Git e mantém o cluster igual ao Git.
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

### 4. Registrar a aplicação
> Ajuste antes o `repoURL` em `argocd-application.yaml` para a URL deste repo.
```bash
kubectl apply -f k8s/argocd-application.yaml
```

### 5. Acessar o app
```bash
minikube service backend-server -n backend-poc --url
# ou
curl http://$(minikube ip):30080/health
```
