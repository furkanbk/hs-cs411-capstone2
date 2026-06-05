# hs-cs411-capstone2

Express sample app deployed end-to-end by a **Jenkins** pipeline to:

1. the `target` lab host (via SCP + SSH, runs as a plain Node process)
2. the `docker` lab host (build -> push to ttl.sh -> pull + run)
3. **Kubernetes** at `https://kubernetes:6443` (stretch goal, via `k8s/`)

```
app.get('/') -> { name: "Hello", description: "World", url: <host header> }
port 4444
```

---

## 1. Local quick check

```bash
npm test                   # node:test runner
npm start                  # listens on :4444
curl http://127.0.0.1:4444/
docker build -t hs411:dev .
docker run --rm -p 4444:4444 hs411:dev
```

---

## 2. Files

| File | Purpose |
| --- | --- |
| `index.js` | Express app (given, unchanged) |
| `index.test.js` | `node:test` unit test (given, unchanged) |
| `package.json` | Added `name`, `version`, `scripts.test` |
| `Dockerfile` | Single-stage, matches the hint (`node:24-alpine`) |
| `Dockerfile.multistage` | Bonus multi-stage build |
| `Jenkinsfile` | **Full pipeline** (60 + 30 pts) |
| `Jenkinsfile.simple` | Bonus: small multistage pipeline (no docker / k8s) |
| `k8s/deployment.yaml` | 2 replicas, probes on `GET /`, ttl.sh image |
| `k8s/service.yaml` | NodePort 30444 -> 4444 |
| `.dockerignore` | Trims the build context |

---

## 3. Required Jenkins setup (one time)

### 3.1 Tools
*Manage Jenkins  ->  Tools  ->  NodeJS Installations*
- Name: **`NodeJS-24`**
- Version: install automatically, **`24.x`** (current)
- Global npm packages to install: *(leave empty)*

### 3.2 Credentials
*Manage Jenkins  ->  Credentials  ->  (some Store)  ->  Global*

| ID | Kind | Fields |
| --- | --- | --- |
| **`LAB_SSH_KEY`** | SSH Username with private key | Username = the unix user whose public half is on `target` and `docker` (typically `laborant`); Private Key = paste the PEM, no passphrase |
| **`KUBECONFIG`** | Secret file | Upload the kubeconfig that targets `https://kubernetes:6443`. **Only required for the Kubernetes stretch stage.** |

### 3.3 Plugins
`NodeJS`, `Pipeline`, `Credentials Binding`, `SSH Build Agents` (or just `ssh-agent`),
`Workspace Cleanup`, `AnsiColor`, `Timestamper`. (All pre-installed on the standard
Jenkins LTS image used in the lab.)

### 3.4 DNS
The pipeline assumes the following hostnames resolve from the Jenkins VM
(`/etc/hosts` is fine):

| hostname | role |
| --- | --- |
| `target`  | plain Linux box where the binary is unpacked and run with `node` |
| `docker`  | host with a working `docker` CLI / daemon |
| `kubernetes` (TCP 6443) | cluster API server |

If your lab uses different hostnames, override the env vars in the job:
`TARGET_HOST`, `DOCKER_HOST`, `K8S_ENDPOINT`.

---

## 4. Pipeline flow (`Jenkinsfile`)

```
+---------+   +-----------+   +----------------+   +-------------------+
|  Test   |-->|  Package  |-->|  Deploy Target |-->|  Build Docker     |
| npm test|   |  tar.gz   |   |  scp + ssh     |   |  docker build     |
+---------+   +-----------+   +----------------+   +-------------------+
                                                       |
                                                       v
                                            +----------------------+
                                            |  Push ttl.sh         |
                                            |  docker push         |
                                            +----------------------+
                                                       |
                                                       v
                                            +----------------------+
                                            |  Deploy Docker Host  |
                                            |  ssh + docker run    |
                                            +----------------------+
                                                       |
                                                       v
                                            +----------------------+
                                            |  Health Check        |
                                            |  curl :4444          |
                                            +----------------------+
                                                       |
                                              (stretch)
                                                       v
                                            +----------------------+
                                            |  Deploy Kubernetes   |
                                            |  kubectl apply       |
                                            +----------------------+
```

