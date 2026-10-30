# Anonymous India Backend - Optimized for cross-platform builds
# Builds on Mac Silicon (ARM64) → Runs on Ubuntu EC2 (AMD64)
# =============================================================================

# -----------------------------------------------------------------------------
# STAGE 1: Dependencies
# Install dependencies and generate Prisma client
# -----------------------------------------------------------------------------
FROM node:20-alpine AS deps
WORKDIR /app

# Install build dependencies with cache mount
RUN --mount=type=cache,target=/var/cache/apk \
    --mount=type=cache,target=/etc/apk/cache \
    apk add --no-cache libc6-compat openssl openssl-dev python3 make g++

# Copy package files first (better layer caching)
COPY package*.json ./
COPY prisma ./prisma/

# Install dependencies with npm cache mount and generate Prisma with all targets
RUN --mount=type=cache,target=/root/.npm \
    npm ci --prefer-offline --no-audit && \
    npx prisma generate --generator=client

# -----------------------------------------------------------------------------
# STAGE 2: Builder
# Compile TypeScript and prepare production bundle
# -----------------------------------------------------------------------------
FROM node:20-alpine AS builder
WORKDIR /app

# Install build tools needed for native modules
RUN apk add --no-cache python3 make g++

# Copy dependencies from deps stage
COPY --from=deps /app/node_modules ./node_modules
COPY --from=deps /app/prisma ./prisma
COPY --from=deps /app/package*.json ./

# Copy source code
COPY . .

# Rebuild bcrypt for target architecture and build application
RUN npm rebuild bcrypt --build-from-source && \
    npm run build && \
    npm prune --production && \
    rm -rf src test coverage .git

# -----------------------------------------------------------------------------
# STAGE 3: Production Runner
# Minimal production image with security hardening
# -----------------------------------------------------------------------------
FROM node:20-alpine AS runner
WORKDIR /app

# Security: Create non-root user
RUN addgroup --system --gid 1001 nodejs && \
    adduser --system --uid 1001 nestjs

# Install runtime dependencies only (including OpenSSL for Prisma)
RUN --mount=type=cache,target=/var/cache/apk \
    apk add --no-cache curl dumb-init ca-certificates openssl

# Copy production files
COPY --from=builder --chown=nestjs:nodejs /app/dist ./dist
COPY --from=builder --chown=nestjs:nodejs /app/node_modules ./node_modules
COPY --from=builder --chown=nestjs:nodejs /app/prisma ./prisma
COPY --from=builder --chown=nestjs:nodejs /app/package.json ./
COPY --chown=nestjs:nodejs docker-entrypoint.sh ./
RUN chmod +x docker-entrypoint.sh

# Set environment
ENV NODE_ENV=production \
    PORT=3001 \
    USER=nestjs

# Security: Use non-root user
USER nestjs

# Expose port
EXPOSE 3001

# Health check with retry logic
HEALTHCHECK --interval=15s --timeout=5s --start-period=40s --retries=3 \
    CMD curl -fs http://localhost:3001/api/health || exit 1

# Use dumb-init for proper signal handling
ENTRYPOINT ["dumb-init", "--"]

# Start application
CMD ["node", "dist/main"]

# -----------------------------------------------------------------------------
# Labels for image metadata
# -----------------------------------------------------------------------------
LABEL org.opencontainers.image.title="Anonymous India Backend" \
      org.opencontainers.image.description="Production NestJS API" \
      org.opencontainers.image.version="1.0.0" \
      org.opencontainers.image.vendor="Anonymous India"
