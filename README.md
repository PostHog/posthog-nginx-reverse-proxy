# PostHog Nginx Reverse Proxy

A lightweight nginx reverse proxy for PostHog with CORS support for multiple origins.

## Features

- Proxies PostHog static assets and main endpoints
- Configurable CORS support for multiple allowed origins
- SNI support for Cloudflare-backed endpoints
- Health check endpoint
- Dynamic DNS resolution

## Configuration

### Environment Variables / Build Args

- `SERVER_NAME`: Server name for nginx (default: `_`)
- `POSTHOG_CLOUD_REGION`: PostHog cloud region, e.g., `us` or `eu` (default: `us`)
- `PORT`: Port to listen on (default: `8080`)
- `CORS_ALLOWED_ORIGINS`: Comma-separated list of allowed origins (default: empty)

### CORS Configuration

The `CORS_ALLOWED_ORIGINS` variable accepts a comma-separated list of origins:

```bash
# Single origin
CORS_ALLOWED_ORIGINS="https://app.example.com"

# Multiple origins
CORS_ALLOWED_ORIGINS="https://app.example.com,https://staging.example.com,https://dev.example.com"

# With wildcard subdomains (use regex pattern)
CORS_ALLOWED_ORIGINS="https://.*\.example\.com"
```

## Building

### With Docker

```bash
# Single origin
docker build \
  --build-arg CORS_ALLOWED_ORIGINS="https://app.example.com" \
  -t posthog-proxy .

# Multiple origins
docker build \
  --build-arg CORS_ALLOWED_ORIGINS="https://app.example.com,https://staging.example.com" \
  -t posthog-proxy .
```

### Running

```bash
docker run -p 8080:8080 posthog-proxy
```

## Testing Locally

### 1. Test the CORS map generation script

```bash
# Test with single origin
./generate-cors-map.sh "https://app.example.com"

# Test with multiple origins
./generate-cors-map.sh "https://app.example.com,https://staging.example.com,https://dev.example.com"
```

### 2. Build the Docker image

```bash
docker build \
  --build-arg CORS_ALLOWED_ORIGINS="https://localhost:3000,https://localhost:8000" \
  -t posthog-proxy-test .
```

### 3. Run the container

```bash
docker run -p 8080:8080 posthog-proxy-test
```

### 4. Test CORS headers

```bash
# Test with allowed origin
curl -i -H "Origin: https://localhost:3000" http://localhost:8080/health

# Test with disallowed origin
curl -i -H "Origin: https://example.com" http://localhost:8080/health

# Test preflight request
curl -i -X OPTIONS \
  -H "Origin: https://localhost:3000" \
  -H "Access-Control-Request-Method: POST" \
  http://localhost:8080/decide
```

### 5. Inspect the generated config

```bash
# Extract and view the generated nginx.conf
docker run --rm posthog-proxy-test cat /etc/nginx/nginx.conf
```

## Example Output

For `CORS_ALLOWED_ORIGINS="https://app.example.com,https://staging.example.com"`, the generated map will be:

```nginx
map $http_origin $cors_allow_origin {
    default "";
    "~^https://app\.example\.com$" $http_origin;
    "~^https://staging\.example\.com$" $http_origin;
}
```

## Endpoints

- `/health` - Health check endpoint (returns 200 OK)
- `/static/*` - PostHog static assets
- `/*` - All other PostHog endpoints

## License

See LICENSE file.
