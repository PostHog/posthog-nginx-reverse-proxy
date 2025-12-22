#!/bin/sh
# Generate CORS origin map entries from comma-separated list
# Usage: ./generate-cors-map.sh "https://app.example.com,https://staging.example.com"

CORS_ORIGINS="${1:-}"

if [ -z "$CORS_ORIGINS" ]; then
    echo "        # No CORS origins configured"
    exit 0
fi

# Split by comma and generate map entries
echo "$CORS_ORIGINS" | tr ',' '\n' | while IFS= read -r origin; do
    # Trim whitespace
    origin=$(echo "$origin" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')

    if [ -n "$origin" ]; then
        # Escape dots for regex and create map entry
        escaped_origin=$(echo "$origin" | sed 's/\./\\./g')
        echo "        \"~^${escaped_origin}\$\" \$http_origin;"
    fi
done
