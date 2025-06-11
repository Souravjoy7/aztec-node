# Aztec Node Setup Script

This script automates the installation, configuration, and management of an Aztec node on Ubuntu. It simplifies the process of running a node by handling dependencies, systemd service setup, port forwarding, and health checks.

## Features:
- Full installation with required dependencies
- Configures and sets up an Aztec node as a service
- Automatically kills processes occupying essential ports
- Health checker for L1 RPC response time
- Port forwarding with socat for required ports
- Uninstall option to remove the setup
- Easy-to-use menu for management

## Requirements:
- Ubuntu-based system
- Root privileges

## Installation:
1. Download the script:
   ```bash
   wget https://github.com/Souravjoy7/aztec-node/main/aztec-node.sh
   chmod +x aztec-node.sh
