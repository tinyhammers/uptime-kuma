# Stage 1: compile production dependencies (native modules need build tools)
FROM node:24-bookworm-slim AS prod-deps

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    python3 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY package.json package-lock.json .npmrc ./
RUN npm ci --omit=dev --no-audit

# Stage 2: build frontend assets (needs devDependencies + build tools)
FROM node:24-bookworm-slim AS build

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    python3 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY package.json package-lock.json .npmrc ./
RUN npm ci --no-audit

COPY . .
RUN npm run build

# Stage 3: runtime image (no build tools)
FROM node:24-bookworm-slim AS release

ENV UPTIME_KUMA_IS_CONTAINER=1

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    dumb-init \
    iputils-ping \
    nscd \
    sqlite3 \
    sudo \
    && rm -rf /var/lib/apt/lists/*

COPY docker/etc/nscd.conf /etc/nscd.conf
COPY docker/etc/sudoers /etc/sudoers

WORKDIR /app

# Copy pre-compiled node_modules from prod-deps stage (no build tools needed at runtime)
COPY --from=prod-deps /app/node_modules ./node_modules
COPY package.json .npmrc ./

COPY --from=build /app/dist ./dist
COPY server ./server
COPY src ./src
COPY db ./db
COPY extra ./extra
COPY public ./public

RUN mkdir -p /app/data && chown -R node:node /app

USER node

EXPOSE 3001

VOLUME ["/app/data"]

HEALTHCHECK --interval=60s --timeout=30s --start-period=180s --retries=5 \
    CMD curl -f http://localhost:3001/api/entry-page || exit 1

ENTRYPOINT ["dumb-init", "--"]
CMD ["node", "server/server.js"]
