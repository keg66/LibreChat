#!/bin/sh

echo "🔒 LibreChat NetRestrictor Security Validation Test"
echo "=================================================="
echo "Testing COMPLETE network isolation implementation"

# Test results tracking
passed=0
failed=0
total=0

test_connection() {
    local description="$1"
    local target="$2"
    local port="$3"
    local expected="$4"
    
    total=$((total + 1))
    echo -n "Testing $description ($target:$port): "
    
    # Use shorter timeout for faster testing
    if timeout 2 nc -z "$target" "$port" 2>/dev/null; then
        if [ "$expected" = "ALLOW" ]; then
            echo "✅ CONNECTED (Expected)"
            passed=$((passed + 1))
        else
            echo "❌ CONNECTED (SECURITY BREACH!)"
            failed=$((failed + 1))
            # Log the security violation for analysis
            echo "  🚨 CRITICAL: NetRestrictor security bypassed for $target:$port" >&2
        fi
    else
        if [ "$expected" = "BLOCK" ]; then
            echo "✅ BLOCKED (Expected)"
            passed=$((passed + 1))
        else
            echo "❌ BLOCKED (Connection Problem)"
            failed=$((failed + 1))
            # Log the connection problem for analysis
            echo "  ⚠️  CONNECTION ISSUE: Cannot reach required service $target:$port" >&2
        fi
    fi
}

echo ""
echo "📊 Testing ALLOWED connections (should succeed):"
echo "------------------------------------------------"
test_connection "LibreChat Frontend" "host.docker.internal" "3080" "ALLOW"
test_connection "OpenAI Chat Proxy" "host.docker.internal" "8081" "ALLOW"
test_connection "MongoDB Internal" "LibreChat-MongoDB-NetRestrictor" "27017" "ALLOW"
test_connection "Meilisearch Internal" "LibreChat-Meilisearch-NetRestrictor" "7700" "ALLOW"
test_connection "VectorDB Internal" "LibreChat-VectorDB-NetRestrictor" "5432" "ALLOW"

echo ""
echo "🌐 Testing EXTERNAL API connections (based on security-config.json):"
echo "--------------------------------------------------------------------"

# Read external API configuration and test each configured service
if [ -f "/app/security/security-config.json" ]; then
    # Check if external APIs are enabled using jq
    external_apis_enabled=$(jq -r '.allowed_connections.external_apis.enabled // false' "/app/security/security-config.json" 2>/dev/null)
    
    if [ "$external_apis_enabled" = "true" ]; then
        # Create temporary file to store external API services
        temp_apis="/tmp/external_apis_list"
        > "$temp_apis"
        
        # Parse external APIs using jq and save to temp file
        jq -r '.allowed_connections.external_apis.services[]? | "\(.name)|\(.host)|\(.port)"' "/app/security/security-config.json" 2>/dev/null > "$temp_apis"
        
        # Now test each service from the temp file
        if [ -f "$temp_apis" ] && [ -s "$temp_apis" ]; then
            while IFS='|' read -r api_name api_host api_port; do
                # Try to resolve hostname first, then test direct IP if hostname fails
                if timeout 5 nc -z "$api_host" "$api_port" 2>/dev/null; then
                    test_connection "External API: $api_name" "$api_host" "$api_port" "ALLOW"
                else
                    # If hostname fails, try resolving to IP and test that
                    resolved_ip=$(dig +short "$api_host" @8.8.8.8 2>/dev/null | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | head -1)
                    if [ -n "$resolved_ip" ]; then
                        echo -n "Testing External API: $api_name ($api_host -> $resolved_ip:$api_port): "
                        total=$((total + 1))
                        if timeout 2 nc -z "$resolved_ip" "$api_port" 2>/dev/null; then
                            echo "✅ CONNECTED (Expected)"
                            passed=$((passed + 1))
                        else
                            echo "❌ BLOCKED (Connection Problem)"
                            failed=$((failed + 1))
                            echo "  ⚠️  CONNECTION ISSUE: Cannot reach required service $api_host:$api_port" >&2
                        fi
                    else
                        test_connection "External API: $api_name" "$api_host" "$api_port" "ALLOW"
                    fi
                fi
            done < "$temp_apis"
        fi
        
        # Clean up temp file
        rm -f "$temp_apis"
    else
        echo "External APIs are disabled in configuration - skipping external API tests"
    fi
else
    echo "Security configuration file not found - skipping external API tests"
fi

