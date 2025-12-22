# Testing Guide

## Quick Test Without Docker

### 1. Test the CORS map generation

```bash
# Test with multiple origins
./generate-cors-map.sh "https://app.example.com,https://staging.example.com,https://dev.example.com"

# Expected output:
#         "~^https://app\.example\.com$" $http_origin;
#         "~^https://staging\.example\.com$" $http_origin;
#         "~^https://dev\.example\.com$" $http_origin;
```

### 2. Verify the nginx config template substitution manually

```bash
# Set environment variables
export SERVER_NAME="_"
export POSTHOG_CLOUD_REGION="us"
export PORT="8080"
export CORS_ORIGIN_MAP=$(./generate-cors-map.sh "https://localhost:3000,https://localhost:8000")

# Generate nginx.conf
envsubst '${SERVER_NAME} ${POSTHOG_CLOUD_REGION} ${PORT} ${CORS_ORIGIN_MAP}' < nginx.conf.template > test-nginx.conf

# View the generated config
cat test-nginx.conf | grep -A 10 "map \$http_origin"

# Cleanup
rm test-nginx.conf
```

## Full Docker Test

### Option 1: Automated Test Script

```bash
./test-local.sh
```

This will:
- Test the CORS map generation
- Build a Docker image with test origins
- Start the container
- Test various CORS scenarios
- Clean up

### Option 2: Manual Docker Testing

```bash
# 1. Build with your origins
docker build \
  --build-arg CORS_ALLOWED_ORIGINS="https://localhost:3000,https://app.example.com" \
  -t posthog-proxy-test .

# 2. Verify the generated config
docker run --rm posthog-proxy-test cat /etc/nginx/nginx.conf

# 3. Start the container
docker run -d --name posthog-test -p 8080:8080 posthog-proxy-test

# 4. Test health endpoint
curl -i http://localhost:8080/health

# 5. Test with allowed origin
curl -i -H "Origin: https://localhost:3000" http://localhost:8080/health

# 6. Test with disallowed origin (should not return Access-Control-Allow-Origin)
curl -i -H "Origin: https://evil.com" http://localhost:8080/health

# 7. Test OPTIONS preflight
curl -i -X OPTIONS \
  -H "Origin: https://localhost:3000" \
  -H "Access-Control-Request-Method: POST" \
  http://localhost:8080/health

# 8. Cleanup
docker stop posthog-test
docker rm posthog-test
```

## Expected Results

### Allowed Origin Request

```
HTTP/1.1 200 OK
Access-Control-Allow-Origin: https://localhost:3000
Access-Control-Allow-Methods: GET, OPTIONS
Access-Control-Allow-Headers: Content-Type, Authorization
Access-Control-Max-Age: 86400
Vary: Origin
Content-Type: text/plain
```

### Disallowed Origin Request

```
HTTP/1.1 200 OK
Content-Type: text/plain

# Note: NO Access-Control-Allow-Origin header
```

### OPTIONS Preflight Request

```
HTTP/1.1 204 No Content
Access-Control-Allow-Origin: https://localhost:3000
Access-Control-Allow-Methods: GET, OPTIONS
Access-Control-Allow-Headers: Content-Type, Authorization
Access-Control-Max-Age: 86400
Vary: Origin
```

## Common Test Scenarios

### Single Origin
```bash
CORS_ALLOWED_ORIGINS="https://app.example.com"
```

### Multiple Origins
```bash
CORS_ALLOWED_ORIGINS="https://app.example.com,https://staging.example.com,https://dev.example.com"
```

### Wildcard Subdomain (regex pattern)
```bash
CORS_ALLOWED_ORIGINS="https://.*\.example\.com"
```

### Mixed (exact + wildcard)
```bash
CORS_ALLOWED_ORIGINS="https://app.example.com,https://.*\.preview\.example\.com"
```

## Troubleshooting

### CORS header not appearing for allowed origin

Check the generated nginx.conf map block:
```bash
docker run --rm posthog-proxy-test cat /etc/nginx/nginx.conf | grep -A 5 "map \$http_origin"
```

### Docker build fails

Ensure the script has execute permissions:
```bash
chmod +x generate-cors-map.sh
```

### Testing with real PostHog endpoints

Replace `localhost:8080` with your proxy URL and test actual PostHog endpoints:
```bash
curl -i -H "Origin: https://yourapp.com" https://your-proxy.com/decide
```
