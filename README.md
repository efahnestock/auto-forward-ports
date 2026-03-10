# auto-forward-ports

Monitor a remote host for listening ports and automatically set up SSH local port forwards.

Useful when working with remote dev servers that spin up services on dynamic ports (dev servers, notebooks, TensorBoard, etc.) — ports are detected and forwarded automatically so you can access them on `localhost`.

## Install

**With curl:**

```bash
curl -fsSL https://raw.githubusercontent.com/efahnestock/auto-forward-ports/main/install.sh | bash
```

**With git:**

```bash
git clone https://github.com/efahnestock/auto-forward-ports.git
cd auto-forward-ports
./install.sh
```

The installer detects your shell and installs the matching version (zsh or bash) to `~/.local/bin/`.

## Usage

```
auto-forward-ports <host> [poll_interval]
```

- `host` — SSH host to monitor (e.g. `aspen`, `pika`, or any host in your `~/.ssh/config`)
- `poll_interval` — seconds between checks (default: `5`)

### Example

```bash
auto-forward-ports myserver 10
```

The TUI shows:
- All currently forwarded ports with process descriptions
- Live status indicators (green = active, yellow = reconnecting)
- Recent event log (ports added/removed)

Press `Ctrl-C` to stop all forwards and exit.

## How it works

1. Polls the remote host via SSH, running `ss -tlnp` to discover listening ports
2. For each new port (>= 1024), starts an SSH local port forward (`ssh -N -L`)
3. Removes forwards when the remote port goes away
4. Reconnects if a tunnel dies

## Requirements

- **zsh** version: any modern zsh
- **bash** version: bash 4.0+ (for associative arrays; macOS ships bash 3.x — install a newer one with `brew install bash`)
- SSH access to the remote host
- `ss` available on the remote host

## License

MIT
