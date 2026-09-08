FROM ubuntu:latest AS builder

ADD nginx.conf.template nginx.conf.template

RUN apt-get update \
    && apt-get install -y --no-install-recommends gettext-base \
    && rm -rf /var/lib/apt/lists/*

ARG SERVER_NAME
ARG PORT=8080
ENV PORT=$PORT
ARG POSTHOG_CLOUD_REGION

RUN envsubst '$SERVER_NAME,$POSTHOG_CLOUD_REGION,$PORT=8080' < nginx.conf.template > nginx.conf

FROM nginx:latest

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates \
    && update-ca-certificates \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder nginx.conf /etc/nginx/nginx.conf