echo ""
echo "🚫 Testing BLOCKED connections (should fail):"
echo "----------------------------------------------"
test_connection "External DNS (Google)" "8.8.8.8" "53" "BLOCK"
test_connection "External DNS (Cloudflare)" "1.1.1.1" "53" "BLOCK"
test_connection "Unauthorized External HTTP" "example.com" "80" "BLOCK" 
test_connection "Unauthorized External HTTPS" "example.com" "443" "BLOCK"
test_connection "Existing Server Direct" "host.docker.internal" "3000" "BLOCK"
test_connection "Local SSH" "127.0.0.1" "22" "BLOCK"
test_connection "External SSH" "8.8.8.8" "22" "BLOCK"
test_connection "Random High Port" "8.8.4.4" "9999" "BLOCK"
test_connection "Alternative DNS" "208.67.222.222" "53" "BLOCK"
test_connection "Host Port Scan 80" "172.17.0.1" "80" "BLOCK"
test_connection "Host Port Scan 443" "172.17.0.1" "443" "BLOCK"
test_connection "Host Port Scan 22" "172.17.0.1" "22" "BLOCK"

echo ""
echo "🛡️ Testing NETRESTRICTOR SPECIFIC blocks:"
echo "----------------------------------------"
test_connection "Direct MongoDB Bypass" "172.17.0.1" "27017" "BLOCK"
test_connection "Direct Redis Bypass" "172.17.0.1" "6379" "BLOCK"
test_connection "Direct PostgreSQL Bypass" "172.17.0.1" "5432" "BLOCK"
test_connection "Direct HTTP Proxy" "172.17.0.1" "8080" "BLOCK"
test_connection "Direct HTTPS Proxy" "172.17.0.1" "8443" "BLOCK"

echo ""
echo "🌐 Testing APPLICATION functionality:"
echo "------------------------------------"
# Test LibreChat login functionality
if command -v curl >/dev/null 2>&1; then
    echo -n "Testing LibreChat frontend access: "
    if curl -s -f "http://localhost:3080/" >/dev/null 2>&1; then
        echo "✅ ACCESSIBLE (Frontend serves correctly)"
        passed=$((passed + 1))
    else
        echo "❌ INACCESSIBLE (Frontend not responding)"
        failed=$((failed + 1))
        echo "  ⚠️  APPLICATION ISSUE: LibreChat frontend not accessible" >&2
    fi
    total=$((total + 1))
    
    echo -n "Testing LibreChat API health: "
    if curl -s -f "http://localhost:3080/api/health" >/dev/null 2>&1; then
        echo "✅ HEALTHY (API responding correctly)"
        passed=$((passed + 1))
    else
        echo "❌ UNHEALTHY (API not responding)"
        failed=$((failed + 1))
        echo "  ⚠️  APPLICATION ISSUE: LibreChat API health check failed" >&2
    fi
    total=$((total + 1))
    
    echo -n "Testing LibreChat login endpoint: "
    if curl -s -f "http://localhost:3080/login" >/dev/null 2>&1; then
        echo "✅ AVAILABLE (Login page accessible)"
        passed=$((passed + 1))
    else
        echo "❌ UNAVAILABLE (Login page not accessible)"
        failed=$((failed + 1))
        echo "  ⚠️  APPLICATION ISSUE: LibreChat login page not accessible" >&2
    fi
    total=$((total + 1))
else
    echo "⚠️  curl not available - skipping application functionality tests"
fi

echo ""
echo "📋 Network Configuration Info:"
echo "------------------------------"
echo "Current user: $(whoami)"
echo "Container hostname: $(hostname)"
echo "Network interfaces:"
ip addr show 2>/dev/null | grep -E "inet " | head -5

echo ""
echo "🔒 iptables Status Check:"
echo "-------------------------"
if command -v iptables >/dev/null 2>&1; then
    echo "✅ iptables available"
    # Use -n flag to avoid DNS lookups that can hang
    echo "Active rules count: $(timeout 10 iptables -L -n | wc -l)"
    echo "Default policies:"
    timeout 10 iptables -L -n | grep -E "Chain.*policy"
else
    echo "❌ iptables not available"
fi

echo ""
echo "🏁 NetRestrictor Security Test Results:"
echo "======================================="
echo "Tests PASSED: $passed"
echo "Tests FAILED: $failed"
echo "Total Tests:  $total"

if [ $failed -eq 0 ]; then
    echo ""
    echo "🎉 ALL SECURITY TESTS PASSED!"
    echo "   🛡️  NetRestrictor-level security ACHIEVED"
    echo "   🔒 Complete network isolation confirmed"
    echo "   ✅ Score: $passed/$total (100%)"
    exit 0
else
    echo ""
    echo "⚠️  SECURITY ISSUES DETECTED!"
    echo "   🚨 $failed out of $total tests failed"
    echo "   📊 Success rate: $(( passed * 100 / total ))%"
    echo "   🔧 NetRestrictor security requires adjustment"
    exit 1
fi