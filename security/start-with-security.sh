#!/bin/bash

echo "=== Starting LibreChat with NetRestrictor Security ==="
echo "Date: $(date)"
echo "Container: $HOSTNAME"

# Configuration file path
CONFIG_FILE="/app/security/security-config.json"

# Function to read JSON config
read_config() {
    local key="$1"
    if [ -f "$CONFIG_FILE" ]; then
        # Use basic shell tools to parse JSON (works without jq)
        grep -o "\"$key\"[[:space:]]*:[[:space:]]*[^,}]*" "$CONFIG_FILE" | cut -d':' -f2 | tr -d ' ",'
    else
        echo "Warning: Config file $CONFIG_FILE not found"
        return 1
    fi
}

# Function to check if a service category is enabled
is_enabled() {
    local category="$1"
    local enabled=$(grep -A 10 "\"$category\"" "$CONFIG_FILE" | grep -o '"enabled"[[:space:]]*:[[:space:]]*[^,}]*' | cut -d':' -f2 | tr -d ' ",')
    [ "$enabled" = "true" ]
}

# We run as root, so we can apply iptables rules directly
if [ "$EUID" -eq 0 ]; then
    echo "Running as root, applying NetRestrictor iptables rules..."
    
    if [ -f "$CONFIG_FILE" ]; then
        echo "Loading configuration from $CONFIG_FILE"
    else
        echo "Warning: Configuration file not found, using hardcoded defaults"
    fi
    
    # Set default policies based on config
    iptables -P OUTPUT DROP 2>/dev/null || echo "Warning: Could not set OUTPUT policy"
    
    # Allow loopback traffic (always enabled for basic functionality)
    iptables -A OUTPUT -o lo -j ACCEPT 2>/dev/null || echo "Warning: Could not add loopback rule"
    iptables -A INPUT -i lo -j ACCEPT 2>/dev/null || echo "Warning: Could not add input loopback rule"
    echo "✅ Loopback traffic allowed"
    
    # Allow established connections (if enabled in config)
    if is_enabled "established" || [ ! -f "$CONFIG_FILE" ]; then
        iptables -A OUTPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT 2>/dev/null || echo "Warning: Could not add established connections rule"
        echo "✅ Established connections allowed"
    fi
    
    # Allow DNS (if enabled in config)
    if is_enabled "dns" || [ ! -f "$CONFIG_FILE" ]; then
        iptables -A OUTPUT -p udp --dport 53 -j ACCEPT 2>/dev/null || echo "Warning: Could not add DNS rule"
        echo "✅ DNS (port 53/udp) allowed"
    fi
    
    # Allow internal service connections (if enabled in config)
    if is_enabled "internal_services" || [ ! -f "$CONFIG_FILE" ]; then
        iptables -A OUTPUT -p tcp --dport 27017 -j ACCEPT 2>/dev/null || echo "Warning: Could not add MongoDB rule"
        iptables -A OUTPUT -p tcp --dport 7700 -j ACCEPT 2>/dev/null || echo "Warning: Could not add Meilisearch rule"
        iptables -A OUTPUT -p tcp --dport 8000 -j ACCEPT 2>/dev/null || echo "Warning: Could not add RAG API rule"
        iptables -A OUTPUT -p tcp --dport 5432 -j ACCEPT 2>/dev/null || echo "Warning: Could not add PostgreSQL rule"
        echo "✅ Internal services (MongoDB:27017, Meilisearch:7700, RAG:8000, PostgreSQL:5432) allowed"
    fi
    
    # Allow connections to host.docker.internal (if enabled in config)
    if is_enabled "host_services" || [ ! -f "$CONFIG_FILE" ]; then
        iptables -A OUTPUT -p tcp --dport 3080 -j ACCEPT 2>/dev/null || echo "Warning: Could not add LibreChat rule"
        iptables -A OUTPUT -p tcp --dport 8081 -j ACCEPT 2>/dev/null || echo "Warning: Could not add proxy rule"
        echo "✅ Host services (LibreChat:3080, Proxy:8081) allowed"
    fi
    
    # Allow HTTP/HTTPS for AI APIs (if enabled in config)
    if is_enabled "external_apis" || [ ! -f "$CONFIG_FILE" ]; then
        iptables -A OUTPUT -p tcp --dport 80 -j ACCEPT 2>/dev/null || echo "Warning: Could not add HTTP rule"
        iptables -A OUTPUT -p tcp --dport 443 -j ACCEPT 2>/dev/null || echo "Warning: Could not add HTTPS rule"
        echo "✅ External APIs (HTTP:80, HTTPS:443) allowed"
    fi
    
    echo ""
    echo "NetRestrictor security rules applied successfully"
    echo "Current iptables rules:"
    iptables -L -n 2>/dev/null || echo "Warning: Could not list iptables rules"
    
    # Switch to node user and start LibreChat
    echo "Starting LibreChat application as node user..."
    cd /app
    export HOME=/home/node
    exec su-exec node npm run backend
else
    echo "Not running as root, starting LibreChat directly..."
    cd /app
    exec npm run backend
fi