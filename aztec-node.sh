#!/bin/bash

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Paths
AZTEC_SERVICE="/etc/systemd/system/aztec-node.service"
AZTEC_DIR="/root/.aztec"
AZTEC_DATA_DIR="$AZTEC_DIR/alpha-testnet"

# ----------------------------------
# Option 1: Full Install
# ----------------------------------
install_full() {
    echo -e "${YELLOW}🚀 Starting Full Installation...${NC}"

    # Root check
    if [ "$(id -u)" -ne 0 ]; then
        echo -e "${RED}Error: Run as root${NC}"
        exit 1
    fi

    echo -e "${GREEN}[1/8] Killing any process using port 40400...${NC}"
    lsof -i :40400 -t | xargs -r kill -9

    echo -e "${GREEN}[2/8] Updating system...${NC}"
    apt update -y && apt upgrade -y

    echo -e "${GREEN}[3/8] Installing dependencies...${NC}"
    apt install -y curl iptables build-essential git wget lz4 jq make gcc nano automake \
        autoconf tmux htop nvme-cli libgbm1 pkg-config libssl-dev libleveldb-dev \
        tar clang bsdmainutils ncdu unzip screen socat ufw

    echo -e "${GREEN}[4/8] Installing Aztec Node...${NC}"
    bash -i <(curl -s https://install.aztec.network)
    echo 'export PATH=$PATH:/root/.aztec/bin' >> ~/.bashrc
    source ~/.bashrc
    aztec-up latest

    echo -e "${GREEN}[5/8] Setting up directories...${NC}"
    mkdir -p "$AZTEC_DATA_DIR"
    chown -R root:root "$AZTEC_DIR"
    chmod 700 "$AZTEC_DIR"

    echo -e "${GREEN}[6/8] Opening firewall ports...${NC}"
    ufw allow 8545/tcp
    ufw allow 3500/tcp
    ufw allow 8081/tcp
    ufw allow 30303/tcp
    ufw allow 30303/udp
    ufw allow 8080/tcp
    ufw allow 40400/udp
    ufw allow 8880/tcp
    ufw --force enable

    echo -e "${GREEN}[7/8] Creating systemd service...${NC}"
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

    echo -e "${GREEN}[8/8] Creating socat forwarding services...${NC}"
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
    echo -e "Logs: ${YELLOW}journalctl -u aztec-node -f${NC}"
}

# ----------------------------------
# Option 2: Reconfigure Node
# ----------------------------------
reconfigure() {
    echo -e "${YELLOW}🔧 Reconfiguring...${NC}"
    if [ ! -f "$AZTEC_SERVICE" ]; then
        echo -e "${RED}Service not found. Run full install first.${NC}"
        return
    fi

    read -p "L1 RPC URL: " NEW_RPC
    read -p "L1 Consensus Host: " NEW_CONSENSUS
    read -p "Validator Private Key: " NEW_KEY
    read -p "Coinbase Address: " NEW_COINBASE

    PUBLIC_IP=$(curl -4 -s ifconfig.me)

    systemctl stop aztec-node

    sed -i \
        -e "s|--l1-rpc-urls .*|--l1-rpc-urls $NEW_RPC \\\\|" \
        -e "s|--l1-consensus-host-urls .*|--l1-consensus-host-urls $NEW_CONSENSUS \\\\|" \
        -e "s|--sequencer.validatorPrivateKey .*|--sequencer.validatorPrivateKey $NEW_KEY \\\\|" \
        -e "s|--sequencer.coinbase .*|--sequencer.coinbase $NEW_COINBASE \\\\|" \
        -e "s|--p2p.p2pIp .*|--p2p.p2pIp $PUBLIC_IP \\\\|" \
        "$AZTEC_SERVICE"

    systemctl daemon-reload
    systemctl restart aztec-node

    if systemctl is-active --quiet aztec-node; then
        echo -e "${GREEN}✅ Node reconfigured and running.${NC}"
    else
        echo -e "${RED}❌ Failed to start. Check logs.${NC}"
        journalctl -u aztec-node -n 20 --no-pager
    fi
}

# ----------------------------------
# Option 3: View Logs
# ----------------------------------
view_logs() {
    echo -e "${YELLOW}📜 Aztec Logs...${NC}"
    journalctl -u aztec-node -f --no-pager
}

# ----------------------------------
# Option 4: Uninstall
# ----------------------------------
uninstall() {
    echo -e "${YELLOW}🧹 Uninstalling Aztec Node...${NC}"
    systemctl stop aztec-node forward-8080 forward-40400
    systemctl disable aztec-node forward-8080 forward-40400
    rm -f $AZTEC_SERVICE /etc/systemd/system/forward-8080.service /etc/systemd/system/forward-40400.service
    systemctl daemon-reload
    rm -rf $AZTEC_DIR
    echo -e "${GREEN}✅ Uninstall complete.${NC}"
}

# ----------------------------------
# Option 5: RPC Health Checker
# ----------------------------------
check_rpc_health() {
    echo -e "${YELLOW}🔍 Checking RPC health...${NC}"
    read -p "L1 RPC URL: " RPC_URL
    read -p "L1 Consensus Host URL: " CONS_URL

    # Check block production
    block=$(curl -s -X POST -H "Content-Type: application/json" --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' $RPC_URL | jq -r .result)
    if [[ $block == "null" || -z $block ]]; then
        echo -e "${RED}❌ L1 RPC is not producing blocks. Invalid RPC.${NC}"
        return
    fi

    echo -e "${GREEN}L1 RPC is producing blocks (latest block: $block)${NC}"
    
    response=$(curl -s -w "%{time_total}" -o /dev/null $RPC_URL)
    consensus=$(curl -s -w "%{time_total}" -o /dev/null $CONS_URL)

    echo -e "\nL1 RPC response time: ${YELLOW}${response}s${NC}"
    case 1 in
        $([[ $(echo "$response == 0" | bc) -eq 1 ]] && echo 1)) echo -e "${RED}❌ Invalid (0s response)${NC}" ;;
        $([[ $(echo "$response < 0.002" | bc) -eq 1 ]] && echo 1)) echo -e "${GREEN}✅ Super Healthy${NC}" ;;
        $([[ $(echo "$response < 0.0045" | bc) -eq 1 ]] && echo 1)) echo -e "${YELLOW}✅ Healthy${NC}" ;;
        $([[ $(echo "$response < 0.007" | bc) -eq 1 ]] && echo 1)) echo -e "${RED}⚠️  Poor${NC}" ;;
        *) echo -e "${RED}❌ Not suitable for Aztec node${NC}" ;;
    esac

    echo -e "\nL1 Consensus Host response time: ${YELLOW}${consensus}s${NC}"
}

