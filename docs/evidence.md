<!--
File:        docs/evidence.md
Assignment:  DSO202 Assignment 4 - GitOps Delivery of the Task Tracker
Descriptor:  4.1.1-4.4.2 (evidence that each GitOps principle holds)
Purpose:     Command output for every task, from the running system.
             Paste real output only. Each block says which command produced it.
-->

# Evidence: DSO202 Assignment 4

Repository: https://github.com/Tshewangdorji7257/dso202-gitops.git
Submitted commit (main): `<sha>`
Tags: `v1.0.0`, `v1.1.0`, `v1.2.0`

---

## Task 1: Tool check, repository and chart

### 1.1 Tool check
```text
$ docker version --format '{{.Server.Version}}'
$ kind version
$ kubectl version --client
$ helm version --short
$ git --version
$ argocd version --client
$ kubeseal --version
(paste output)
```

### 1.2 Sealed Secrets chart is available
```text
$ helm search repo sealed-secrets/sealed-secrets --versions | head -5
(paste output: 2.20.0 must be listed)
```

### 1.3 Chart lint and render
```text
$ helm lint charts/tasktracker -f environments/dev/values.yaml
$ helm lint charts/tasktracker -f environments/staging/values.yaml
$ helm template tasktracker charts/tasktracker -f environments/dev/values.yaml | grep '^kind:' | sort -u
(paste output)
```

### 1.4 .gitignore is the first commit
```text
$ git log --reverse --oneline | head -3
(paste output)
```

---

## Task 2: Argo CD installed from bootstrap/argocd

```text
$ kubectl apply -k bootstrap/argocd --server-side --force-conflicts
$ kubectl get pods -n argocd
(paste output: seven Pods Running)
$ kubectl get cm argocd-cm -n argocd -o jsonpath='{.data.timeout\.reconciliation}'
(paste output: 60s)
```

---

## Task 3: AppProjects and the root Application

```text
$ kubectl apply -f bootstrap/root/
$ argocd app get root
$ argocd proj list
$ argocd proj get dso202
(paste output: dso202 created by root; whitelist ConfigMap, Service, Deployment, StatefulSet, Job)
```

---

## Task 4: Sealed Secrets and platform layer

### 4.1 Controller installed from Git
```text
$ argocd app get sealed-secrets
$ kubectl get pods -n sealed-secrets
(paste output)
```

### 4.2 Key backed up outside the repository
```text
$ ls -l ~/dso202-keys/
$ git ls-files | grep -i key || echo "no key files tracked"
(paste output)
```

### 4.3 Platform Applications healthy, Secrets created from SealedSecrets
```text
$ kubectl get applications -n argocd
$ kubectl get sealedsecret,secret -n dso202-dev
$ kubectl get sealedsecret,secret -n dso202-staging
$ kubectl get resourcequota,limitrange,role,rolebinding -n dso202-dev
(paste output)
```

### 4.4 No plaintext in history
```text
$ git log --all -p | grep -c "$DEV_DB_PASSWORD"      # expect 0
$ git log --all -p | grep -c "$STAGING_DB_PASSWORD"  # expect 0
$ git log --all -p | grep -nE '^\+kind: Secret$' || echo "no Secret manifest ever committed"
(paste output)
```

---

## Task 5: Workloads, waves and smoke test

```text
$ git ls-remote --tags origin
$ argocd app get tasktracker-dev
$ argocd app sync tasktracker-staging
$ argocd app get tasktracker-staging
$ kubectl get pods,svc,pvc -n dso202-dev
$ kubectl get pods,svc,pvc -n dso202-staging
$ kubectl logs job/tasktracker-smoke-test -n dso202-dev
$ kubectl get events -n dso202-dev --sort-by=.lastTimestamp | grep -E 'db-0|backend|frontend' | head -20
(paste output: waves db -> backend -> frontend; SMOKE TEST PASSED)
```

CRUD cycle in dev (http://localhost:30080): create, list, update, delete a task (screenshots or API calls).

---

## Task 6: reviewer account

```text
$ argocd login localhost:8080 --username reviewer --insecure
$ argocd account can-i get applications 'dso202/*'
$ argocd account can-i sync applications 'dso202/*'
$ argocd account can-i get logs 'dso202/*'
(paste output: yes / no / no)

# after the commit that adds the logs rule, and re-applying bootstrap/argocd
$ argocd account can-i get logs 'dso202/*'
(paste output: yes)
```

---

## Task 7: Release, failure and recovery

### 7.1 Frontend 1.1 promoted through v1.1.0
```text
$ argocd app history tasktracker-dev
$ argocd app diff tasktracker-staging
$ argocd app sync tasktracker-staging
$ argocd app history tasktracker-staging
(paste output)
```

### 7.2 Backend 1.1 failure in dev
```text
$ argocd app get tasktracker-dev
$ kubectl get pods -n dso202-dev -l tier=backend
$ kubectl logs <failing-backend-pod> -n dso202-dev --previous
(paste output: the log line that names the cause)
```

### 7.3 argocd app rollback refused
```text
$ argocd app rollback tasktracker-dev
(paste output: refused because automated sync is enabled)
```

### 7.4 Recovery by git revert, then fix-forward and v1.2.0
```text
$ git log --oneline -8
$ argocd app get tasktracker-dev
$ argocd app history tasktracker-staging   # staging went v1.0.0 -> v1.1.0 -> v1.2.0 only
$ gh pr list --state all
(paste output)
```

---

## Task 8: Drills

| Drill | Action | Prediction (written before) | Observation | Explanation |
|---|---|---|---|---|
| 1 Self-heal (dev) | | | | |
| 2 Drift (staging) | | | | |
| 3 Prune | | | | |
| 4 Project boundary | | | | |

(paste the command output for each drill below the table)

---

## Task 9: Rebuild from the repository and the key

```text
Start time:
$ kind delete cluster --name dso202-gitops
$ ... (bootstrap sequence from README section 4)
$ kubectl get applications -n argocd
$ kubectl get secret tasktracker-credentials -n dso202-dev
$ curl -s http://localhost:30080 | head -5
End time:
Elapsed:
(paste output)
```
