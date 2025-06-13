#!/bin/bash

# AZTEC NODE MANAGER BY SOURAV JOY (Updated to load external scripts from GitHub)
# Menu Options:
# 1) Full Install
# 2) Reconfigure
# 3) View Logs
# 4) Uninstall
# 5) Check RPC Health (Downloaded)
# 6) Show Peer ID
# 7) Telegram Bot Monitor Setup (Downloaded)
# 8) Exit

# Color Codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

AZTEC_SERVICE="/etc/systemd/system/aztec-node.service"
AZTEC_DIR="/root/.aztec"
AZTEC_DATA_DIR="$AZTEC_DIR/alpha-testnet"

install_full() {
    echo -e "${YELLOW}🚀 Starting Full Installation...${NC}"
    if [ "$(id -u)" -ne 0 ]; then echo -e "${RED}Run as root${NC}"; exit 1; fi

    echo -e "${GREEN}Killing process using port 40400...${NC}"
    lsof -i :40400 -t | xargs -r kill -9

    echo -e "${GREEN}Updating system...${NC}"
    apt update -y && apt upgrade -y

    echo -e "${GREEN}Installing dependencies...${NC}"
    apt install -y curl iptables build-essential git wget lz4 jq make gcc nano automake \
        autoconf tmux htop nvme-cli libgbm1 pkg-config libssl-dev libleveldb-dev tar \
        clang bsdmainutils ncdu unzip screen socat ufw bc python3 python3-pip python3-venv

    echo -e "${GREEN}Installing Aztec Node...${NC}"
    bash -i <(curl -s https://install.aztec.network)
    echo 'export PATH=$PATH:/root/.aztec/bin' >> ~/.bashrc && source ~/.bashrc
    aztec-up latest

    echo -e "${GREEN}Setting up directories...${NC}"
    mkdir -p "$AZTEC_DATA_DIR"
    chown -R root:root "$AZTEC_DIR"
    chmod 700 "$AZTEC_DIR"

    echo -e "${GREEN}Opening firewall ports...${NC}"
    ufw allow 8545/tcp && ufw allow 3500/tcp && ufw allow 8081/tcp && ufw allow 30303/tcp
    ufw allow 30303/udp && ufw allow 8080/tcp && ufw allow 40400/udp && ufw allow 8880/tcp
    ufw --force enable

    echo -e "${GREEN}Creating systemd service...${NC}"
    PUBLIC_IP=$(curl -4 -s ifconfig.me)
    cat <<EOF > $AZTEC_SERVICE
[Unit]
Description=Aztec Validator Node
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$AZTEC_DIR
Environment="AZTEC_DATA_DIR=$AZTEC_DATA_DIR"
Environment="NODE_OPTIONS=--max-old-space-size=8192"
ExecStart=/root/.aztec/bin/aztec start \\
  --node \\
  --archiver \\
  --sequencer \\
  --network alpha-testnet \\
  --l1-rpc-urls http://127.0.0.1:8545 \\
  --l1-consensus-host-urls http://127.0.0.1:3500 \\
  --sequencer.validatorPrivateKey YOUR_KEY \\
  --sequencer.coinbase YOUR_ADDRESS \\
  --p2p.p2pIp $PUBLIC_IP \\
  --port 8081 \\
  --admin-port 8880 \\
  --sequencer.governanceProposerPayload 0x54F7fe24E349993b363A5Fa1bccdAe2589D5E5Ef
Restart=always
RestartSec=5
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

    echo -e "${GREEN}Creating socat port forwarders...${NC}"
    cat <<EOF > /etc/systemd/system/forward-8080.service
[Unit]
Description=Port Forward 8080 -> 8081
After=network.target

[Service]
ExecStart=/usr/bin/socat TCP-LISTEN:8080,fork TCP:127.0.0.1:8081
Restart=always

[Install]
WantedBy=multi-user.target
EOF

    cat <<EOF > /etc/systemd/system/forward-40400.service
[Unit]
Description=Port Forward 40400 -> 30303 (UDP)
After=network.target

[Service]
ExecStart=/usr/bin/socat UDP-LISTEN:40400,fork UDP:127.0.0.1:30303
Restart=always

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable aztec-node forward-8080 forward-40400
    systemctl start aztec-node forward-8080 forward-40400

    echo -e "${GREEN}✅ Installation complete!${NC}"
}

reconfigure() {
    echo -e "${YELLOW}🔧 Reconfiguring Aztec Node...${NC}"
    if [ ! -f "$AZTEC_SERVICE" ]; then echo -e "${RED}Service not found.${NC}"; return; fi
    read -p "L1 RPC URL: " RPC
    read -p "Consensus URL: " CONS
    read -p "Validator Key: " KEY
    read -p "Coinbase Address: " CB
    PUBIP=$(curl -4 -s ifconfig.me)

    systemctl stop aztec-node
    sed -i -e "s|--l1-rpc-urls .*|--l1-rpc-urls $RPC \\\\|" \
           -e "s|--l1-consensus-host-urls .*|--l1-consensus-host-urls $CONS \\\\|" \
           -e "s|--sequencer.validatorPrivateKey .*|--sequencer.validatorPrivateKey $KEY \\\\|" \
           -e "s|--sequencer.coinbase .*|--sequencer.coinbase $CB \\\\|" \
           -e "s|--p2p.p2pIp .*|--p2p.p2pIp $PUBIP \\\\|" $AZTEC_SERVICE
    systemctl daemon-reload && systemctl restart aztec-node
}

view_logs() {
    echo -e "${YELLOW}📜 Viewing logs...${NC}"
    journalctl -u aztec-node -f --no-pager
}

uninstall() {
    echo -e "${YELLOW}🧹 Uninstalling Aztec Node...${NC}"
    systemctl stop aztec-node forward-8080 forward-40400
    systemctl disable aztec-node forward-8080 forward-40400
    rm -f $AZTEC_SERVICE /etc/systemd/system/forward-8080.service /etc/systemd/system/forward-40400.service
    systemctl daemon-reload
    rm -rf $AZTEC_DIR
    echo -e "${GREEN}✅ Uninstalled.${NC}"
}

check_rpc_health() {
    bash <(curl -s https://raw.githubusercontent.com/Souravjoy7/aztec-node-tools/main/rpc_health_check.sh)
}

show_peer_id() {
    PEER_ID=$(journalctl -u aztec-node -n 10000 --no-pager | grep -i "peerId" | grep -o '"peerId":"[^"]*"' | cut -d'"' -f4 | head -n 1)
    [[ -z "$PEER_ID" ]] && echo -e "${RED}❌ Not found.${NC}" || echo -e "${GREEN}✅ Peer ID: ${PEER_ID}${NC}"
}

telegram_bot_setup() {
    bash <(curl -s https://raw.githubusercontent.com/Souravjoy7/aztec-node-tools/main/aztec_telegram_monitor.sh)
}

# ===================== MENU ==========================
while true; do
    clear
    echo -e "${BLUE}================ AZTEC NODE MANAGER =================${NC}"
    echo -e "1) Full Install (no Docker)"
    echo -e "2) Reconfigure RPC/Key"
    echo -e "3) View Logs"
    echo -e "4) Uninstall"
    echo -e "5) Check RPC Health (Industry Standard)"
    echo -e "6) Show Peer ID"
    echo -e "7) Telegram Bot Monitor Setup"
    echo -e "8) Exit"
    echo -e "${BLUE}====================================================${NC}"
    read -p "Choose option (1-8): " choice

    case $choice in
        1) install_full ;;
        2) reconfigure ;;
        3) view_logs ;;
        4) uninstall ;;
        5) check_rpc_health ;;
        6) show_peer_id ;;
        7) telegram_bot_setup ;;
        8) break ;;
        *) echo -e "${RED}Invalid option!${NC}"; sleep 1 ;;
    esac
    read -p "Press Enter to return to menu..."
done
