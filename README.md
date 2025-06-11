# Aztec Node Setup Script

This script automates the installation, configuration, and management of an Aztec node on Ubuntu systems using `systemd`. It supports dynamic IP detection, port forwarding, L1 RPC health checks, and node service management via a simple menu.

## Features:
- Full installation with all required dependencies
- Automatically configures Aztec node as a systemd service
- Auto-detects public IP address for config setup
- Kills any process occupying essential ports
- Health checker for L1 RPC (verifies block production & response time)
- Socat-based port forwarding (8080, 40400)
- Option to view node Peer ID
- Easy uninstall option
- User-friendly interactive menu

## Requirements:
- Ubuntu-based VPS (tested on 20.04+)
- Root or sudo privileges

## Installation:
To download and run the script directly:

```bash
source <(curl -s https://raw.githubusercontent.com/Souravjoy7/aztec-node/main/aztec-node.sh)
