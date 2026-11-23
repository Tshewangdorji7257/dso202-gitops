<!--
File:        README.md
Assignment:  DSO202 Assignment 4 - GitOps Delivery of the Task Tracker
Descriptor:  4.1.1, 4.1.2 (GitOps principles, repository as desired state)
Purpose:     What this repository is, the pinned versions, how to build the
             whole environment from an empty machine, how to clean up, how
             credentials are handled, and the written answers Q1-Q6.
-->

# dso202-gitops: GitOps delivery of the Task Tracker with Argo CD

## 1. Purpose

This repository is the single source of truth for the DSO202 Task Tracker (PostgreSQL StatefulSet, backend, frontend). Argo CD runs in the cluster, polls this repository every 60 seconds, and makes the cluster match it. After a short bootstrap, nobody runs `kubectl apply` or `helm install`: a release is a commit, a promotion is a tag, and a recovery is a `git revert`.

| Environment | Namespace | Follows | Sync | Frontend |
|---|---|---|---|---|
| dev | `dso202-dev` | branch `main` | automated, prune, self-heal | http://localhost:30080 |
| staging | `dso202-staging` | a tag (`v1.0.0`, `v1.1.0`, `v1.2.0`) | manual | NodePort 30081, `kubectl port-forward` |

The Helm chart in `charts/tasktracker` is the Assignment 3 chart (`dso202-app`), changed for GitOps. It no longer creates the namespace, the quota, the Secret or the Ingress. Those now come from `platform/<env>/` or are no longer used.

## 2. Pinned versions

| Component | Version |
|---|---|
| Argo CD (server and `argocd` CLI) | v3.5.6 |
| Sealed Secrets Helm chart | 2.20.0 |
| Sealed Secrets controller / `kubeseal` | 0.40.0 / v0.40.0 |
| Task Tracker images | `rynorbu11/dso202-{frontend,backend,db}`: 1.0; frontend and backend 1.1 for the release |
| Smoke-test image | `busybox:1.37` |
| kind, node image, kubectl | as in Practical 1 |
| Helm | as in Assignment 3 (v3.18.6) |

## 3. Repository layout

```
bootstrap/argocd/      Argo CD v3.5.6 + local settings       (applied by hand)
bootstrap/root/        platform AppProject + root Application (applied by hand)
argocd/projects/       dso202 AppProject                      (wave -3, from Git)
argocd/applications/   sealed-secrets (-2), platform-* (-1), tasktracker-* (0)
platform/<env>/        namespace, quota and limits, RBAC, SealedSecret
charts/tasktracker/    the workload chart (identical in both environments)
environments/<env>/    the values that differ per environment
cluster/               kind configuration
docs/evidence.md       command output for every task
```

## 4. Build everything from an empty machine

Prerequisites: Docker, kind, kubectl, Helm, git, `argocd` v3.5.6 and `kubeseal` v0.40.0 installed, and `docker login` done. The sealing-key backup must be at `~/dso202-keys/sealed-secrets-key-backup.yaml`, **outside** this repository.

```bash
# 1. Cluster
git clone https://github.com/Tshewangdorji7257/dso202-gitops.git && cd dso202-gitops
kind create cluster --config cluster/kind-cluster.yaml

# 2. Argo CD (server-side apply: the ApplicationSet CRD is too large for client-side apply)
kubectl apply -k bootstrap/argocd --server-side --force-conflicts
kubectl wait --for=condition=Available deployment --all -n argocd --timeout=300s

# 3. Restore the sealing key BEFORE the controller starts, so old SealedSecrets decrypt
#    (first build ever: skip this step, then back up the key after the controller starts)
kubectl create namespace sealed-secrets
grep -v -E '^\s+(resourceVersion|uid|creationTimestamp):' \
  ~/dso202-keys/sealed-secrets-key-backup.yaml | kubectl apply -f -

# 4. Hand over to Git: platform project and root Application
kubectl apply -f bootstrap/root/

# 5. Watch the waves: dso202 project -> sealed-secrets -> platform-* -> tasktracker-*
kubectl get applications -n argocd -w

# 6. Staging is manual: sync it once
kubectl port-forward svc/argocd-server -n argocd 8080:443 &
argocd login localhost:8080 --username admin --insecure \
  --password "$(argocd admin initial-password -n argocd | head -1)"
argocd app sync tasktracker-staging

# 7. Check
curl -s http://localhost:30080 | head -5                        # dev frontend
kubectl port-forward svc/frontend-svc -n dso202-staging 8081:8080 # staging frontend
```

## 5. Cleanup

```bash
kubectl delete -f bootstrap/root/root-app.yaml   # finalizers remove every child and workload
kind delete cluster --name dso202-gitops         # removes everything, including the sealing key
```

Keep `~/dso202-keys/` if you will rebuild. Without that backup, the SealedSecrets in Git cannot be decrypted on a new cluster.

## 6. How credentials are handled

- The database credentials exist in Git **only** as SealedSecrets: `platform/dev/tasktracker-credentials.sealed.yaml` and `platform/staging/tasktracker-credentials.sealed.yaml`. Each is sealed separately and has strict scope, so it decrypts only with this name, in this namespace, on a cluster that holds the matching private key.
- The plaintext Secret is never written to disk. `kubectl create secret ... --dry-run=client -o yaml` is piped straight into `kubeseal`.
- The Sealed Secrets controller turns each SealedSecret into the Secret `tasktracker-credentials`, which the chart reads by name (`credentials.secretName`). The chart contains no password.
- The sealing key is backed up outside the repository (`~/dso202-keys/`) and is matched by `.gitignore`. The proof that nothing leaked is the history search in `docs/evidence.md`, Task 4.

## 7. Written answers

### Q1
_(answer)_

### Q2
_(answer)_

### Q3
_(answer)_

### Q4
_(answer)_

### Q5
_(answer)_

### Q6
**Part 1:** _(answer)_

**Part 2:** _(answer)_
