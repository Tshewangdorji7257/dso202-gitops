# dso202-gitops: GitOps delivery of the Task Tracker with Argo CD

## 1. Purpose

This repository is the single source of truth for the DSO202 Task Tracker: a PostgreSQL StatefulSet, a backend API and a frontend. **Argo CD** runs inside the cluster, polls this repository every 60 seconds, and makes the cluster match it.

After a short bootstrap, nobody runs `kubectl apply` or `helm install` for the application:

- **A release is a commit.** Changing an image tag on `main` deploys it to dev.
- **A promotion is a tag.** Staging follows a Git tag and changes only when a person moves the tag and syncs.
- **A recovery is a `git revert`.** Rolling back in Argo CD is refused while automated sync is on; Git is the only way back.
- **Credentials are in Git only as SealedSecrets**, and the whole environment can be rebuilt from this repository plus one backed-up key.

| | dev | staging |
|---|---|---|
| Namespace | `dso202-dev` | `dso202-staging` |
| Application | `tasktracker-dev` | `tasktracker-staging` |
| Follows | branch `main` | a tag: `v1.0.0` → `v1.1.0` → `v1.2.0` |
| Sync | automated, prune, self-heal | manual (the promotion gate) |
| Replicas (backend / frontend) | 1 / 1 | 2 / 2 |
| `LOG_LEVEL` | `debug` | `info` |
| Frontend | NodePort 30080 → http://localhost:30080 | NodePort 30081 → `kubectl port-forward` to 8081 |
| `BACKEND_URL` (used by the browser) | http://localhost:8090 | http://localhost:8091 |
| Credentials | `platform/dev/tasktracker-credentials.sealed.yaml` | `platform/staging/tasktracker-credentials.sealed.yaml` |

## 2. Pinned versions

| Component | Version |
|---|---|
| Argo CD (server and `argocd` CLI) | v3.5.6 |
| Sealed Secrets Helm chart | 2.20.0 |
| Sealed Secrets controller / `kubeseal` | 0.40.0 / v0.40.0 |
| kind / node image / kubectl | v0.32.0 / Kubernetes v1.36.1 / v1.32.2 (as in Practical 1) |
| Helm | v3.18.6 (as in Assignment 3) |
| Task Tracker images | `rynorbu11/dso202-frontend` 1.1, `rynorbu11/dso202-backend` 1.1, `rynorbu11/dso202-db` 1.0 |
| Smoke-test image | `busybox:1.37` |

No file uses `latest`, `stable`, `master` or `HEAD` as a version.

## 3. Repository layout

```
dso202-gitops/
├── README.md                     this file
├── .gitignore                    keeps keys and plaintext Secrets out of Git
├── cluster/kind-cluster.yaml     kind cluster "dso202-gitops" (Practical 1 configuration)
├── bootstrap/                    applied by hand, once per cluster
│   ├── argocd/                   Argo CD v3.5.6 + local settings (polling, health check, reviewer, RBAC)
│   └── root/                     platform AppProject + root Application
├── argocd/                       watched by the root Application ("app of apps")
│   ├── projects/dso202.yaml      least-privilege workload project      (wave -3)
│   └── applications/
│       ├── sealed-secrets.yaml   Sealed Secrets controller             (wave -2)
│       ├── platform-dev.yaml     namespace, quota, RBAC, credentials   (wave -1)
│       ├── platform-staging.yaml
│       ├── tasktracker-dev.yaml  workloads, follows main              (wave 0)
│       └── tasktracker-staging.yaml  workloads, follows a tag          (wave 0)
├── platform/{dev,staging}/       namespace, quota and limits, Role/RoleBinding, SealedSecret
├── charts/tasktracker/           the Assignment 3 chart, adapted for GitOps (identical in both environments)
├── environments/{dev,staging}/   values.yaml: only what differs per environment
├── docs/evidence.md              evidence for Tasks 1-9 (figures and command output)
└── evidence/                     screenshots referenced by docs/evidence.md
```

### Changes to the Assignment 3 chart

