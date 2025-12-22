# ---------- build stage ----------
FROM public.ecr.aws/docker/library/alpine:3.20 AS build
RUN apk add --no-cache gettext
WORKDIR /app
COPY nginx.conf.template .
COPY generate-cors-map.sh .

ARG SERVER_NAME=_
ARG POSTHOG_CLOUD_REGION=us
ARG PORT=8080
ARG CORS_ALLOWED_ORIGINS=""

ENV SERVER_NAME="${SERVER_NAME}" \
    POSTHOG_CLOUD_REGION="${POSTHOG_CLOUD_REGION}" \
    PORT="${PORT}" \
    CORS_ALLOWED_ORIGINS="${CORS_ALLOWED_ORIGINS}"

# Generate CORS origin map from comma-separated list
RUN CORS_ORIGIN_MAP=$(sh generate-cors-map.sh "$CORS_ALLOWED_ORIGINS") && \
    export CORS_ORIGIN_MAP && \
    envsubst '${SERVER_NAME} ${POSTHOG_CLOUD_REGION} ${PORT} ${CORS_ORIGIN_MAP}' \
    < nginx.conf.template > nginx.conf

# ---------- runtime stage ----------
FROM public.ecr.aws/docker/library/nginx:1.27-alpine
COPY --from=build /app/nginx.conf /etc/nginx/nginx.conf
CMD ["nginx", "-g", "daemon off;"]
