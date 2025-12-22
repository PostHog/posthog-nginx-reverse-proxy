#!/bin/bash
# Local testing script for PostHog reverse proxy with multiple CORS origins

set -e

echo "=== Testing PostHog Reverse Proxy with Multiple CORS Origins ==="
echo ""

# Test origins
TEST_ORIGINS="https://localhost:3000,https://localhost:8000,https://app.example.com"

echo "1. Testing CORS map generation script..."
echo "   Origins: $TEST_ORIGINS"
echo ""
./generate-cors-map.sh "$TEST_ORIGINS"
echo ""

echo "2. Building Docker image..."
docker build \
  --build-arg CORS_ALLOWED_ORIGINS="$TEST_ORIGINS" \
  -t posthog-proxy-test \
  .
echo ""

echo "3. Inspecting generated nginx.conf..."
echo "   Looking for CORS map configuration:"
echo ""
docker run --rm posthog-proxy-test cat /etc/nginx/nginx.conf | grep -A 10 "map \$http_origin"
echo ""

echo "4. Starting container on port 8080..."
docker run -d --name posthog-proxy-test -p 8080:8080 posthog-proxy-test
echo "   Container started. Waiting 2 seconds..."
sleep 2
echo ""

echo "5. Testing CORS headers..."
echo ""

# Test 1: Health check
echo "   Test 1: Health check (no origin)"
curl -s -o /dev/null -w "   Status: %{http_code}\n" http://localhost:8080/health
echo ""

# Test 2: Allowed origin
echo "   Test 2: Request with allowed origin (https://localhost:3000)"
curl -s -i -H "Origin: https://localhost:3000" http://localhost:8080/health | grep -i "access-control"
echo ""

# Test 3: Another allowed origin
echo "   Test 3: Request with allowed origin (https://app.example.com)"
curl -s -i -H "Origin: https://app.example.com" http://localhost:8080/health | grep -i "access-control"
echo ""

# Test 4: Disallowed origin
echo "   Test 4: Request with disallowed origin (https://evil.com)"
RESULT=$(curl -s -i -H "Origin: https://evil.com" http://localhost:8080/health | grep -i "access-control-allow-origin" || echo "No CORS header (expected)")
echo "   $RESULT"
echo ""

# Test 5: Preflight request
echo "   Test 5: OPTIONS preflight request"
curl -s -o /dev/null -w "   Status: %{http_code}\n" -X OPTIONS \
  -H "Origin: https://localhost:3000" \
  -H "Access-Control-Request-Method: POST" \
  http://localhost:8080/health
echo ""

echo "6. Cleaning up..."
docker stop posthog-proxy-test
docker rm posthog-proxy-test
echo ""

echo "=== All tests completed! ==="
echo ""
echo "To manually test, run:"
echo "  docker run -d -p 8080:8080 posthog-proxy-test"
echo "  curl -i -H 'Origin: https://localhost:3000' http://localhost:8080/health"
