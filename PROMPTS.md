# PROMPTS.md — Agent-session documentation

How this Jenkins pipeline was built with an AI coding agent: the prompts that
worked, where it got stuck, how I verified it, and how much carried over from
the earlier **Go** pipeline assignment.

---

## 1. The transfer story (Go → Node.js)

The previous capstone built the same kind of Jenkins pipeline for a **Go**
service. I did **not** reuse the Go prompts verbatim — I **re-derived** them for
Node.js, because the artifact model is fundamentally different:

| Concern | Go pipeline (capstone 1) | Node.js pipeline (this one) |
| --- | --- | --- |
| Test command | `go test ./...` | `node --test` |
| Build artifact | one static compiled binary | no binary — ship `index.js` + `node_modules` |
| "Deploy the binary" | `scp ./app laborant@target` | `tar czf app.tgz index.js node_modules` then scp |
| systemd `ExecStart` | `/home/laborant/app/app` | `/usr/bin/node /home/laborant/app/index.js` |
| Runtime on target | nothing (static binary) | Node 24 interpreter must be installed |
| Dockerfile base | `scratch` / `distroless` | `node:24-alpine`, `COPY node_modules` |

**What transferred (the skeleton):** the *shape* of the pipeline was reused as a
mental template — `Unit Test → deploy to target → build & push image to ttl.sh →
deploy to docker host`, the `withCredentials([sshUserPrivateKey(...)])` SSH
pattern, and the ttl.sh ephemeral-registry trick.

**What had to be re-derived (the specifics):** everything about *how Node ships*.
The single biggest re-derivation: a Go deploy is "copy one file"; a Node deploy
is "copy the app **and** its `node_modules` **and** make sure an interpreter
exists on the box." That changed the target stage, the systemd unit, and the
Dockerfile.

So: **reused the architecture prompt, rewrote every implementation prompt.**

---

## 2. A specific prompt that worked

Early on I gave the agent the full acceptance criteria in one shot and let it
scaffold:

> "Create a build and deployment pipeline in Jenkins for a NodeJS app. It uses
> NodeJS 24, the given `index.js` and `index.test.js`, executes a unit-test
> stage, and deploys to **target** and **docker**. The repo is pulled by a
> sandboxed Jenkins VM which `scp`s the app to `laborant@target` and runs it,
> and pushes the Docker image to `ttl.sh` then `ssh`es into `laborant@docker`
> to pull and run it. Make the Jenkinsfile use `withCredentials` with the SSH
> private key stored as `LAB_SSH_KEY`."

This produced a working first draft because it specified **the hosts, the
credential ID, the registry, and the exact transport (scp/ssh)** — not just
"deploy it." Naming `LAB_SSH_KEY` up front meant the `withCredentials` block was
correct on the first try.

A later, sharper prompt that paid off:

> "Simplify the Jenkinsfile, remove the weird plugin requirements."

That one cut the over-engineered first draft (NodeJS tool plugin, `ansiColor`,
`timestamps`, `buildDiscarder`, `junit`, `cleanWs`) down to the four stages that
actually satisfy the rubric.

---

## 3. A friction moment

**Shell quoting inside `sh '''…'''` Groovy blocks broke the SSH remote
commands.** The first draft wrapped remote commands in single quotes:

```groovy
sh '''
    ssh ... laborant@target 'pkill -f "node index.js"; sleep 1'
'''
```

Reviewing it, the nested single quotes were ambiguous/fragile, and the
multi-line remote scripts mixed `$!` and `$(...)` that I needed the **remote**
shell to expand, not the local one. The fix was a consistent rule:

- outer **double** quotes around the remote command,
- inner **single** quotes for literal args,
- escape `\$!` and `\$(...)` so they reach the remote shell intact.

```groovy
ssh ... "laborant@target" "pkill -f 'node index.js'; sleep 1"
```

A second, sneakier friction moment: the generated `.dockerignore` listed
`node_modules`, but the Dockerfile does `COPY node_modules node_modules`. The
ignore rule would have **silently broken the image build**. Caught it on review
and removed that line.

---

## 4. A verification step

I did not trust "it looks right" — every change was checked:

1. **Unit test, exactly as the pipeline runs it:**
   ```bash
   node --test
   # => # tests 1 / # pass 1 / # fail 0
   ```

2. **Runtime smoke test** — start the app and hit the endpoint:
   ```bash
   node index.js & sleep 2
   curl -fsS http://127.0.0.1:4444/
   # => {"name":"Hello","description":"World","url":"127.0.0.1:4444"}
   ```

3. **Jenkinsfile structural check** — a script that strips strings/comments and
   counts braces/parens to catch Groovy syntax breakage after the quoting edits:
   ```
   Jenkinsfile: braces {=…, }=… (balanced), (=…, )=… (balanced)
   ```

4. **In-pipeline health checks** — each deploy stage ends with
   `curl -fsS http://localhost:4444/` on the target / docker host, so a green
   build is itself evidence the endpoint answered after deployment.

---

## 5. What I'd tell the next person

- Give the agent **the host names, the credential ID, and the transport** in the
  first prompt — vague "deploy it" prompts produced vague pipelines.
- Ask it to **simplify** as an explicit second pass; the first draft over-reached
  on plugins.
- **Read the generated shell quoting and `.dockerignore` yourself** — those were
  the two places the agent's output was subtly wrong.
- Don't assume Go habits transfer: with Node you ship `node_modules` and need an
  interpreter on the box.
