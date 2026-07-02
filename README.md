# Backend Server — K8s PoC (GitOps com ArgoCD)

PoC de uma API Express empacotada em Docker e implantada em um **minikube local**,
orquestrada via **GitOps** com **ArgoCD**: o Git é a fonte da verdade e o ArgoCD
mantém o cluster sempre igual ao repositório.

## Como funciona (arquitetura)

O conceito central é **GitOps**: você não aplica coisas no cluster na mão. Você
descreve o estado desejado em arquivos YAML no Git, e um agente (ArgoCD) garante
que o cluster fique igual ao Git.

```
 Você edita YAML        GitHub                 ArgoCD (dentro do             minikube
 na pasta k8s/   ──►   (repo, fonte  ──observa──►  cluster) compara   ──aplica──►  (Deployment,
 e dá git push          da verdade)              Git x cluster                    Service, pods)
                                                 e corrige o que difere
```

### As peças

| Peça | O que é | Papel aqui |
|---|---|---|
| **Imagem Docker** | o app Express empacotado | `aristeukafka/backend-server-k8s-poc:1.0.0` no Docker Hub — o que roda dentro dos pods |
| **minikube** | um cluster Kubernetes de 1 nó na máquina | o "servidor" onde tudo roda |
| **Manifests (`k8s/`)** | YAMLs que descrevem o estado desejado | namespace (isola), deployment (roda 2 réplicas + probes), service (expõe na rede) |
| **ArgoCD** | um controlador que roda **dentro** do cluster | lê o Git e sincroniza no minikube; oferece UI/CLI para ver, sincronizar e fazer rollback |

### Os manifests, um a um

- **`k8s/namespace.yaml`** — cria o `backend-poc`, uma "gaveta" lógica que separa os
  recursos do resto do cluster.
- **`k8s/deployment.yaml`** — o coração. Declara 2 réplicas da imagem na porta 3000.
  As **probes** (`liveness`/`readiness`) batem em `/health`: se o pod trava, o K8s
  reinicia; se ainda não está pronto, não recebe tráfego.
- **`k8s/service.yaml`** — os pods têm IPs que mudam. O Service é um endereço **fixo**
  que balanceia entre as réplicas. Como é `NodePort`, abre a porta `30080` no nó.
- **`k8s/argocd-application.yaml`** — o "contrato" que liga o Argo ao repo: *"observe
  este repositório, pasta `k8s`, branch `main`, e aplique no namespace `backend-poc`"*.

### O detalhe que faz o GitOps "mágico"

O `syncPolicy.automated` no Application. Com ele o cluster **sempre converge para o Git**:

- Deu `kubectl edit` e mudou algo na mão? → o Argo reverte para o Git (`selfHeal`).
- Apagou um arquivo do Git? → o Argo remove o recurso do cluster (`prune`).
- Deu push de uma tag nova? → o Argo aplica sozinho.

Por isso a UI serve mais para *visualizar e fazer rollback* do que para aplicar coisas.

## Estrutura

```
.
├── Dockerfile              # empacota o app Express (node:20-alpine, usuário non-root)
├── package.json
├── src/index.js            # API Express (/, /health, /items)
└── k8s/
    ├── namespace.yaml          # namespace backend-poc
    ├── deployment.yaml         # Deployment (imagem :1.0.0) + probes em /health
    ├── service.yaml            # Service NodePort (30080 -> 3000)
    └── argocd-application.yaml # Application do ArgoCD apontando para este repo
```

## Como iniciar do zero (runbook)

Pré-requisitos: Docker Desktop, minikube, kubectl e gh instalados.

### 1. App + imagem
```bash
docker build -t aristeukafka/backend-server-k8s-poc:1.0.0 .
docker login                                    # use um access token
docker push aristeukafka/backend-server-k8s-poc:1.0.0
```

### 2. Repositório GitOps
```bash
git init && git add -A && git commit -m "app + manifests"
gh repo create backend-server-k8s-poc --public --source=. --push
```

### 3. Cluster
```bash
minikube start
```

### 4. Instalar o ArgoCD no cluster
```bash
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl wait --for=condition=available --timeout=300s -n argocd deployment/argocd-server
```

### 5. Registrar a aplicação (liga Argo -> repo)
```bash
# garanta que o repoURL em k8s/argocd-application.yaml aponta para o SEU repo
kubectl apply -f k8s/argocd-application.yaml
```
A partir daqui o Argo lê o repo, cria namespace/deployment/service e mantém sincronizado.

### 6. Acessar

UI do ArgoCD:
```bash
# senha inicial (usuário: admin)
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d; echo

# abre em https://localhost:8080 (aceite o certificado self-signed)
kubectl port-forward -n argocd svc/argocd-server 8080:443
```

O app:
```bash
kubectl port-forward -n backend-poc svc/backend-server 18080:80
curl http://localhost:18080/health
```

## Ciclo do dia a dia

```
1. edita k8s/deployment.yaml (ex: image :1.0.0 -> :1.1.0)
2. git commit && git push
3. o ArgoCD detecta e sincroniza sozinho (ou clique "Sync" na UI)
4. novos pods sobem com a versão nova
```

Nos passos 1–3 você **nunca roda `kubectl apply`** — essa é a diferença do GitOps para
o deploy tradicional. O único `kubectl apply` manual é o do passo 5 (registrar o
Application), feito **uma única vez**.

## Endpoints da API

| Método | Rota | Descrição |
|---|---|---|
| GET | `/` | mensagem de boas-vindas |
| GET | `/health` | health check (usado pelas probes do K8s) |
| GET | `/items` | lista itens (em memória) |
| POST | `/items` | cria um item |
