ARG NODE_IMAGE_REPO="node"
ARG NODE_IMAGE_VERSION="22-alpine"

# Install dependencies only when needed
FROM ${NODE_IMAGE_REPO}:${NODE_IMAGE_VERSION} AS deps
# 可通过 build-arg 覆盖，用于加速 npm/pnpm 下载（例如 https://registry.npmmirror.com 或公司内网 Nexus）
ARG NPM_REGISTRY="https://registry.npmjs.org"
ARG PNPM_FETCH_TIMEOUT="600000"
ARG PNPM_FETCH_RETRIES="5"
ARG PNPM_NETWORK_CONCURRENCY="8"
ENV NPM_CONFIG_REGISTRY=$NPM_REGISTRY
ENV PNPM_CONFIG_REGISTRY=$NPM_REGISTRY
# Check https://github.com/nodejs/docker-node/tree/b4117f9333da4138b03a546ec926ef50a31506c3#nodealpine to understand why libc6-compat might be needed.
RUN apk add --no-cache libc6-compat
WORKDIR /app
COPY package.json pnpm-lock.yaml ./
RUN npm install -g pnpm
RUN npm config set registry $NPM_REGISTRY
RUN pnpm config set registry $NPM_REGISTRY \
  && pnpm config set fetch-timeout $PNPM_FETCH_TIMEOUT \
  && pnpm config set fetch-retries $PNPM_FETCH_RETRIES \
  && pnpm config set network-concurrency $PNPM_NETWORK_CONCURRENCY
RUN pnpm install --frozen-lockfile

# Rebuild the source code only when needed
FROM ${NODE_IMAGE_REPO}:${NODE_IMAGE_VERSION} AS builder
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY . .
COPY docker/middleware.ts ./src

ARG BASE_PATH
ARG NPM_REGISTRY="https://registry.npmjs.org"
ARG PRISMA_ENGINES_MIRROR="https://registry.npmmirror.com/-/binary/prisma"

ENV NPM_CONFIG_REGISTRY=$NPM_REGISTRY
ENV PNPM_CONFIG_REGISTRY=$NPM_REGISTRY
ENV PRISMA_ENGINES_MIRROR=$PRISMA_ENGINES_MIRROR

ENV BASE_PATH=$BASE_PATH
ENV NEXT_TELEMETRY_DISABLED=1
ENV DATABASE_URL="postgresql://user:pass@localhost:5432/dummy"

RUN npm run build-docker

# Production image, copy all the files and run next
FROM ${NODE_IMAGE_REPO}:${NODE_IMAGE_VERSION} AS runner
WORKDIR /app

ARG PRISMA_VERSION="6.19.0"
ARG NODE_OPTIONS
ARG NPM_REGISTRY="https://registry.npmjs.org"
ARG PRISMA_ENGINES_MIRROR="https://registry.npmmirror.com/-/binary/prisma"
ARG PNPM_FETCH_TIMEOUT="600000"
ARG PNPM_FETCH_RETRIES="5"
ARG PNPM_NETWORK_CONCURRENCY="8"

ENV NODE_ENV=production
ENV NEXT_TELEMETRY_DISABLED=1
ENV NODE_OPTIONS=$NODE_OPTIONS
ENV NPM_CONFIG_REGISTRY=$NPM_REGISTRY
ENV PNPM_CONFIG_REGISTRY=$NPM_REGISTRY
ENV PRISMA_ENGINES_MIRROR=$PRISMA_ENGINES_MIRROR

RUN addgroup --system --gid 1001 nodejs
RUN adduser --system --uid 1001 nextjs
RUN set -x \
    && apk add --no-cache curl \
    && npm install -g pnpm
RUN npm config set registry $NPM_REGISTRY
RUN pnpm config set registry $NPM_REGISTRY \
  && pnpm config set fetch-timeout $PNPM_FETCH_TIMEOUT \
  && pnpm config set fetch-retries $PNPM_FETCH_RETRIES \
  && pnpm config set network-concurrency $PNPM_NETWORK_CONCURRENCY

# Script dependencies
RUN pnpm --allow-build='@prisma/engines' add npm-run-all dotenv chalk semver \
    prisma@${PRISMA_VERSION} \
    @prisma/adapter-pg@${PRISMA_VERSION}

COPY --from=builder --chown=nextjs:nodejs /app/public ./public
COPY --from=builder /app/prisma ./prisma
COPY --from=builder /app/scripts ./scripts
COPY --from=builder /app/generated ./generated

# Automatically leverage output traces to reduce image size
# https://nextjs.org/docs/advanced-features/output-file-tracing
COPY --from=builder --chown=nextjs:nodejs /app/.next/standalone ./
COPY --from=builder --chown=nextjs:nodejs /app/.next/static ./.next/static

USER nextjs

EXPOSE 3000

ENV HOSTNAME=0.0.0.0
ENV PORT=3000

CMD ["pnpm", "start-docker"]
