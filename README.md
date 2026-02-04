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
- Apple Silicon (ARM64) or Intel Mac
- Linux kernel (automatically installed with Homebrew)

## Installation

### Homebrew (Recommended)

The easiest way to install Compote with all dependencies:

```bash
# Add the tap
brew tap briannadoubt/compote

# Install (this also installs the required Linux kernel)
brew install compote

# Verify installation
compote setup
```

The Homebrew formula automatically installs:
- ✅ Compote binary
- ✅ Apple's Containerization framework
- ✅ Linux kernel for running containers
- ✅ All required dependencies

### Using Mint

```bash
mint install briannadoubt/compote

# Then install the kernel separately:
brew install containerization
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

# Install dependencies (includes Linux kernel)
brew install containerization

# Verify setup
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

# Execute command in container
compote exec web bash

# Validate config
compote config
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

1. **Check if containerization is installed**:
   ```bash
   brew list containerization
   ```

2. **Reinstall if needed**:
   ```bash
   brew reinstall containerization
   ```

3. **Verify kernel location**:
   ```bash
   ls -la /opt/homebrew/share/containerization/kernel/vmlinuz
   # or for Intel Macs:
   ls -la /usr/local/share/containerization/kernel/vmlinuz
   ```

4. **Run setup to diagnose**:
   ```bash
   compote setup --verbose
   ```

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

- ✅ Full container lifecycle (create, start, stop, delete)
- ✅ OCI image pulling from registries
- ✅ State persistence across sessions
- ✅ Named volumes and bind mounts
- ✅ Network management with vmnet (macOS 26+)
- ✅ Service orchestration with dependencies
- ✅ Health checks with retry logic
- ✅ Container exec (run commands in containers)
- ✅ Multi-service parallel startup
- ✅ Resource limits (CPU, memory)

### In Progress 🚧

- 🚧 Log streaming (placeholder implemented)
- 🚧 Port forwarding (requires additional configuration)

### Planned 📋

- [ ] Build from Dockerfile
- [ ] Network DNS resolution between containers
- [ ] Config and secrets support
- [ ] Scale command
- [ ] Pull command
- [ ] Push command for custom images

## License

MIT

## Contributing

Contributions welcome! Please open an issue or PR.
