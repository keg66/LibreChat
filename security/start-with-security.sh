#!/bin/bash

echo "=== Starting LibreChat with NetRestrictor Security ==="
echo "Date: $(date)"
echo "Container: $HOSTNAME"

# Configuration file path
CONFIG_FILE="/app/security/security-config.json"

# Function to read JSON config using jq
read_config() {
    local key="$1"
    if [ -f "$CONFIG_FILE" ]; then
        jq -r ".$key // empty" "$CONFIG_FILE" 2>/dev/null
    else
        echo "Warning: Config file $CONFIG_FILE not found"
        return 1
    fi
}

# Function to check if a service category is enabled using jq
is_enabled() {
    local category="$1"
    if [ -f "$CONFIG_FILE" ]; then
        local enabled=$(jq -r ".allowed_connections.\"$category\".enabled // false" "$CONFIG_FILE" 2>/dev/null)
        [ "$enabled" = "true" ]
    else
        return 1
    fi
}

# We run as root, so we can apply iptables rules directly
if [ "$EUID" -eq 0 ]; then
    echo "Running as root, applying NetRestrictor iptables rules..."
    
    if [ -f "$CONFIG_FILE" ]; then
        echo "Loading configuration from $CONFIG_FILE"
    else
        echo "Warning: Configuration file not found, using hardcoded defaults"
    fi
    
    # Temporarily allow DNS for hostname resolution during startup
    iptables -A OUTPUT -p udp --dport 53 -j ACCEPT 2>/dev/null || echo "Warning: Could not add temporary DNS rule"
    
    # Set default policies based on config (but keep DNS allowed for now)
    iptables -P OUTPUT ACCEPT 2>/dev/null || echo "Warning: Could not set OUTPUT policy"
    
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
    
    # Allow external DNS (if enabled in config)
    if is_enabled "external_dns" || [ ! -f "$CONFIG_FILE" ]; then
        if [ -f "$CONFIG_FILE" ] && is_enabled "external_dns"; then
            echo "✅ External DNS (Configured servers):"
            
            # Parse DNS servers using jq
            jq -r '.allowed_connections.external_dns.servers[]? | "\(.name)|\(.ip)|\(.port)|\(.protocol)"' "$CONFIG_FILE" 2>/dev/null | while IFS='|' read -r dns_name dns_ip dns_port dns_protocol; do
                if [ -n "$dns_name" ] && [ -n "$dns_ip" ] && [ -n "$dns_port" ] && [ -n "$dns_protocol" ]; then
                    echo "  ✅ $dns_name ($dns_ip:$dns_port/$dns_protocol)"
                    
                    # Add iptables rule for this DNS server
                    iptables -A OUTPUT -d "$dns_ip" -p "$dns_protocol" --dport "$dns_port" -j ACCEPT 2>/dev/null || echo "Warning: Could not add DNS rule for $dns_ip"
                fi
            done
        else
            # Fallback: allow standard external DNS
            iptables -A OUTPUT -p udp --dport 53 ! -d 127.0.0.11 -j ACCEPT 2>/dev/null || echo "Warning: Could not add external DNS rule"
            echo "✅ External DNS (port 53/udp to external servers) allowed"
        fi
    fi
    
    # Allow internal service connections (if enabled in config)
    if is_enabled "internal_services" || [ ! -f "$CONFIG_FILE" ]; then
        if [ -f "$CONFIG_FILE" ] && is_enabled "internal_services"; then
            echo "✅ Internal services (Config-based):"
            
            # Parse internal services using jq
            jq -r '.allowed_connections.internal_services.services[]? | "\(.name)|\(.port)|\(.protocol)"' "$CONFIG_FILE" 2>/dev/null | while IFS='|' read -r service_name service_port service_protocol; do
                if [ -n "$service_name" ] && [ -n "$service_port" ] && [ -n "$service_protocol" ]; then
                    echo "  ✅ $service_name ($service_port/$service_protocol)"
                    
                    # Add iptables rule for this service
                    iptables -A OUTPUT -p "$service_protocol" --dport "$service_port" -j ACCEPT 2>/dev/null || echo "Warning: Could not add $service_name rule"
                fi
            done
        else
            # Fallback: use hardcoded defaults if no config file
            iptables -A OUTPUT -p tcp --dport 27017 -j ACCEPT 2>/dev/null || echo "Warning: Could not add MongoDB rule"
            iptables -A OUTPUT -p tcp --dport 7700 -j ACCEPT 2>/dev/null || echo "Warning: Could not add Meilisearch rule"
            iptables -A OUTPUT -p tcp --dport 8000 -j ACCEPT 2>/dev/null || echo "Warning: Could not add RAG API rule"
            iptables -A OUTPUT -p tcp --dport 5432 -j ACCEPT 2>/dev/null || echo "Warning: Could not add PostgreSQL rule"
            echo "✅ Internal services (MongoDB:27017, Meilisearch:7700, RAG:8000, PostgreSQL:5432) allowed"
        fi
    fi
    
    # Allow connections to host.docker.internal (if enabled in config)
    if is_enabled "host_services" || [ ! -f "$CONFIG_FILE" ]; then
        if [ -f "$CONFIG_FILE" ] && is_enabled "host_services"; then
            echo "✅ Host services (Config-based):"
            
            # Parse host services using jq
            jq -r '.allowed_connections.host_services.services[]? | "\(.name)|\(.port)|\(.protocol)"' "$CONFIG_FILE" 2>/dev/null | while IFS='|' read -r service_name service_port service_protocol; do
                if [ -n "$service_name" ] && [ -n "$service_port" ] && [ -n "$service_protocol" ]; then
                    echo "  ✅ $service_name ($service_port/$service_protocol)"
                    
                    # Add iptables rule for this service
                    iptables -A OUTPUT -p "$service_protocol" --dport "$service_port" -j ACCEPT 2>/dev/null || echo "Warning: Could not add $service_name rule"
                fi
            done
        else
            # Fallback: use hardcoded defaults if no config file
            iptables -A OUTPUT -p tcp --dport 3080 -j ACCEPT 2>/dev/null || echo "Warning: Could not add LibreChat rule"
            iptables -A OUTPUT -p tcp --dport 8081 -j ACCEPT 2>/dev/null || echo "Warning: Could not add proxy rule"
            echo "✅ Host services (LibreChat:3080, Proxy:8081) allowed"
        fi
    fi
    
    # Allow external APIs (if enabled in config)
    if is_enabled "external_apis" || [ ! -f "$CONFIG_FILE" ]; then
        if [ -f "$CONFIG_FILE" ] && is_enabled "external_apis"; then
            echo "✅ External APIs (Host-specific mode):"
            
            # Get primary DNS server from config using jq
            primary_dns=$(jq -r '.allowed_connections.external_dns.primary_server // "8.8.8.8"' "$CONFIG_FILE" 2>/dev/null)
            
            # Parse each service using jq
            jq -r '.allowed_connections.external_apis.services[]? | "\(.name)|\(.host)|\(.port)"' "$CONFIG_FILE" 2>/dev/null | while IFS='|' read -r name host port; do
                if [ -n "$name" ] && [ -n "$host" ] && [ -n "$port" ]; then
                    echo "  ✅ $name ($host:$port)"
                    
                    # Try to resolve hostname and add iptables rules
                    host_ips=""
                    
                    # Try dig with configured external DNS first (most reliable)
                    if host_ips=$(dig +short "$host" @"$primary_dns" 2>/dev/null | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$'); then
                        echo "    → Resolved via dig (using $primary_dns) to: $host_ips"
                    # Try nslookup with configured external DNS as fallback
                    elif host_ips=$(nslookup "$host" "$primary_dns" 2>/dev/null | grep "Address:" | grep -v "#53" | awk '{print $2}' | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$'); then
                        echo "    → Resolved via nslookup (using $primary_dns) to: $host_ips"
                    # Try getent as last resort
                    elif host_ips=$(getent hosts "$host" 2>/dev/null | awk '{print $1}' | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$'); then
                        echo "    → Resolved via getent to: $host_ips"
                    else
                        echo "    → Could not resolve hostname"
                    fi
                    
                    # Add iptables rules for resolved IPs
                    if [ -n "$host_ips" ]; then
                        for host_ip in $host_ips; do
                            # Validate IP format
                            if echo "$host_ip" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$'; then
                                iptables -A OUTPUT -d "$host_ip" -p tcp --dport "$port" -j ACCEPT 2>/dev/null
                            fi
                        done
                    fi
                    
                    # Store for testing purposes
                    echo "$name:$host:$port" >> /tmp/external_apis_config 2>/dev/null || true
                fi
            done
            
            echo "  📊 Applied host-specific rules for external APIs"
        else
            # Fallback: block all external access if no config
            echo "✅ External APIs disabled (no configuration file)"
        fi
    fi
    
    # Now apply the final DROP policy after all rules are set
    echo ""
    echo "Applying final security policy..."
    iptables -P OUTPUT DROP 2>/dev/null || echo "Warning: Could not set final DROP policy"
    
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