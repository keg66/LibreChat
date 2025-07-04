# LibreChat NetRestrictor Security System

## Overview

The NetRestrictor security system provides enterprise-grade network isolation for LibreChat using iptables-based firewall rules. This implementation ensures that LibreChat containers can only communicate with explicitly allowed services while maintaining full application functionality.

## Architecture

### Security Model
- **Default Policy**: DROP all outgoing traffic
- **Selective Allow**: Only explicitly permitted connections are allowed
- **Container-Level Isolation**: Each LibreChat container runs with restricted network access
- **JSON Configuration**: Centralized security policy management

### Network Isolation Layers
1. **Application Layer**: LibreChat container with security restrictions
2. **Service Layer**: Internal services (MongoDB, Meilisearch, etc.) with controlled access
3. **External Layer**: Restricted outbound access for AI APIs and authentication

## Configuration

### security-config.json

The security configuration is managed through `security/security-config.json`. This file defines all allowed network connections and security policies.

#### Configuration Structure

```json
{
  "netrestrictor": {
    "description": "LibreChat NetRestrictor Security Configuration",
    "version": "1.0",
    "default_policy": {
      "input": "ACCEPT",
      "output": "DROP",
      "forward": "DROP"
    }
  },
  "allowed_connections": {
    "category_name": {
      "enabled": true|false,
      "description": "Category description",
      "services": [...]
    }
  }
}
```

#### Security Categories

##### 1. Loopback Traffic
```json
"loopback": {
  "enabled": true,
  "description": "Allow loopback traffic for internal processes"
}
```
- **Purpose**: Essential for internal process communication
- **Target**: 127.0.0.1 (localhost)
- **Recommendation**: Always keep enabled

##### 2. Established Connections
```json
"established": {
  "enabled": true,
  "description": "Allow established and related connections"
}
```
- **Purpose**: Allow return traffic for outgoing connections
- **Mechanism**: iptables ESTABLISHED,RELATED state tracking
- **Recommendation**: Keep enabled for normal operation

##### 3. DNS Resolution
```json
"dns": {
  "enabled": true,
  "ports": [53],
  "protocols": ["udp"],
  "description": "Allow DNS resolution (Docker internal DNS)"
}
```
- **Purpose**: Domain name resolution
- **Target**: Docker's internal DNS (127.0.0.11) and configured DNS servers
- **Port**: 53/UDP
- **Recommendation**: Required for container networking

##### 4. Internal Services
```json
"internal_services": {
  "enabled": true,
  "description": "Allow connections to internal LibreChat services",
  "services": [
    {"name": "MongoDB", "port": 27017, "protocol": "tcp"},
    {"name": "Meilisearch", "port": 7700, "protocol": "tcp"},
    {"name": "RAG API", "port": 8000, "protocol": "tcp"},
    {"name": "PostgreSQL/VectorDB", "port": 5432, "protocol": "tcp"}
  ]
}
```
- **Purpose**: Communication with LibreChat's internal services
- **Services**:
  - **MongoDB** (27017/tcp): Database storage
  - **Meilisearch** (7700/tcp): Search functionality
  - **RAG API** (8000/tcp): Retrieval-augmented generation
  - **PostgreSQL** (5432/tcp): Vector database
- **Recommendation**: Required for full LibreChat functionality

##### 5. Host Services
```json
"host_services": {
  "enabled": true,
  "description": "Allow connections to host services",
  "target": "host.docker.internal",
  "services": [
    {"name": "LibreChat Frontend", "port": 3080, "protocol": "tcp"},
    {"name": "OpenAI Chat Proxy", "port": 8081, "protocol": "tcp"}
  ]
}
```
- **Purpose**: Communication with services running on the Docker host
- **Services**:
  - **LibreChat Frontend** (3080/tcp): Web interface access
  - **OpenAI Chat Proxy** (8081/tcp): Secure AI API communication
- **Recommendation**: Required for proxy-based AI communication

