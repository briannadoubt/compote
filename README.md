# Compote

A docker-compose like tool using Apple's containerization framework for macOS.

## Overview

Compote provides a familiar `docker-compose` interface while leveraging Apple's native containerization framework under the hood. It supports both `docker-compose.yml` and `compote.yml` configuration files with full compatibility for compose features.

## Features

- ✅ Full docker-compose.yml compatibility
- ✅ Service orchestration with dependency management
- ✅ Health checks with retry logic
- ✅ Named volumes and bind mounts
- ✅ Bridge networking
- ✅ Environment variable interpolation
- ✅ Multi-service parallel startup
- ✅ Image pulling and building
- ✅ Resource limits (CPU, memory)

## Requirements

- macOS 15.0+ (Sequoia or later)
- Xcode 16.0 or later
- Apple Silicon (ARM64) recommended (Intel Macs also supported)
- Linux kernel (automatically downloaded on first run)

## Installation

### Homebrew (Recommended)

The easiest way to install Compote:

```bash
# Add the tap
brew tap briannadoubt/tap

# Install compote
brew install compote

# Verify installation (downloads Linux kernel on first run)
compote setup
```

The Homebrew formula installs:
- ✅ Compote binary
- ✅ Shell completions
- ✅ Runtime TCP relay dependency (`socat`)

The Linux kernel and container runtime are automatically downloaded when you first run `compote setup` or `compote up`.

### Using Mint

```bash
mint install briannadoubt/compote

# Then verify setup (downloads kernel automatically)
compote setup
```

### From Source

```bash
# Clone the repository
git clone https://github.com/briannadoubt/compote.git
cd compote

# Build
swift build -c release

# Install binary
sudo cp .build/release/compote /usr/local/bin/

# Optional runtime dependency for service port forwarding
brew install socat

# Verify setup (downloads kernel automatically)
compote setup
```

### First Run

After installation, run the setup checker:

```bash
compote setup
```

This will verify that:
- ✅ Linux kernel is available
- ✅ Networking is supported (macOS 26+)
- ✅ Storage directories are configured

If the kernel is missing, the setup command will provide detailed instructions.

## Usage

### Basic Commands

```bash
# Check setup
compote setup

# Start services
compote up

# Start in detached mode
compote up -d

# Stop and remove containers
compote down

# Stop and remove volumes
compote down --volumes

# List running services
compote ps

# View logs
compote logs -f
compote logs --tail 100
compote logs web#2

# Execute command in container
compote exec web bash
compote exec web#2 sh

# Pull/push images
compote pull
compote push

# Validate config
compote config

# Scale services
compote scale web=3 worker=2
```

### Compose File

Create a `compote.yml` or `docker-compose.yml`:

```yaml
version: '3.8'

services:
  web:
    image: nginx:latest
    ports:
      - "8080:80"
    volumes:
      - ./html:/usr/share/nginx/html:ro
    depends_on:
      app:
        condition: service_healthy

  app:
    build: ./app
    environment:
      DATABASE_URL: postgresql://db:5432/myapp
    depends_on:
      - db
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost/health"]
      interval: 10s

  db:
    image: postgres:15
    volumes:
      - db-data:/var/lib/postgresql/data
    environment:
      POSTGRES_PASSWORD: secret

volumes:
  db-data:
```

## Troubleshooting

### Kernel Not Found

If you see "Linux kernel not found" errors:

1. **Run setup to download kernel**:
   ```bash
   compote setup
   ```

   This will automatically download the required Linux kernel to:
   `~/Library/Application Support/compote/kernel/`

2. **Check kernel location**:
   ```bash
   ls -la ~/Library/Application\ Support/compote/kernel/vmlinuz
   ```

3. **Manually download if needed**:
   Visit https://github.com/apple/containerization for kernel download instructions

### Networking Issues (macOS < 26)

Compote uses vmnet for networking, which requires macOS 26 (Sequoia) or later. On older versions:
- Containers will run without networking
- Use bind mounts for file access
- Consider upgrading to macOS 26+

### Permission Errors

If you encounter permission errors with volumes:
```bash
# Ensure proper ownership of volume directories
ls -la ~/Library/Application\ Support/compote/volumes/
```

## Architecture

### Components

- **CLI Layer**: ArgumentParser-based commands (up, down, ps, logs, etc.)
- **Core Library**: Models, parser, orchestrator, managers
- **Apple Integration**: Wrappers around Containerization, ContainerizationOCI, ContainerizationEXT4, ContainerizationNetlink

### Technology Stack

- Apple Containerization framework for Linux containers on macOS
- Virtualization.framework for lightweight VMs
- Swift 6.2 with strict concurrency
- Actor-based state management

## Development

### Building

```bash
swift build
```

### Running

```bash
swift run compote up
```

### Testing

```bash
swift test
```

## Status

### Implemented ✅

- ✅ Full container lifecycle (create, start, stop, restart, delete)
- ✅ OCI image pulling from registries
- ✅ Build from Dockerfile with build args
- ✅ State persistence across sessions
- ✅ Named volumes and bind mounts
- ✅ Network management with vmnet (macOS 26+)
- ✅ Service orchestration with dependencies
- ✅ Health checks with retry logic
- ✅ Container exec (run commands in containers)
- ✅ Log streaming with --follow and --timestamps
- ✅ Multi-service parallel startup
- ✅ Resource limits (CPU, memory)
- ✅ Environment variable interpolation
- ✅ Pull command (`compote pull`) and `up --pull`
- ✅ Push command for service images (`compote push`)
- ✅ Service-level config and secret file mounts
- ✅ Scale command (`compote scale service=replicas`)
- ✅ Service name discovery via generated `/etc/hosts` entries
- ✅ TCP port forwarding (`service.ports`) via host relay processes (`socat` required)

### Planned 📋

- UDP host port forwarding
- Replica-specific targeting for additional commands
- Expanded CLI integration coverage for multi-replica workflows

## License

MIT

## Contributing

Contributions welcome! Please open an issue or PR.