# ----------------------------------
# Option 6: Show Peer ID
# ----------------------------------
show_peer_id() {
    echo -e "${YELLOW}🔍 Fetching Peer ID from aztec-node logs...${NC}"
    PEER_ID=$(journalctl -u aztec-node -n 100000 --no-pager | grep -i "peerId" | grep -o '"peerId":"[^\"]*"' | cut -d'"' -f4 | head -n 1)
    if [ -z "$PEER_ID" ]; then
        echo -e "${RED}❌ Peer ID not found. Make sure the node has started successfully.${NC}"
    else
        echo -e "${GREEN}✅ Your Peer ID: ${YELLOW}$PEER_ID${NC}"
    fi
}

# ----------------------------------
# Menu
# ----------------------------------
while true; do
    clear
    echo -e "${YELLOW}==============================${NC}"
    echo -e "AZTEC NODE INSTALLER BY SOURAV JOY"
    echo -e "${YELLOW}==============================${NC}"
    echo -e "1) Full Install (no Docker)"
    echo -e "2) Reconfigure RPC/Key"
    echo -e "3) View Logs"
    echo -e "4) Uninstall"
    echo -e "5) Check RPC Health"
    echo -e "6) Show Peer ID"
    echo -e "7) Exit"
    echo -e "${YELLOW}==============================${NC}"
    read -p "Choose option (1-7): " choice

    case $choice in
        1) install_full ;;
        2) reconfigure ;;
        3) view_logs ;;
        4) uninstall ;;
        5) check_rpc_health ;;
        6) show_peer_id ;;
        7) break ;;
        *) echo -e "${RED}Invalid option!${NC}" ; sleep 1 ;;
    esac
    read -p "Press Enter to return to menu..."
done