### 4.1 SSH pattern

All SSH/SCP calls go through the `LAB_SSH_KEY` Jenkins credential:

```groovy
withCredentials([sshUserPrivateKey(credentialsId: 'LAB_SSH_KEY',
                                   keyFileVariable: 'SSH_KEY')]) {
    sh "ssh -i ${SSH_KEY} -o StrictHostKeyChecking=no laborant@${TARGET_HOST} '...'"
    sh "scp -i ${SSH_KEY} -o StrictHostKeyChecking=no dist/app.tar.gz laborant@${TARGET_HOST}:~/"
}
```

The public part of the key is already on `target` and `docker`, so no passwords
are required.

### 4.2 The "binary"

The capstone brief calls it a binary. For Node.js that is the app bundle:

```bash
tar -czf dist/app.tar.gz index.js package.json node_modules
```

It is SCP'd to the target, extracted into `~/app`, and started with
`nohup node index.js &`. The PID is stashed in `~/app.pid` so the next run
can `pkill -f` it cleanly.

### 4.3 ttl.sh

`ttl.sh` is an anonymous, short-lived registry. Each image name is unique and
the TTL is encoded in the tag. The pipeline uses a **1-hour** tag:

```
ttl.sh/hs-cs411-capstone2:<build#>-<gitsha7>-1h
```

No `docker login` is required. On the docker host we `docker pull` and run
with `--restart unless-stopped` on port 4444.

### 4.4 Kubernetes (stretch)

The `k8s/deployment.yaml` contains placeholders that the pipeline replaces
before applying:

```bash
sed "s|REPLACE_IMAGE|${TTL_IMAGE}|g; s|REPLACE_TAG|${IMAGE_TAG}|g" \
    k8s/deployment.yaml > .k8s-rendered/deployment.yaml
kubectl --kubeconfig=$KUBECONFIG apply -f .k8s-rendered/
kubectl --kubeconfig=$KUBECONFIG rollout status deployment/hs-cs411-capstone2 --timeout=120s
```

After it rolls out:

```bash
curl http://<any-node-ip>:30444/
# or in-cluster
curl http://hs-cs411-capstone2.default.svc.cluster.local:4444/
```

> **Skip without the credential**: set the build parameter `SKIP_K8S=true`
> if `KUBECONFIG` isn't installed yet - the rest of the pipeline still runs.

---

## 5. Bonus: small multistage version

`Jenkinsfile.simple` keeps the same `withCredentials` + `nodejs` tool pattern
but drops the docker and k8s stages. It is meant for hosts that don't have
docker installed or when you just want fast feedback on the unit test + binary
deploy. Use it with **Pipeline from SCM** by selecting it as the Script Path
in the job config.

---

## 6. Scoring checklist

### Core - 60 pts
- [x] Node 24 interpreter (`tools { nodejs 'NodeJS-24' }`)
- [x] `Unit Test` stage runs `npm test` (passes locally)
- [x] `Build` stage produces a runnable Docker image
- [x] Container exposes the app on port 4444 (matches `index.js` + `Dockerfile EXPOSE 4444`)
- [x] Pipeline is end-to-end runnable on the lab Jenkins VM

### Stretch - 30 pts
- [x] `Deployment` + `Service` manifests in `k8s/`
- [x] Image pulled from ttl.sh (imagePullPolicy: Always)
- [x] Probes hit `GET /` so the pod reaches Ready
- [x] Reachable through the Service on `NodePort 30444`
- [x] `Deploy to Kubernetes` stage is wired up in the Jenkinsfile
