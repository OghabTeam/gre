
#!/bin/bash

set -eo pipefail

CYAN=$(tput setaf 6 2>/dev/null || true)
GREEN=$(tput setaf 2 2>/dev/null || true)
YELLOW=$(tput setaf 3 2>/dev/null || true)
RED=$(tput setaf 1 2>/dev/null || true)
RESET=$(tput sgr0 2>/dev/null || true)

# ==========================================
# CONFIGURATION
# ==========================================

TUNNEL_NAME="oghab-m2"

IRAN_TUNNEL_IP="132.168.30.2"
FOREIGN_TUNNEL_IP="132.168.30.1"

CHAIN_DNAT="VHG_DNAT"
CHAIN_SNAT="VHG_SNAT"
CHAIN_FORWARD="VHG_FWD"
CHAIN_INPUT="VHG_INPUT"

# ==========================================
# ROOT CHECK
# ==========================================

if [[ $EUID -ne 0 ]]; then
    echo "[!] Please run as root:"
    echo "sudo bash $0"
    exit 1
fi

for cmd in ip iptables sysctl; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "[!] Required command not found: $cmd"
        exit 1
    fi
done

clear 2>/dev/null || true

echo -e "${CYAN}"
echo "=========================================="
echo "          OGHABHOST GRE TUNNEL"
echo "          PORT FORWARDING v2"
echo "=========================================="
echo -e "${RESET}"

# ==========================================
# FUNCTIONS
# ==========================================

parse_ports() {
    local raw="$1"
    local cleaned="${raw//,/ }"
    local p n
    local -a items=()

    PORTS=()

    read -r -a items <<< "$cleaned" || true

    for p in "${items[@]}"; do

        if [[ ! "$p" =~ ^[0-9]{1,5}$ ]]; then
            echo -e "${RED}[!] Invalid port: $p${RESET}"
            return 1
        fi

        n=$((10#$p))

        if (( n < 1 || n > 65535 )); then
            echo -e "${RED}[!] Invalid port range: $p${RESET}"
            return 1
        fi

        case " ${PORTS[*]} " in
            *" $n "*) ;;
            *) PORTS+=("$n") ;;
        esac
    done
}

ensure_chain() {
    local table="$1"
    local chain="$2"

    if ! iptables -t "$table" -S "$chain" >/dev/null 2>&1; then
        iptables -t "$table" -N "$chain"
    fi

    iptables -t "$table" -F "$chain"
}

ensure_hook() {
    local table="$1"
    local parent="$2"
    local chain="$3"

    shift 3

    while iptables -t "$table" -C "$parent" "$@" -j "$chain" 2>/dev/null; do
        iptables -t "$table" -D "$parent" "$@" -j "$chain"
    done

    iptables -t "$table" -I "$parent" 1 "$@" -j "$chain"
}

ensure_rule() {
    local table="$1"
    local chain="$2"

    shift 2

    if ! iptables -t "$table" -C "$chain" "$@" 2>/dev/null; then
        iptables -t "$table" -I "$chain" 1 "$@"
    fi
}

remove_rule_all() {
    local table="$1"
    local chain="$2"

    shift 2

    while iptables -t "$table" -C "$chain" "$@" 2>/dev/null; do
        iptables -t "$table" -D "$chain" "$@"
    done
}

# ==========================================
# SERVER SELECTION
# ==========================================

echo "Select server location:"
echo
echo "1 - IRAN"
echo "2 - FOREIGN"
echo

read -rp "Enter 1 or 2: " LOCATION

if [[ "$LOCATION" != "1" && "$LOCATION" != "2" ]]; then
    echo "[!] Invalid selection."
    exit 1
fi

read -rp "Enter IRAN server public IP: " IP_IRAN
read -rp "Enter FOREIGN server public IP: " IP_FOREIGN

if [[ -z "$IP_IRAN" || -z "$IP_FOREIGN" ]]; then
    echo "[!] IP addresses cannot be empty."
    exit 1
fi

# ==========================================
# PORT SELECTION
# ==========================================

echo
echo "=========================================="
echo "             PORT SELECTION"
echo "=========================================="
echo
echo "Example: 80,443,8080"
echo "Leave empty if you don't need a protocol."
echo

read -rp "Enter TCP ports: " TCP_RAW
read -rp "Enter UDP ports: " UDP_RAW

parse_ports "$TCP_RAW" || exit 1
TCP_PORTS=("${PORTS[@]}")

parse_ports "$UDP_RAW" || exit 1
UDP_PORTS=("${PORTS[@]}")

# ==========================================
# SSH PROTECTION
# ==========================================