##### 6. External APIs
```json
"external_apis": {
  "enabled": false,
  "description": "Allow specific external APIs and OAuth providers (disabled for local-only deployment)",
  "services": [
    // Example configurations - uncomment and modify as needed
    // {"name": "OpenAI API", "host": "api.openai.com", "port": 443},
    // {"name": "Anthropic API", "host": "api.anthropic.com", "port": 443},
    // {"name": "Google OAuth", "host": "accounts.google.com", "port": 443},
    // {"name": "GitHub API", "host": "api.github.com", "port": 443}
  ]
}
```
- **Purpose**: Host-specific access to external services
- **Configuration**: Each service requires `name`, `host`, and `port`
- **Default**: Disabled for maximum security in local-only deployments
- **Use Cases**:
  - AI provider APIs (OpenAI, Anthropic, Google, etc.)
  - OAuth authentication (Google, GitHub, Discord, etc.)
  - External tools (weather, search, etc.)
- **Security**: High security - only specified hosts allowed when enabled
- **Recommendation**: Keep disabled unless external API access is required

##### 7. External DNS
```json
"external_dns": {
  "enabled": false,
  "description": "Allow external DNS resolution for hostname lookups (disabled for local-only deployment)",
  "servers": [
    // Example configurations - uncomment and modify as needed
    // {"name": "Google Primary DNS", "ip": "8.8.8.8", "port": 53, "protocol": "udp"},
    // {"name": "Cloudflare Primary DNS", "ip": "1.1.1.1", "port": 53, "protocol": "udp"}
  ],
  "primary_server": "8.8.8.8"
}
```
- **Purpose**: Enable external DNS resolution for hostname-based external APIs
- **Configuration**: 
  - `servers`: Array of DNS server configurations
  - `primary_server`: Primary DNS server IP used for hostname resolution
- **Default**: Disabled for maximum security in local-only deployments
- **Use Cases**:
  - Required when external APIs use hostnames instead of IP addresses
  - Enables resolution of api.openai.com, accounts.google.com, etc.
- **Security**: Medium risk - allows specific DNS servers only when enabled
- **Recommendation**: Only enable when external_apis is enabled with hostname-based services

## Security Policy Management

### Adding Custom External APIs

To add new external services that LibreChat should be allowed to access:

#### Step 1: Enable External APIs
First, enable external APIs in `security-config.json`:

```json
"external_apis": {
  "enabled": true,
  "description": "Allow specific external APIs and OAuth providers",
  "services": [
    {"name": "OpenAI API", "host": "api.openai.com", "port": 443},
    {"name": "Anthropic API", "host": "api.anthropic.com", "port": 443},
    {"name": "Custom Weather API", "host": "api.weather.com", "port": 443},
    {"name": "Custom Search API", "host": "search.example.com", "port": 80}
  ]
}
```

**Note**: Configuration parsing uses `jq` for robust JSON handling. See `security-config.json.examples` for complete configuration examples.

#### Step 2: Required Fields
Each service entry must include:
- **`name`**: Descriptive name for the service (used in logs and tests)
- **`host`**: Hostname or domain name (e.g., "api.example.com")
- **`port`**: Port number (typically 443 for HTTPS, 80 for HTTP)

#### Step 3: Apply Changes
```bash
# Restart the NetRestrictor container to apply changes
docker compose -f docker-compose.netrestrictor.yml restart librechat-netrestrictor

# Verify the configuration is applied
docker logs LibreChat-NetRestrictor | grep "External APIs"
```

#### Step 4: Test Validation
```bash
# Run security tests to verify your new service is allowed
docker exec LibreChat-NetRestrictor /app/security/netrestrictor_security_test.sh
```

The test script will automatically read your configuration and test each configured external API.

### Configuring External DNS

When using external APIs with hostnames, you need to configure external DNS servers for hostname resolution.

#### Step 1: Enable External DNS
First, enable external DNS in `security-config.json`:

```json
"external_dns": {
  "enabled": true,
  "description": "Allow external DNS resolution for hostname lookups",
  "servers": [
    {"name": "Google Primary DNS", "ip": "8.8.8.8", "port": 53, "protocol": "udp"},
    {"name": "Cloudflare Primary DNS", "ip": "1.1.1.1", "port": 53, "protocol": "udp"},
    {"name": "Custom DNS Server", "ip": "203.0.113.1", "port": 53, "protocol": "udp"}
  ],
  "primary_server": "8.8.8.8"
}
```

