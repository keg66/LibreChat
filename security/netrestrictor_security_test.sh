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
echo "🚫 Testing BLOCKED connections (should fail):"
echo "----------------------------------------------"
test_connection "External DNS (Google)" "8.8.8.8" "53" "BLOCK"
test_connection "External DNS (Cloudflare)" "1.1.1.1" "53" "BLOCK"
test_connection "External HTTP (Google)" "google.com" "80" "BLOCK" 
test_connection "External HTTPS (Google)" "google.com" "443" "BLOCK"
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
    echo "Active rules count: $(iptables -L | wc -l)"
    echo "Default policies:"
    iptables -L | grep -E "Chain.*policy"
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