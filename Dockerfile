FROM node:22-bookworm-slim AS build
WORKDIR /app
COPY package.json package-lock.json ./
# npm ci is strict about nested lock entries; fall back so a VPS rebuild
# still works if the lockfile and npm disagree.
RUN npm ci --no-audit --no-fund || npm install --no-audit --no-fund
COPY . .
ARG PARROT_VERSION=dev
ENV PARROT_VERSION=$PARROT_VERSION
ENV NITRO_PRESET=node-server
RUN npm run build:vps && test -f .output/server/index.mjs

FROM node:22-bookworm-slim
WORKDIR /app
ARG PARROT_VERSION=dev
ENV PARROT_VERSION=$PARROT_VERSION
RUN apt-get update \
  && apt-get install -y --no-install-recommends ca-certificates curl \
  && rm -rf /var/lib/apt/lists/*
COPY --from=build /app/.output ./.output
ENV NODE_ENV=production
ENV HOST=0.0.0.0
ENV PORT=3000
EXPOSE 3000
HEALTHCHECK --interval=30s --timeout=5s --start-period=25s --retries=3 \
  CMD node -e "fetch('http://127.0.0.1:3000/').then((r)=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"
LABEL org.opencontainers.image.title="Parrot Clicker" \
  org.opencontainers.image.description="Tap a macaw. Raise a flock. Sit beside the Caddy you already run."
CMD ["node", ".output/server/index.mjs"]
