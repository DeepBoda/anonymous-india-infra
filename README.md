# Anonymous India: infrastructure

How my own product, Anonymous India, is built, shipped and run in production. It is an anonymous social app for India with a Flutter app, a NestJS API, a Next.js site and an admin console. I run all of it alone.

The application code stays private because the product is live. This repo has everything that takes the code to a running server.

![Architecture](docs/architecture.webp)

## The stack

- **API:** NestJS on the Fastify adapter, Prisma over PostgreSQL 16, Redis 7 for sessions, throttling and the Socket.io adapter
- **Server:** one Ubuntu EC2 instance running Docker Compose, Nginx in front, Let's Encrypt certificates through certbot
- **Images:** built on a Mac (ARM) for the server (AMD64) with `docker buildx`, pushed to Amazon ECR

## What is in here

| File | What it does |
|---|---|
| `Dockerfile` | Three-stage build: dependencies, compile, then a small runtime image |
| `docker-compose.prod.yml` | Postgres, Redis, the API and Nginx, with health checks and resource limits |
| `nginx/anonymous-backend.conf` | Rate limits, WebSocket routing, security headers, gzip |
| `scripts/build-push-image.sh` | Builds the AMD64 image and pushes it to ECR |
| `scripts/deploy-ec2.sh` | Installs Docker if needed, logs in to ECR, pulls the image and restarts the stack |
| `scripts/setup-server.sh` | First-time server setup: packages, swap, Nginx, certbot |
| `scripts/setup-nginx.sh` | Installs the Nginx site and requests the certificate |
| `.env.example` | Every variable the stack reads, with no real values |

## Decisions worth explaining

**The runtime image only has what runs.** The build stage compiles TypeScript and generates the Prisma client, then `npm prune --production` drops dev dependencies. The final stage copies only `dist`, production `node_modules` and the Prisma schema.

**It runs as a non-root user with a real init.** The API runs as user `nestjs` (uid 1001). `dumb-init` is PID 1, so `SIGTERM` reaches Node and a deploy closes connections cleanly instead of killing them.

**Built on ARM, runs on AMD64.** I develop on Apple Silicon and the server is x86. `bcrypt` is a native module, so the build rebuilds it from source for the target platform. Without that the container starts and then crashes on the first login.

**The API only starts when its data is ready.** Compose waits for the Postgres and Redis health checks before it starts the API. The image has its own health check on `/api/health`.

**The databases are not reachable from the internet.** Postgres and Redis bind to `127.0.0.1` only. Redis needs a password anyway.

**Login is rate limited harder than everything else.** Nginx allows 30 requests a second per IP for the API and 5 a second for auth routes. The API applies its own per-user limits on top.

**WebSockets get their own route.** Socket.io traffic has its own Nginx location with the Upgrade headers and a 24 hour read timeout. Without it the handshake falls through to the normal API route, gets a 60 second timeout and fails silently.

**API logs cannot fill the disk.** The API container rotates its JSON logs at 100 MB, keeping 5 files.

**A small server survives memory spikes.** First-time setup adds a 1 GB swap file with low swappiness, so a burst does not get the API killed by the kernel.

## What I would change at more traffic

- Move Postgres to Amazon RDS with automated backups and point-in-time restore.
- Run the API as more than one container behind a load balancer. Realtime already works across containers because Socket.io uses the Redis adapter.
- Deploy without the short gap the current `down` then `up` leaves, by starting the new container before stopping the old one.
- Deploy from a pipeline with an immutable image tag instead of `latest`, so a rollback is one tag change.

## Author

**Deep Boda**, Senior DevOps Engineer. [deepboda.in](https://deepboda.in) · [Case study](https://deepboda.in/work/anonymous-india) · deepboda18@gmail.com
