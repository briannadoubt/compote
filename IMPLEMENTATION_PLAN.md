# Compote Implementation Plan

This plan covers all currently outstanding work: planned features, warning cleanup, and release readiness. The sequence is chosen to deliver value incrementally while reducing integration risk.

## Guiding Goals

- Keep behavior predictable across CLI invocations.
- Build shared foundations once, then layer feature commands on top.
- Prefer small, testable slices over large multi-feature merges.

## Phase 0: Baseline Quality and Stability

### Scope

- Fix current project-source compiler warnings.
- Confirm clean local state and test pass before feature work.

### Target files

- `Sources/CompoteCore/Container/ContainerRuntime.swift`
- `Sources/CompoteCore/Container/KernelManager.swift`
- `Sources/CompoteCore/Orchestrator/HealthChecker.swift`
- `Sources/CompoteCore/Container/StreamingWriter.swift`
- `Sources/CompoteCore/Orchestrator/Orchestrator.swift`

### Acceptance criteria

- `swift test` passes.
- No warnings emitted from `Sources/CompoteCore/*` and `Sources/compote/*`.

## Phase 1: Runtime Foundation (Cross-Command Reliability)

### Scope

- Add state hydration at orchestrator startup so `ps`, `logs`, and `exec` can see previously created containers in later CLI invocations.
- Add a lightweight runtime metadata model for container records (service, replica index, image reference, createdAt, intended status).
- Introduce internal helpers for deterministic container naming and lookup.

### Key design decisions

- Keep state as source of truth for known containers; runtime-memory map remains per process.
- On hydration, do not assume every stored container is running; mark status conservatively.
- Preserve existing `<project>_<service>_1` naming for backward compatibility.

### Target files

- `Sources/CompoteCore/Orchestrator/StateManager.swift`
- `Sources/CompoteCore/Orchestrator/Orchestrator.swift`
- `Sources/compote/Commands/PsCommand.swift`
- `Sources/compote/Commands/LogsCommand.swift`
- `Sources/compote/Commands/ExecCommand.swift`

### Acceptance criteria

- `compote up -d` followed by fresh-shell `compote ps` shows expected services.
- `compote logs <service>` and `compote exec <service> ...` fail gracefully with actionable messages when service is known but not currently attachable.
- Existing commands remain backward-compatible.

## Phase 2: Networking Feature Work

### 2.1 Port Forwarding

#### Scope

- Implement service `ports` parsing and validation for short syntax first: `host:container[/proto]`.
- Apply host-to-container forwarding strategy:
  - Prefer native framework support if available.
  - Fallback to explicit host proxy process when needed.

#### Target files

- `Sources/CompoteCore/Models/Service.swift`
- `Sources/CompoteCore/Orchestrator/ServiceManager.swift`
- `Sources/CompoteCore/Container/ContainerRuntime.swift`

#### Acceptance criteria

- Exposed host port reaches container process reliably.
- Conflicts and malformed mappings return clear errors.

### 2.2 Inter-Container DNS Resolution

#### Scope

- Assign/store per-network addressing metadata.
- Inject host records for service names and aliases.
- Ensure multi-service projects resolve peers by service name.

#### Target files

- `Sources/CompoteCore/Network/NetworkManager.swift`
- `Sources/CompoteCore/Orchestrator/Orchestrator.swift`
- `Sources/CompoteCore/Orchestrator/ServiceManager.swift`

#### Acceptance criteria

- Service-to-service name resolution works within project network.
- Name collisions are detected and reported.

## Phase 3: Config and Secret Support

### Scope

- Extend service model with service-level `configs` and `secrets` references.
- Materialize config/secret sources from top-level definitions.
- Mount into containers read-only with compose-style default targets.

### Target files

- `Sources/CompoteCore/Models/Service.swift`
- `Sources/CompoteCore/Models/ComposeFile.swift`
- `Sources/CompoteCore/Orchestrator/ServiceManager.swift`

### Acceptance criteria

- Declared configs/secrets are available at expected in-container paths.
- Missing sources or external references fail with clear diagnostics.

## Phase 4: Image Lifecycle Commands

### 4.1 `pull` command

#### Scope

- Add `pull` CLI command for selected/all services.
- Wire existing `up --pull` flag to force pre-pull behavior.

#### Target files

- `Sources/compote/Commands/PullCommand.swift` (new)
- `Sources/compote/Commands/UpCommand.swift`
- `Sources/compote/CompoteCommand.swift`
- `Sources/CompoteCore/Image/ImageManager.swift`

#### Acceptance criteria

- `compote pull` pulls all image-backed services.
- `compote up --pull` triggers pull before create/start.

### 4.2 `push` command

#### Scope

- Add `push` command for custom/built images.
- Use Docker CLI-backed push path first (consistent with current build path), with future native OCI push extension.

#### Target files

- `Sources/compote/Commands/PushCommand.swift` (new)
- `Sources/compote/CompoteCommand.swift`
- `Sources/CompoteCore/Image/ImageManager.swift`

#### Acceptance criteria

- Push succeeds for tagged local images.
- Registry/auth failures include actionable error messages.

## Phase 5: Replica Management (`scale`)

### Scope

- Add `scale` command and replica-aware orchestrator operations.
- Refactor in-memory container registry from single service instance to replica collection.
- Maintain deterministic naming `<project>_<service>_<index>`.
- Update `ps`, `logs`, `exec` semantics for replicas.

### Target files

- `Sources/compote/Commands/ScaleCommand.swift` (new)
- `Sources/compote/CompoteCommand.swift`
- `Sources/CompoteCore/Orchestrator/Orchestrator.swift`
- `Sources/CompoteCore/Orchestrator/StateManager.swift`

### Acceptance criteria

- `compote scale web=3` and subsequent `web=1` converge correctly.
- Logs and status output clearly identify replica instances.

## Phase 6: Documentation and Release Readiness

### Scope

- Update README feature/status and command docs.
- Add or update changelog entries.
- Validate Homebrew formula install and setup flow.
- Check and complete release checklist documents.

### Target files

- `README.md`
- `RELEASE.md`
- `SETUP_CHECKLIST.md`
- `HOMEBREW_TAP.md`
- `Formula/compote.rb`

### Acceptance criteria

- Docs match shipped behavior.
- Release checklist is executable end-to-end without guesswork.

## Testing Strategy by Phase

- Unit tests for parser/model transformations.
- Orchestrator-level behavior tests for dependency order, lifecycle transitions, and state transitions.
- CLI smoke tests for command wiring and error messages.
- Formula/install smoke test using `scripts/test-formula.sh` where applicable.

## Milestone Delivery Sequence

1. Phase 0 + Phase 1 foundation
2. Phase 2 networking (ports then DNS)
3. Phase 3 configs/secrets
4. Phase 4 pull/push
5. Phase 5 scale
6. Phase 6 docs/release polish

This ordering minimizes rework by implementing shared runtime/state primitives before command-specific features.
