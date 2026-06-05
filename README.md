# hs-cs411-capstone2

Express sample app (port 4444) built and deployed by a simple **Jenkins**
pipeline to three places:

1. **target** — runs as a `systemd` service (`index.js` + `node_modules`)
2. **docker** — image pushed to `ttl.sh`, then pulled and run on the docker host
3. **kubernetes** — `Deployment` + `Service` applied to `https://kubernetes:6443`

```
GET /  ->  { "name": "Hello", "description": "World", "url": <host> }
```

---

## Files

| File | Purpose |
| --- | --- |
| `index.js` / `index.test.js` | App + unit test (given) |
| `package.json` | `npm install` deps, `node --test` runs the test |
| `Dockerfile` | `node:24-alpine`, matches the hint |
| `Jenkinsfile` | The pipeline (5 stages) |
| `myapp.service` | systemd unit deployed to the target host |
| `k8s/deployment.yaml` | Deployment, image filled in by the pipeline |
| `k8s/service.yaml` | NodePort 30444 -> 4444 |

---

## Jenkins setup (minimal)

Sign in at the Jenkins tab with **admin / admin**.

**Credentials** (Manage Jenkins -> Credentials -> System -> Global):

| ID | Kind | Notes |
| --- | --- | --- |
| `LAB_SSH_KEY` | SSH Username with private key | username `laborant`; public half already on `target` and `docker` |
| `KUBECONFIG` | Secret file | kubeconfig pointing at `https://kubernetes:6443` (k8s stage only) |

**Plugins:** just the bundled `Pipeline` + `Credentials Binding`, plus
`SSH Credentials` (for the private-key binding). No NodeJS/AnsiColor/etc.

**Node on the Jenkins agent:** the test stage runs `node --test`, so the agent
needs `node`, `npm`, `docker` and `kubectl` on `PATH`. Install Node 24 with:

```bash
curl -fsSL https://deb.nodesource.com/setup_24.x -o nodesource_setup.sh
sudo -E bash nodesource_setup.sh
sudo apt-get install -y nodejs
```

Create a **Pipeline** job -> *Pipeline script from SCM* -> point it at this repo,
Script Path `Jenkinsfile`.

---

## Pipeline stages

| Stage | What it does |
| --- | --- |
| Unit Test | `npm install` then `node --test` |
| Deploy to target | tar `index.js` + `node_modules`, scp to `laborant@target`, install `myapp.service`, `systemctl restart`, curl health check |
| Build & Push Docker | `docker build` then `docker push ttl.sh/myapp-<build>:1h` |
| Deploy to docker | ssh `laborant@docker`, `docker run -p 4444:4444`, curl health check |
| Deploy to kubernetes | `sed` the image into `k8s/deployment.yaml`, `kubectl apply`, wait for rollout |

The image name (`ttl.sh/myapp-${BUILD_NUMBER}:1h`) is set once in the
`environment {}` block and reused by the docker and kubernetes stages.

---

## Run it locally

```bash
npm install
node --test                 # unit test
node index.js               # http://localhost:4444/
docker build -t myapp .
docker run --rm -p 4444:4444 myapp
```

After a Kubernetes deploy, reach the app on any node:

```bash
curl http://<node-ip>:30444/
```
