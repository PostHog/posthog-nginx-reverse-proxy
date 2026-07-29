# nginx.conf is rendered at *build* time, so SERVER_NAME, POSTHOG_CLOUD_REGION
# and PORT are build arguments rather than runtime environment variables.
FROM nginx:1.30-alpine AS config

# `_` is nginx's catch-all: this image only ever has one server block, so
# SERVER_NAME is documentation rather than routing.
ARG SERVER_NAME=_
ARG POSTHOG_CLOUD_REGION=us
ARG PORT=8080

COPY nginx.conf.template /tmp/nginx.conf.template

# Only these three placeholders are substituted; nginx's own $variables
# (e.g. $proxy_add_x_forwarded_for) must survive untouched.
RUN envsubst '${SERVER_NAME} ${POSTHOG_CLOUD_REGION} ${PORT}' \
        < /tmp/nginx.conf.template > /tmp/nginx.conf

FROM nginx:1.30-alpine

COPY --from=config /tmp/nginx.conf /etc/nginx/nginx.conf

# Fail the build rather than the deploy if the rendered config is invalid
RUN nginx -t
