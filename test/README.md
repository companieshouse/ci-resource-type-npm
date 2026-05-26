# Test Guide

This folder contains cucumber-js integration tests for the npm resource.

## Quick Start

From repository root:

```bash
docker build . -t ci-resource-type-npm:latest
cd test
docker compose -f docker-compose.registry.yml up -d registry
```

Then run one of the auth-mode examples below.

When done:

```bash
docker compose -f docker-compose.registry.yml down -v
```

## Environment Variables

Required in all runs:

- `DOCKER_IMAGE` (usually `ci-resource-type-npm:latest`)
- `TEST_REGISTRY` (host-side URL, usually `http://127.0.0.1:4873/`)
- `TEST_REGISTRY_INTERNAL` (container-side URL, usually `http://host.docker.internal:4873/`)

Auth mode variables:

- `TEST_AUTH_MODE=token`
- No credential env vars required (tests obtain a token via user setup automatically)
- Optional override: `CORRECT_CREDENTIALS`, `INCORRECT_CREDENTIALS`

or

- `TEST_AUTH_MODE=userpass`
- `CORRECT_USERNAME`
- `CORRECT_PASSWORD`
- `CORRECT_EMAIL` (optional, defaults to `test@example.com`)

Set `NORMRF=true` if you want to keep temp directories after test runs.

## Run Examples

### Token Mode

```bash
DOCKER_IMAGE=ci-resource-type-npm:latest \
TEST_AUTH_MODE=token \
TEST_REGISTRY=http://127.0.0.1:4873/ \
TEST_REGISTRY_INTERNAL=http://host.docker.internal:4873/ \
npm test
```

### User/Password Mode

```bash
DOCKER_IMAGE=ci-resource-type-npm:latest \
TEST_AUTH_MODE=userpass \
TEST_REGISTRY=http://127.0.0.1:4873/ \
TEST_REGISTRY_INTERNAL=http://host.docker.internal:4873/ \
CORRECT_USERNAME=test \
CORRECT_PASSWORD=test \
CORRECT_EMAIL=test@example.com \
npm test
```

## Local Registry Notes

- The test runner executes on the host.
- Resource scripts execute in containers.
- Because of this, host and container may need different registry hostnames.
- `TEST_REGISTRY_INTERNAL` exists for that network-context split.
