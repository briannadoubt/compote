# Changelog

All notable changes to this project will be documented in this file.

The format is based on Keep a Changelog and this project follows Semantic Versioning.

## [Unreleased]

### Added
- `compote pull` command and `up --pull` image pre-pull support.
- `compote push` command for pushing service images.
- `compote scale service=replicas` command with replica-aware orchestration.
- Service-level config and secret reference parsing and read-only mounts.
- Service discovery host entries for in-network name resolution.
- TCP host port forwarding for `ports` via managed `socat` relays.
- Replica selector support for `logs` and `exec` (`service#replica`).
- Replica selector support for lifecycle commands (`start`, `stop`, `restart`).

### Changed
- `ps` now reports replica-aware status counts (for example `Up (3)`).
- Orchestrator now hydrates persisted state for cross-invocation command reliability.
- `logs` now honors `--follow` and `--tail`.
- Homebrew formula now declares `socat` as a dependency for port forwarding.

### Tests
- Added parser coverage for service config/secret references.
- Added `LogBuffer` coverage for `tail` and non-follow streaming behavior.
