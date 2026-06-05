# Single-stage Dockerfile (matches the capstone hint)
# Build with deps already installed in the workspace (npm ci has been run).
FROM node:24-alpine
WORKDIR /usr/app
COPY index.js index.js
COPY package.json package.json
COPY node_modules node_modules
EXPOSE 4444
CMD ["node", "index.js"]
