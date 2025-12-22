# Changelog

## [Unreleased] - 2025-12-22

### Added
- **Multiple CORS Origins Support**: The reverse proxy now supports multiple allowed origins via a comma-separated environment variable
  - New `CORS_ALLOWED_ORIGINS` build argument (replaces `CORS_ALLOWED_ORIGIN`)
  - Build-time script `generate-cors-map.sh` to generate nginx map entries from comma-separated list
  - Support for regex patterns in origin definitions (e.g., wildcard subdomains)

### Changed
- **Breaking**: Renamed `CORS_ALLOWED_ORIGIN` to `CORS_ALLOWED_ORIGINS` (plural) to better reflect multiple origins support
- Updated nginx.conf.template to use dynamically generated CORS map
- Modified Dockerfile build process to generate CORS configuration at build time

### Documentation
- Added comprehensive README.md with usage examples
- Added TESTING.md with manual and automated testing instructions
- Added test-local.sh script for automated local testing

## Migration Guide

### From Single Origin (Old)
```dockerfile
ARG CORS_ALLOWED_ORIGIN="https://app.example.com"
```

### To Multiple Origins (New)
```dockerfile
# Single origin (still works)
ARG CORS_ALLOWED_ORIGINS="https://app.example.com"

# Multiple origins
ARG CORS_ALLOWED_ORIGINS="https://app.example.com,https://staging.example.com"
```

### Build Command Change
```bash
# Old
docker build --build-arg CORS_ALLOWED_ORIGIN="https://app.example.com" -t proxy .

# New
docker build --build-arg CORS_ALLOWED_ORIGINS="https://app.example.com,https://staging.example.com" -t proxy .
```

## Example Configurations

### Production with staging
```bash
CORS_ALLOWED_ORIGINS="https://app.turbodocx.com,https://staging.turbodocx.com"
```

### Development with local ports
```bash
CORS_ALLOWED_ORIGINS="https://localhost:3000,https://localhost:8000,http://localhost:3000"
```

### With Cloudflare Pages previews (regex)
```bash
CORS_ALLOWED_ORIGINS="https://turbodocx.com,https://.*\.turbodocx\.pages\.dev"
```