| Change | Reason |
|---|---|
| Renamed `dso202-app` → `tasktracker` (chart 1.0.0) | Layout of section 7 |
| Removed `secret.yaml`; Pods read the Secret `tasktracker-credentials` by name | Credentials come only from SealedSecrets in `platform/<env>/` |
| Removed `quota.yaml` (now in `platform/<env>/`) | The workload project must not be able to create quotas |
| Removed `ingress.yaml`; frontend Service is NodePort | Access by NodePort (section 6.3) |
| Removed the Helm test Pod and `NOTES.txt` | Replaced by an Argo CD PostSync smoke-test Job |
| Sync waves: ConfigMap 0, database 1, backend 2, frontend 3 | Database, then backend, then frontend |
| StatefulSet `RollingUpdate`; Deployments `progressDeadlineSeconds: 120` | Health is reported correctly; a crashing release becomes Degraded |
| `checksum/config` on backend and frontend only | A config change does not restart PostgreSQL |
| Requests and limits on every container, including the smoke test | Required by the namespace quota |
| `values.schema.json`: environment `dev`/`staging`, exact numeric image tags | No `latest` can get in |
| `TASK_PAGE_SIZE: "50"` in the config defaults | Required by backend 1.1 at start-up (found in its log, Task 7) |

## 4. Build everything from an empty machine

These are the commands used in Task 9, on Windows PowerShell. Prerequisites: Docker Desktop running, kind, kubectl, Helm, git, `argocd` v3.5.6 and `kubeseal` v0.40.0 on the PATH, and `docker login` done. The sealing-key backup must be at `C:\Users\<you>\dso202-keys\sealed-secrets-key-backup.yaml`, **outside** this repository.

```powershell
# 1. Get the repository and create the cluster
git clone https://github.com/Tshewangdorji7257/dso202-gitops.git
cd dso202-gitops
$start = Get-Date
kind create cluster --config cluster/kind-cluster.yaml

# 2. Install Argo CD (server-side apply: the ApplicationSet CRD is too large for client-side apply)
kubectl apply -k bootstrap/argocd --server-side --force-conflicts
kubectl wait --for=condition=Ready pod --all -n argocd --timeout=900s

# 3. Restore the sealing key BEFORE the controller starts, so the SealedSecrets in Git decrypt
#    (first build ever: skip this step, and back up the key once the controller is running - see section 6)
kubectl create namespace sealed-secrets
Get-Content $HOME\dso202-keys\sealed-secrets-key-backup.yaml |
  Where-Object { $_ -notmatch '^\s+(resourceVersion|uid|creationTimestamp):' } |
  kubectl apply -f -

# 4. Hand over to Git: platform project + root Application. Everything else comes from the repository.
kubectl apply -f bootstrap/root/
kubectl get applications -n argocd -w        # waves: dso202 -> sealed-secrets -> platform-* -> tasktracker-*

# 5. Argo CD API and UI (separate window; port 8080 is reserved on Windows)
kubectl port-forward svc/argocd-server -n argocd 8443:443

# 6. Log in, sync staging (manual by design), set the reviewer password
$p = kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}"
[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($p))
argocd login localhost:8443 --username admin --insecure
argocd app sync tasktracker-staging
argocd account update-password --account reviewer --current-password "ADMIN_PASSWORD" --new-password "REVIEWER_PASSWORD"

# 7. Check
argocd app list                                             # all six Synced / Healthy
kubectl logs job/tasktracker-smoke-test -n dso202-dev       # SMOKE TEST PASSED
kubectl logs job/tasktracker-smoke-test -n dso202-staging   # SMOKE TEST PASSED
"Elapsed: {0:hh\:mm\:ss}" -f ((Get-Date) - $start)
```

### Opening the application

The frontend runs in the browser and calls the backend at `BACKEND_URL`, so the backend must also be reachable from the host. Each command runs in its own window:

```powershell
# dev   -> http://localhost:30080
kubectl port-forward svc/backend-svc  -n dso202-dev     8090:8080

# staging -> http://localhost:8081
kubectl port-forward svc/frontend-svc -n dso202-staging 8081:8080
kubectl port-forward svc/backend-svc  -n dso202-staging 8091:8080
```

### Showing CLI diffs on Windows

`argocd app diff` needs an external `diff` program. Git for Windows provides one:

```powershell
$env:KUBECTL_EXTERNAL_DIFF = "C:\PROGRA~1\Git\usr\bin\diff.exe -u"
```

## 5. Cleanup

```powershell
kubectl delete -f bootstrap/root/root-app.yaml   # finalizers remove every child Application and its workloads
kind delete cluster --name dso202-gitops         # removes everything, including the in-cluster sealing key
```

Keep `C:\Users\<you>\dso202-keys\` if the environment will be rebuilt. Without that backup, the SealedSecrets in Git cannot be decrypted on a new cluster.

## 6. How credentials are handled

- The database credentials exist in Git **only** as SealedSecrets, one per environment, each sealed separately with a different password. Strict scope means each one decrypts only as `tasktracker-credentials` in its own namespace, on a cluster that holds the matching private key.
- The plaintext Secret is never written to disk. `kubectl create secret ... --dry-run=client -o yaml` is piped straight into `kubeseal`:
  ```powershell
  kubectl create secret generic tasktracker-credentials -n dso202-dev `
    --from-literal=DB_USER=taskuser "--from-literal=DB_PASSWORD=$pw" `
    --from-literal=POSTGRES_USER=taskuser "--from-literal=POSTGRES_PASSWORD=$pw" `
    --dry-run=client -o yaml |
  kubeseal --controller-name sealed-secrets-controller --format yaml
  ```
- The Sealed Secrets controller turns each SealedSecret into the Secret `tasktracker-credentials`. The chart reads it by name (`credentials.secretName`) and contains no password.
- The sealing key is backed up **outside** the repository:
  ```powershell
  kubectl get secret -n sealed-secrets -l sealedsecrets.bitnami.com/sealed-secrets-key -o yaml |
    Set-Content -Encoding ascii $HOME\dso202-keys\sealed-secrets-key-backup.yaml
  ```
  Key files are also matched by `.gitignore`, but that is only a safety net. The proof is a search of the whole Git history for both passwords, which returns 0 matches (`docs/evidence.md`, Task 4).
- Non-secret settings such as `TASK_PAGE_SIZE` and `BACKEND_URL` go in the ConfigMap values, never in a SealedSecret.

## 7. Releases and promotion

| Tag | Content | Reached staging |
|---|---|---|
| `v1.0.0` | frontend 1.0, backend 1.0, db 1.0 | Task 5 (manual sync) |
| `v1.1.0` | frontend 1.1; staging `BACKEND_URL` fix | Task 7 (PR to `targetRevision`, manual sync) |
| `v1.2.0` | backend 1.1 with `TASK_PAGE_SIZE` | Task 7 (PR to `targetRevision`, manual sync) |

Backend 1.1 without `TASK_PAGE_SIZE` crashed in dev, was diagnosed from its log, reverted with `git revert` (PR #11) and fixed forward (PR #12). It was never tagged, so staging never ran it.

Promotion procedure:

1. Merge the change to `main` through a pull request. Dev deploys it automatically, and the smoke test checks it.
2. Tag the commit: `git tag -a vX.Y.Z -m "..."`, then `git push origin vX.Y.Z`.
3. Open a pull request that changes `targetRevision` in `argocd/applications/tasktracker-staging.yaml` to the new tag, and merge it.
4. Review the change with `argocd app diff tasktracker-staging`, then run `argocd app sync tasktracker-staging`.

## 8. Access control

| Account | Can do |
|---|---|
| `admin` | everything (bootstrap and operations) |
| `reviewer` | view the `dso202` Applications and read their logs; cannot sync, edit or see the platform Applications |

The policy is in `bootstrap/argocd/argocd-rbac-cm-patch.yaml`. The logs permission was added by a separate commit (PR #5).