#### Step 2: DNS Server Fields
Each DNS server entry must include:
- **`name`**: Descriptive name for the DNS server
- **`ip`**: IP address of the DNS server
- **`port`**: Port number (typically 53 for DNS)
- **`protocol`**: Protocol type ("udp" for standard DNS)

#### Step 3: Primary Server Configuration
- **`primary_server`**: IP address used for hostname resolution during external API setup
- Must match one of the IPs in the `servers` array
- Used by dig and nslookup commands for hostname resolution

#### Step 4: Apply and Test
```bash
# Restart the NetRestrictor container
docker compose -f docker-compose.netrestrictor.yml restart librechat-netrestrictor

# Verify DNS configuration is applied
docker logs LibreChat-NetRestrictor | grep "External DNS"

# Test hostname resolution
docker exec LibreChat-NetRestrictor /app/security/netrestrictor_security_test.sh
```

### Enabling/Disabling Categories

To modify security policies, edit `security/security-config.json`:

#### Example: Disable External API Access
```json
"external_apis": {
  "enabled": false,
  "description": "Block all external API access"
}
```

#### Example: Disable External DNS Resolution
```json
"external_dns": {
  "enabled": false,
  "description": "Block external DNS resolution - only Docker internal DNS allowed"
}
```

#### Example: Enable Only Specific Internal Services
```json
"internal_services": {
  "enabled": true,
  "services": [
    {"name": "MongoDB", "port": 27017, "protocol": "tcp"}
  ]
}
```

### Configuration Changes
1. Edit `security/security-config.json`
2. Restart the LibreChat NetRestrictor container:
   ```bash
   docker compose -f docker-compose.netrestrictor.yml restart librechat-netrestrictor
   ```
3. Run security validation:
   ```bash
   docker exec LibreChat-NetRestrictor /app/security/netrestrictor_security_test.sh
   ```

## Security Testing

### Test Script: netrestrictor_security_test.sh

The security validation script performs comprehensive testing of the NetRestrictor implementation.

#### Test Categories

##### 1. Allowed Connections (Should Succeed)
- **LibreChat Frontend** (host.docker.internal:3080)
- **OpenAI Chat Proxy** (host.docker.internal:8081)
- **MongoDB Internal** (LibreChat-MongoDB-NetRestrictor:27017)
- **Meilisearch Internal** (LibreChat-Meilisearch-NetRestrictor:7700)
- **VectorDB Internal** (LibreChat-VectorDB-NetRestrictor:5432)

##### 2. Blocked Connections (Should Fail)
- **External DNS Servers**: 8.8.8.8:53, 1.1.1.1:53
- **External HTTP/HTTPS**: google.com:80, google.com:443
- **SSH Access**: 127.0.0.1:22, 8.8.8.8:22
- **Port Scanning**: 172.17.0.1:80, 172.17.0.1:443, 172.17.0.1:22
- **Alternative DNS**: 208.67.222.222:53

##### 3. NetRestrictor Specific Blocks
- **Direct Database Bypass**: 172.17.0.1:27017
- **Direct Redis Bypass**: 172.17.0.1:6379
- **Direct PostgreSQL Bypass**: 172.17.0.1:5432
- **Direct Proxy Bypass**: 172.17.0.1:8080, 172.17.0.1:8443

##### 4. Application Functionality Tests
- **Frontend Accessibility**: HTTP GET to localhost:3080
- **API Health Check**: HTTP GET to localhost:3080/api/health
- **Login Endpoint**: HTTP GET to localhost:3080/login

#### Running Security Tests

```bash
# Run complete security validation
docker exec LibreChat-NetRestrictor /app/security/netrestrictor_security_test.sh

# Expected output: 25/25 tests passing (100% success rate)
```

#### Test Results Interpretation

- **✅ CONNECTED (Expected)**: Allowed connection succeeded
- **✅ BLOCKED (Expected)**: Blocked connection failed as intended
- **❌ CONNECTED (SECURITY BREACH!)**: Security violation - connection should be blocked
- **❌ BLOCKED (Connection Problem)**: Required connection failed

