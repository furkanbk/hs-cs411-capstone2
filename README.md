# hs-cs411-capstone2

Express sample app (port 4444) built and deployed by a simple **Jenkins**
pipeline to two places:

1. **target** — runs as a `systemd` service (`index.js` + `node_modules`)
2. **docker** — image pushed to `ttl.sh`, then pulled and run on the docker host

```
GET /  ->  { "name": "Hello", "description": "World", "url": <host> }
```

> The Kubernetes deployment is the optional stretch and is **not** wired into
> the pipeline. The `k8s/` manifests are left in the repo if you want to apply
> them by hand later.

---

## Files

| File | Purpose |
| --- | --- |
| `index.js` / `index.test.js` | App + unit test (given) |
| `package.json` | `npm install` deps, `node --test` runs the test |
| `Dockerfile` | `node:24-alpine`, matches the hint |
| `Jenkinsfile` | The pipeline (4 stages) |
| `myapp.service` | systemd unit deployed to the target host |
| `k8s/*` | Optional stretch manifests (not used by the pipeline) |

---

## 1. Jenkins setup (one time)

Sign in at the Jenkins tab with **admin / admin**.

**Credential** (Manage Jenkins → Credentials → System → Global → Add):

| ID | Kind | Notes |
| --- | --- | --- |
| `LAB_SSH_KEY` | SSH Username with private key | username `laborant`; the public half is already on `target` and `docker` |

**Plugins:** only the bundled `Pipeline` + `Credentials Binding`, plus
`SSH Credentials` (for the private-key binding).

**Agent tooling:** the Jenkins node needs `node`, `npm` and `docker` on `PATH`.
Install Node 24 with:

```bash
curl -fsSL https://deb.nodesource.com/setup_24.x -o nodesource_setup.sh
sudo -E bash nodesource_setup.sh
sudo apt-get install -y nodejs
```

**Target host:** the `laborant` user must have passwordless `sudo` (used to
install the systemd unit). The lab image already provides this.

---

## 2. Create and run the job

1. New Item → **Pipeline** → name it `myapp`.
2. Pipeline → Definition: **Pipeline script from SCM**.
3. SCM: Git → this repo URL → branch `main` → Script Path `Jenkinsfile`.
4. Save → **Build Now**.

### What each stage does

| Stage | Action |
| --- | --- |
| Unit Test | `npm install` then `node --test` |
| Deploy to target | tar `index.js` + `node_modules`, scp to `laborant@target`, install `myapp.service`, `systemctl restart`, curl check |
| Build & Push Docker | `docker build` then `docker push ttl.sh/myapp-<build>:1h` |
| Deploy to docker | ssh `laborant@docker`, `docker run -p 4444:4444`, curl check |

The image name (`ttl.sh/myapp-${BUILD_NUMBER}:1h`) is set once in the
`environment {}` block and reused by the docker stage.

---

## 3. Verify the deployment

### Target (systemd service)

```bash
ssh laborant@target 'systemctl status myapp --no-pager'
ssh laborant@target 'curl -fsS http://localhost:4444/'
# expected: {"name":"Hello","description":"World","url":"localhost:4444"}
```

### Docker host

```bash
ssh laborant@docker 'docker ps --filter name=myapp'
ssh laborant@docker 'curl -fsS http://localhost:4444/'
```

Both stages already run a `curl` health check inside the pipeline, so a green
build is itself proof the endpoint answered on each host.

---

## 4. Run locally (sanity check)

```bash
npm install
node --test                 # unit test -> 1 pass
node index.js               # http://localhost:4444/
docker build -t myapp .
docker run --rm -p 4444:4444 myapp
curl -fsS http://localhost:4444/
```
