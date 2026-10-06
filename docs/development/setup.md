# Development setup

## Prerequisites

- Flutter SDK
- Dart SDK
- Rust toolchain (for secure core or native crypto layer)
- PostgreSQL
- Redis
- Docker Compose (optional for local services)
- Git

## Recommended local environment

Use Docker Compose for local infrastructure where practical, including:

- PostgreSQL
- Redis
- a local relay test harness

## Initial setup

```bash
# from repo root
flutter --version
rustc --version
psql --version
redis-server --version
```

## Repository conventions

- keep cryptography outside UI code
- use protocols and specs as the source of truth
- keep tests with the module they validate
- treat security tests as mandatory checks

## Local development flow

1. create and verify identity keys locally
2. run the secure protocol tests
3. run backend relay tests
4. run integration tests for A -> relay -> B
5. run the mobile client against a local mock relay or test backend

## Required checks before merging

- lint
- formatting
- unit tests
- security test suite
- integration tests
- no secret files committed

## Security reminder

Never commit private keys, real credentials, or production secrets. All secret-bearing files must be kept out of version control.
