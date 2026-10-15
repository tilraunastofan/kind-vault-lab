# Diagrams

Mermaid renders natively on GitHub. The overview is an SVG with the official Kubernetes and OpenBao logos
(embedded, so it works as a plain `<img>`); logo sources are in `images/logos/`.

## Architecture

![kind-vault-lab architecture](images/architecture.svg)

Three addresses reach the same OpenBao: the laptop uses `https://bao.orb.local` (OrbStack HTTPS), pods use
`https://bao:8200` (lab CA), and OpenBao calls the API server at `https://vault-lab-control-plane:6443`.
That only works because the `bao` container is attached to the `kind` docker network.

## 1. `kubernetes` auth: namespace + service account

```mermaid
sequenceDiagram
    autonumber
    participant P as ☸ Pod<br/>team-a / payments
    participant B as OpenBao<br/>auth/kubernetes
    participant K as ☸ kube-apiserver
    participant S as Secret engines<br/>kv-v2 · database
    participant PG as Postgres

    Note over P: projected token, aud = "bao"<br/>(default API-server token is rejected)
    P->>B: POST auth/kubernetes/login {role: app, jwt}
    B->>B: role "app": namespace in allow-list?<br/>(team-a, team-b only)
    B->>K: TokenReview(jwt) as SA bao-auth<br/>(system:auth-delegator)
    K-->>B: authenticated: team-a / payments
    B->>B: entity alias metadata =<br/>service_account_namespace, service_account_name
    B-->>P: token, policy k8s-app only, TTL 5m

    Note over B: policy path templates are resolved per request<br/>from the alias metadata of the token's entity
    P->>S: GET secret/data/apps/team-a/payments/config
    S-->>P: 200 (own secret)
    P->>S: GET secret/data/apps/team-a/frontend/config
    S-->>P: 403 (template resolves to payments, not frontend)
    P->>S: GET database/creds/team-a-payments
    S->>PG: CREATE ROLE "v-..." VALID UNTIL now+5m
    S-->>P: 200 username + password (lease 5m, max 15m)
```

## 2. `jwt` auth: adds the pod name

The `kubernetes` method cannot see the pod name; projected tokens carry it as a claim, so the JWT is validated
locally against the API server's pinned public key. No call to the API server is made.

```mermaid
sequenceDiagram
    autonumber
    participant P as ☸ Pod ledger-0<br/>team-a / SA ledger
    participant B as OpenBao<br/>auth/jwt-k8s
    participant S as kv-v2

    P->>B: POST auth/jwt-k8s/login {role: pod, jwt}
    B->>B: verify signature (pinned SA public key),<br/>iss = kubernetes.default.svc, aud = bao
    B->>B: bound_claims: /kubernetes.io/namespace ∈ {team-a, team-b}
    B->>B: entity alias = pod UID (/kubernetes.io/pod/uid)<br/>metadata: namespace, pod_name, service_account
    B-->>P: token, policy k8s-pod only, TTL 5m
    P->>S: GET secret/data/pods/team-a/ledger-0/config
    S-->>P: 200
    P->>S: GET secret/data/pods/team-a/ledger-1/config
    S-->>P: 403 (policy resolves pod_name = ledger-0)
```

## 3. Where a request is stopped

```mermaid
flowchart TD
    A([Pod sends login with projected SA token]) --> B{aud = bao?}
    B -- no --> X1[/login rejected/]
    B -- yes --> C{namespace in allow-list?<br/>team-a, team-b}
    C -- "no (team-c)" --> X2[/login refused: 403 kubernetes, 400 jwt/]
    C -- yes --> D[token issued<br/>only the templated policy, no default policy<br/>TTL 5 min]
    D --> E{request path}
    E -- "own secret, own namespace share,<br/>own DB role" --> OK1([200])
    E -- "another SA / namespace / pod" --> X3[/403: template resolves to caller's identity/]
    E -- "write, list, sys/*" --> X4[/403: policy is read-only and anchored/]
    OK1 --> AU[(audit log: every request, secrets HMAC'd)]
    X3 --> AU
    X4 --> AU
    X1 --> AU
    X2 --> AU
```

## 4. Who owns what: Kustomize vs Terraform

```mermaid
flowchart LR
    subgraph K["k8s/ - Kustomize (kubectl apply -k)"]
        NS[namespaces + tenant SAs]
        BA[bao-auth SA + token + auth-delegator]
        CA[ClusterTrustBundle<br/>lab CA, cluster-wide]
        PG[postgres + root password Secret]
    end
    subgraph T["terraform/ - OpenBao only"]
        AU[auth mounts + roles]
        PO[policies]
        KV[kv data + database engine]
    end
    BA -- "reviewer token (read-only data source)" --> T
    PG -- "root password (read-only data source)" --> T
    API[kube-apiserver] -- "cluster CA" --> T
    T -- "configures" --> BAO[(OpenBao)]
    K -- "applied to" --> API
```

## 5. Bootstrap and startup

```mermaid
flowchart LR
    T[task up] --> BU[bao:up<br/>CA + certs, compose up, init once]
    BU --> US[bao-unseal sidecar<br/>unseals when status exit code = 2]
    BU --> CL[cluster:up<br/>kind create, attach bao to kind network]
    CL --> K8[k8s:apply<br/>kubectl apply -k k8s: namespaces, SAs, trust bundle, postgres]
    K8 --> WS[tf:workspace<br/>HCP workspace, local execution]
    WS --> TF[tf:apply<br/>OpenBao only: auth mounts, policies, data, DB engine]
    TF --> SM[task smoke<br/>34 allow/deny checks from real pods]
```