for p in "${TCP_PORTS[@]}"; do

    if [[ "$p" == "22" ]]; then

        echo
        echo -e "${YELLOW}[WARNING] TCP port 22 is your SSH port!${RESET}"

        read -rp "Tunnel SSH anyway? Type YES to confirm: " CONFIRM

        if [[ "$CONFIRM" != "YES" ]]; then

            FILTERED=()

            for x in "${TCP_PORTS[@]}"; do
                [[ "$x" == "22" ]] || FILTERED+=("$x")
            done

            TCP_PORTS=("${FILTERED[@]}")

            echo "[*] SSH port 22 excluded."
        fi

    fi

done

if [[ ${#TCP_PORTS[@]} -eq 0 && ${#UDP_PORTS[@]} -eq 0 ]]; then
    echo "[!] No ports selected."
    exit 1
fi

# ==========================================
# LOCAL / REMOTE CONFIGURATION
# ==========================================

if [[ "$LOCATION" == "1" ]]; then

    LOCAL_PUBLIC="$IP_IRAN"
    REMOTE_PUBLIC="$IP_FOREIGN"

    LOCAL_TUNNEL="$IRAN_TUNNEL_IP"
    REMOTE_TUNNEL="$FOREIGN_TUNNEL_IP"

else

    LOCAL_PUBLIC="$IP_FOREIGN"
    REMOTE_PUBLIC="$IP_IRAN"

    LOCAL_TUNNEL="$FOREIGN_TUNNEL_IP"
    REMOTE_TUNNEL="$IRAN_TUNNEL_IP"

fi

# ==========================================
# GRE TUNNEL SETUP
# ==========================================

echo
echo "[*] Configuring GRE tunnel..."

if command -v modprobe >/dev/null 2>&1; then
    modprobe ip_gre 2>/dev/null || true
fi

if ip link show "$TUNNEL_NAME" >/dev/null 2>&1; then

    ip tunnel change "$TUNNEL_NAME" mode gre \
        local "$LOCAL_PUBLIC" \
        remote "$REMOTE_PUBLIC" ttl 255

else

    ip tunnel add "$TUNNEL_NAME" mode gre \
        local "$LOCAL_PUBLIC" \
        remote "$REMOTE_PUBLIC" ttl 255

fi

ip addr replace "$LOCAL_TUNNEL/30" dev "$TUNNEL_NAME"

ip link set "$TUNNEL_NAME" up

# Allow GRE protocol 47 through host firewall
ensure_rule filter INPUT \
    -p 47 -s "$REMOTE_PUBLIC" -j ACCEPT

ensure_rule filter OUTPUT \
    -p 47 -d "$REMOTE_PUBLIC" -j ACCEPT

echo -e "${GREEN}[+] GRE interface configured.${RESET}"

# ==========================================
# IRAN SERVER
# ==========================================

if [[ "$LOCATION" == "1" ]]; then

    echo
    echo "=========================================="
    echo "         CONFIGURING IRAN SERVER"
    echo "=========================================="

    # Enable IP forwarding
    sysctl -w net.ipv4.ip_forward=1

    # Remove old catch-all DNAT rules from v1
    remove_rule_all nat PREROUTING \
        -p tcp --dport 22 \
        -j DNAT --to-destination "$IRAN_TUNNEL_IP"

    remove_rule_all nat PREROUTING \
        -j DNAT --to-destination "$FOREIGN_TUNNEL_IP"

    # Ask before removing an old global MASQUERADE rule.
    if iptables -t nat -C POSTROUTING -j MASQUERADE 2>/dev/null; then

        echo
        echo -e "${YELLOW}[WARNING] Found a global MASQUERADE rule.${RESET}"
        echo "If this was added by the old OghabHost script,"
        echo "it is no longer needed for this configuration."
        echo

        read -rp "Remove one matching rule? (y/N): " CLEAN

        if [[ "$CLEAN" =~ ^[Yy]$ ]]; then
            iptables -t nat -D POSTROUTING -j MASQUERADE
            echo "[+] Old global MASQUERADE rule removed."
        fi
    fi

    # --------------------------------------
    # CREATE NAT CHAINS
    # --------------------------------------

    ensure_chain nat "$CHAIN_DNAT"
    ensure_chain nat "$CHAIN_SNAT"

    ensure_hook nat PREROUTING "$CHAIN_DNAT"

    ensure_hook nat POSTROUTING "$CHAIN_SNAT" \
        -o "$TUNNEL_NAME"

    # --------------------------------------
    # CREATE FORWARD CHAIN
    # --------------------------------------

    ensure_chain filter "$CHAIN_FORWARD"

    ensure_hook filter FORWARD "$CHAIN_FORWARD"

    # --------------------------------------
    # TCP PORTS
    # --------------------------------------

    for port in "${TCP_PORTS[@]}"; do

        echo "[+] Tunneling TCP: $port"

        # DNAT selected TCP port
        iptables -t nat -A "$CHAIN_DNAT" \
            -d "$IP_IRAN" \
            -p tcp --dport "$port" \
            -j DNAT --to-destination "$FOREIGN_TUNNEL_IP"

        # SNAT selected TCP port
        iptables -t nat -A "$CHAIN_SNAT" \
            -d "$FOREIGN_TUNNEL_IP" \
            -p tcp --dport "$port" \
            -j SNAT --to-source "$IRAN_TUNNEL_IP"

        # Allow outgoing packets through GRE
        iptables -A "$CHAIN_FORWARD" \
            -o "$TUNNEL_NAME" \
            -d "$FOREIGN_TUNNEL_IP" \
            -p tcp --dport "$port" \
            -m conntrack --ctstate NEW,ESTABLISHED,RELATED \
            -j ACCEPT

        # Allow return packets
        iptables -A "$CHAIN_FORWARD" \
            -i "$TUNNEL_NAME" \
            -s "$FOREIGN_TUNNEL_IP" \
            -p tcp --sport "$port" \
            -m conntrack --ctstate ESTABLISHED,RELATED \
            -j ACCEPT

    done

    # --------------------------------------
    # UDP PORTS
    # --------------------------------------

    for port in "${UDP_PORTS[@]}"; do

        echo "[+] Tunneling UDP: $port"

        # DNAT selected UDP port
        iptables -t nat -A "$CHAIN_DNAT" \
            -d "$IP_IRAN" \
            -p udp --dport "$port" \
            -j DNAT --to-destination "$FOREIGN_TUNNEL_IP"

        # SNAT selected UDP port
        iptables -t nat -A "$CHAIN_SNAT" \
            -d "$FOREIGN_TUNNEL_IP" \
            -p udp --dport "$port" \
            -j SNAT --to-source "$IRAN_TUNNEL_IP"

        # Allow outgoing packets through GRE
        iptables -A "$CHAIN_FORWARD" \
            -o "$TUNNEL_NAME" \
            -d "$FOREIGN_TUNNEL_IP" \
            -p udp --dport "$port" \
            -m conntrack --ctstate NEW,ESTABLISHED,RELATED \
            -j ACCEPT

        # Allow return packets
        iptables -A "$CHAIN_FORWARD" \
            -i "$TUNNEL_NAME" \
            -s "$FOREIGN_TUNNEL_IP" \
            -p udp --sport "$port" \
            -m conntrack --ctstate ESTABLISHED,RELATED \
            -j ACCEPT

    done

    # Allow related ICMP error packets
    iptables -A "$CHAIN_FORWARD" \
        -i "$TUNNEL_NAME" \
        -s "$FOREIGN_TUNNEL_IP" \
        -p icmp \
        -m conntrack --ctstate RELATED \
        -j ACCEPT

    echo
    echo -e "${GREEN}[SUCCESS] IRAN server configured.${RESET}"

# ==========================================
# FOREIGN SERVER
# ==========================================

elif [[ "$LOCATION" == "2" ]]; then

    echo
    echo "=========================================="
    echo "        CONFIGURING FOREIGN SERVER"
    echo "=========================================="

    # --------------------------------------
    # CREATE INPUT CHAIN
    # --------------------------------------

    ensure_chain filter "$CHAIN_INPUT"

    ensure_hook filter INPUT "$CHAIN_INPUT" \
        -i "$TUNNEL_NAME"

    # --------------------------------------
    # ALLOW TCP PORTS
    # --------------------------------------

    for port in "${TCP_PORTS[@]}"; do

        echo "[+] Allowing TCP: $port"

        iptables -A "$CHAIN_INPUT" \
            -s "$IRAN_TUNNEL_IP" \
            -p tcp --dport "$port" \
            -j ACCEPT

    done

    # --------------------------------------
    # ALLOW UDP PORTS
    # --------------------------------------

    for port in "${UDP_PORTS[@]}"; do

        echo "[+] Allowing UDP: $port"

        iptables -A "$CHAIN_INPUT" \
            -s "$IRAN_TUNNEL_IP" \
            -p udp --dport "$port" \
            -j ACCEPT

    done

    echo
    echo -e "${GREEN}[SUCCESS] FOREIGN server configured.${RESET}"

fi

# ==========================================
# FINAL STATUS
# ==========================================

echo
echo "=========================================="
echo "          GRE CONFIGURATION DONE"
echo "=========================================="

echo
echo "Tunnel interface:"
ip -br addr show "$TUNNEL_NAME"

echo
echo "Selected TCP ports:"
echo "${TCP_PORTS[*]:-None}"

echo
echo "Selected UDP ports:"
echo "${UDP_PORTS[*]:-None}"

echo
echo -e "${GREEN}OghabHost GRE setup completed!${RESET}"
echo
