# 🦅 OghabHost GRE Tunnel

**Advanced GRE Tunnel & Selective Port Forwarding for Linux Servers**

OghabHost GRE Tunnel is an interactive Bash script designed to establish a GRE tunnel between an IRAN server and a FOREIGN server.

Unlike traditional GRE configurations that route all server traffic through the tunnel, OghabHost allows you to select specific TCP and UDP ports for forwarding.

Simple, lightweight, and fully interactive.

## ✨ Features

- 🚀 Automatic GRE tunnel configuration
- 🎯 Selective TCP port forwarding
- 🔀 Selective UDP port forwarding
- 🔒 NAT-based traffic routing
- 🛡️ SSH port protection (Port 22)
- 🌐 Separate IRAN and FOREIGN server configuration
- ⚡ Automatic IP forwarding configuration
- 🔧 Custom iptables chains
- 🔄 Reconfiguration support
- 💻 Interactive Bash interface

## 📋 Requirements

Both servers must have:

- Linux operating system
- Root privileges
- iproute2
- iptables
- sysctl
- curl (for downloading the script)

**Network requirements:**

- GRE protocol (IP Protocol 47) must be allowed by the hosting provider and network firewall.
- Both servers must be reachable through their public IP addresses.

## 📥 Installation

Run the following command on both servers:

```bash
curl -fsSL https://raw.githubusercontent.com/OghabTeam/gre/main/gre.sh -o /tmp/oghab-gre.sh && sudo bash /tmp/oghab-gre.sh
```

The script will automatically download and run the latest version from this repository.

## ⚙️ Configuration Guide

### 1. Select Server Location

When the script starts, select your server role:

```text
1 - IRAN
2 - FOREIGN
```

- Select `1` on your IRAN server.
- Select `2` on your FOREIGN server.

### 2. Enter Server IP Addresses

Enter the public IP addresses of both servers:

```text
Enter IRAN server public IP:
Enter FOREIGN server public IP:
```

### 3. Select TCP Ports

Specify the TCP ports you want to forward through the GRE tunnel.

Example:

```text
80,443,8080,8443
```

### 4. Select UDP Ports

Specify the UDP ports you want to forward through the GRE tunnel.

Example:

```text
53,500,4500
```

You can leave either field empty if you don't need that protocol.

**Important:** Use the same TCP and UDP port lists on both servers.

## 🛡️ SSH Protection

The script includes additional protection for SSH connections.

If TCP port `22` is selected, the script displays a warning and asks for confirmation:

```text
[WARNING] TCP port 22 is your SSH port!

Tunnel SSH anyway? Type YES to confirm:
```

Unless you explicitly enter `YES`, port 22 will be excluded from the forwarding configuration.

## 🌐 Network Architecture

```text
                 INTERNET
                     |
                     |
              IRAN SERVER
               Public IP
                     |
              Selected Ports
                     |
                  DNAT
                     |
                  SNAT
                     |
                     |
                GRE TUNNEL
                     |
              132.168.30.2
                     |
                     |
              132.168.30.1
                     |
                     |
             FOREIGN SERVER
                     |
              Selected Services
```

## 🔧 Default GRE Configuration

| Configuration | Value |
|---|---|
| Tunnel Interface | `oghab-m2` |
| IRAN Tunnel IP | `132.168.30.2/30` |
| FOREIGN Tunnel IP | `132.168.30.1/30` |
| Tunnel Mode | GRE |
| TTL | 255 |

### Custom iptables Chains

The script uses the following custom chains:

| Chain | Purpose |
|---|---|
| VHG_DNAT | Selected port destination NAT |
| VHG_SNAT | Source NAT through GRE |
| VHG_FWD | Forwarding traffic rules |
| VHG_INPUT | Incoming traffic rules on FOREIGN |

## 🧪 Testing

After configuring both servers, verify GRE connectivity.

On the IRAN server:

```bash
ping -c 4 132.168.30.1
```

On the FOREIGN server:

```bash
ping -c 4 132.168.30.2
```

Check the GRE interface:

```bash
ip -br addr show oghab-m2
```

Check NAT rules on IRAN:

```bash
iptables -t nat -vnL VHG_DNAT
iptables -t nat -vnL VHG_SNAT
```

Check forwarding rules on IRAN:

```bash
iptables -vnL VHG_FWD
```

Check incoming rules on FOREIGN:

```bash
iptables -vnL VHG_INPUT
```

## ⚠️ Important Notes

1. GRE protocol 47 must be enabled by your hosting provider.
2. Services on the FOREIGN server should listen on `132.168.30.1` or `0.0.0.0`.
3. The FOREIGN server sees the source IP as `132.168.30.2` because SNAT is enabled.
4. Only the selected TCP and UDP ports are forwarded through the tunnel.
5. Other traffic continues through the normal routing path of the IRAN server.
6. Existing firewall configurations such as UFW and Firewalld may affect connectivity.
7. Tunnel and firewall settings are not automatically restored after reboot.
8. The script rebuilds its own custom firewall chains when reconfigured. Avoid placing unrelated rules inside these chains.

## 👨‍💻 Project

**OghabTeam**

GitHub Repository:

https://github.com/OghabTeam/gre

## 📜 License

No specific license has been declared yet. Check the repository for licensing information.

---

**Developed with ❤️ by OghabTeam**

🦅 *OghabHost GRE Tunnel – Simple, Fast & Selective.*
