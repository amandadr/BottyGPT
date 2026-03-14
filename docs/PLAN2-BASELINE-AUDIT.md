# Plan 2.0 baseline audit

This baseline captures the issues observed before the Plan 2.0 refactor.

## Docker/image baseline

- Previous backend image build used Ubuntu + PPA setup in both build/runtime stages.
- Build baked model archives directly into the image (`mpnet-base-v2.zip`), increasing size and layer churn.
- Rust toolchain install was included in Docker build path, adding additional bloat risk.
- Runtime image carried package-install complexity that was not essential for serving API requests.

## Deployment baseline

- Production-like Compose stacks had broad dependency fan-out (`backend`, `worker`, `redis`, `mongo`, `qdrant`, `frontend`) without readiness checks.
- Some deployment variants relied on host bind paths that can drift across machines.
- Health semantics were weak: no backend readiness endpoint and no container-level health checks for service orchestration.
- Log rotation limits were not consistently configured, risking disk pressure on long-lived VMs.

## Testing and CI/CD baseline

- Existing test docs described connectivity checks as optional and explicitly non-mandatory in CI.
- CI had test coverage and linting, but no mandatory Compose-level connectivity smoke test gate.
- No image-size guardrail to prevent oversized backend artifacts from reaching deployment.

## Primary failure signatures observed

- Disk pressure and cleanup loops on VM during iterative rebuilds.
- Runtime startup failures hidden until manual post-deploy checks.
- Dependency/connectivity errors surfacing late (after UI validation started) rather than failing fast in CI.

## Baseline-to-target mapping

- Move to slim multi-stage backend image with runtime-only dependencies.
- Enforce CI preflight gates for dependency integrity, image size, and Compose connectivity.
- Add liveness/readiness endpoints and reusable healthcheck commands.
- Harden Compose with restart policies, health checks, and log rotation.