### Security Metrics

The system targets 100% security test success rate:
- **Passing Score**: 25/25 tests
- **Security Violations**: 0 unexpected connections
- **Application Functionality**: All core features operational

## Deployment

### Standard Deployment
```bash
# Start NetRestrictor-secured LibreChat
docker compose -f docker-compose.netrestrictor.yml up -d --build

# Verify security
docker exec LibreChat-NetRestrictor /app/security/netrestrictor_security_test.sh
```

### High-Security Deployment (Default Configuration)
For maximum security, the default configuration disables external API access:

1. Default configuration in `security/security-config.json`:
   ```json
   "external_apis": {"enabled": false},
   "external_dns": {"enabled": false}
   ```

2. Configure OAuth alternative (optional):
   ```yaml
   # In librechat.yaml
   registration:
     socialLogins: []  # Disable external OAuth
   ```

3. Deploy and test:
   ```bash
   docker compose -f docker-compose.netrestrictor.yml up -d --build
   docker exec LibreChat-NetRestrictor /app/security/netrestrictor_security_test.sh
   ```

This configuration provides complete network isolation with 100% test success rate.

## Troubleshooting

### Common Issues

#### 1. External API Access Required
**Symptoms**: Authentication failures, tool functionality issues
**Solution**: Enable external APIs in configuration
```json
"external_apis": {"enabled": true}
```

#### 2. Internal Service Connection Failures
**Symptoms**: Database errors, search functionality issues
**Solution**: Verify internal services are enabled and containers are healthy
```bash
docker compose -f docker-compose.netrestrictor.yml ps
```

#### 3. Security Test Failures
**Symptoms**: Tests showing unexpected connections or blocks
**Solution**: 
1. Check container networking
2. Verify iptables rules: `docker exec LibreChat-NetRestrictor iptables -L -n`
3. Review container logs: `docker logs LibreChat-NetRestrictor`

### Monitoring

#### Security Rule Status
```bash
# View active iptables rules
docker exec LibreChat-NetRestrictor iptables -L -n

# View security configuration
docker exec LibreChat-NetRestrictor cat /app/security/security-config.json
```

#### Container Health
```bash
# Check all NetRestrictor services
docker compose -f docker-compose.netrestrictor.yml ps

# View security startup logs
docker logs LibreChat-NetRestrictor | grep "NetRestrictor"
```

## Security Considerations

### Risk Assessment
- **Low Risk**: Loopback, established connections, internal services
- **Medium Risk**: Host services, DNS resolution
- **High Risk**: External APIs (HTTP/HTTPS access)

### Best Practices
1. **Principle of Least Privilege**: Only enable required categories
2. **Regular Testing**: Run security validation after changes
3. **Monitoring**: Review container logs for blocked attempts
4. **Proxy Usage**: Prefer proxy-based communication over direct external access
5. **Configuration Management**: Version control security configuration changes

### Compliance
This implementation supports various security frameworks:
- **Zero Trust Architecture**: Default deny with explicit allows
- **Defense in Depth**: Multiple security layers
- **Audit Trail**: Comprehensive logging and testing
- **Access Control**: Granular network-level restrictions

## Advanced Configuration

### Custom Security Rules
For advanced users, additional iptables rules can be added to `security/start-with-security.sh`:

```bash
# Example: Allow specific external IP
iptables -A OUTPUT -d 192.168.1.100 -j ACCEPT

# Example: Log blocked attempts
iptables -A OUTPUT -j LOG --log-prefix "NETRESTRICTOR-BLOCK: "
```

### Integration with External Security Tools
- **SIEM Integration**: Parse iptables logs for security events
- **Network Monitoring**: Monitor container network traffic
- **Compliance Scanning**: Regular security validation automation

## Support

### Documentation
- **Main Documentation**: `/LibreChat/CLAUDE.md`
- **Docker Compose**: `docker-compose.netrestrictor.yml`
- **Security Configuration**: `security/security-config.json`

### Validation
- **Security Tests**: `security/netrestrictor_security_test.sh`
- **Application Health**: Standard LibreChat health checks
- **Container Status**: Docker Compose service monitoring