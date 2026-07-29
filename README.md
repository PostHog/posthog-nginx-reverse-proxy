# PostHog nginx reverse proxy

A minimal nginx container that reverse proxies PostHog Cloud from a subdomain you
control, so SDK traffic is sent to (for example) `ph.example.com` instead of
`us.i.posthog.com`. See [Deploy a reverse proxy](https://posthog.com/docs/advanced/proxy)
for why you'd want that.

It fronts two PostHog hosts and nothing else:

| Path      | Upstream                                   |
| --------- | ------------------------------------------ |
| `/static` | `<region>-assets.i.posthog.com` (`array.js`, toolbar, recorder) |
| `/`       | `<region>.i.posthog.com` (event capture, flags, replay uploads) |

Because it only proxies PostHog's own ingest and asset hosts, it is never in the
request path for your own application's pages.

## Build and run

The config is rendered from `nginx.conf.template` **at image build time**, so
these are build arguments, not runtime environment variables:

| Build arg              | Default | Notes                                                    |
| ---------------------- | ------- | -------------------------------------------------------- |
| `POSTHOG_CLOUD_REGION` | `us`    | `us` or `eu` — must match your PostHog Cloud region       |
| `PORT`                 | `8080`  | Port nginx listens on, baked into the config              |
| `SERVER_NAME`          | `_`     | Cosmetic; there is only one server block, so it matches all hostnames |

```bash
docker build \
  --build-arg POSTHOG_CLOUD_REGION=us \
  --build-arg SERVER_NAME=ph.example.com \
  -t posthog-proxy .

docker run -p 8080:8080 posthog-proxy
curl -i http://localhost:8080/health
```

If you deploy somewhere that injects a `PORT` at runtime (Railway, Heroku, Cloud
Run), pass that same value as `--build-arg PORT=...` — changing `PORT` in the
environment after the image is built has no effect.

## TLS is not handled here — terminate it in front

`nginx.conf.template` only has `listen ${PORT};`. **This container speaks plain
HTTP and holds no certificate.** Browsers must never reach it directly over
`http://`; something in front has to terminate TLS for your proxy subdomain:

- **Recommended:** a platform that terminates TLS for you (Fly.io, Railway,
  Render, Cloud Run, an ALB/ingress with an ACM/cert-manager certificate) and
  forwards to this container over HTTP on `${PORT}`.
- **Cloudflare in front:** create a **proxied** (orange-cloud) DNS record for the
  proxy subdomain, then pick the SSL/TLS encryption mode to match your origin:
  - Origin is behind a platform/load balancer that serves valid HTTPS →
    **Full (strict)**.
  - Cloudflare connects straight to this container on plain HTTP → **Flexible**.
    This is the only case where Flexible is correct, and it leaves the
    Cloudflare→origin hop unencrypted, so prefer the option above.

  A mismatch here (Full/Full strict pointed at a plain-HTTP origin) surfaces as
  Cloudflare 5xx error pages — a `525`/`526` on the proxy subdomain, not a
  browser certificate warning on your app's own pages.

Whatever sits in front, keep the requirements from the
[proxy reference](https://posthog.com/docs/advanced/proxy/proxy-reference):
allow `GET` and `POST` on every path, and allow request bodies up to 64 MB
(session recordings are large — nginx here is already configured for that).

## Client IP and geolocation

PostHog derives an event's location from the client IP it receives, so the proxy
forwards the original client on every request:

```nginx
proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
proxy_set_header X-Real-IP $client_ip;
proxy_set_header X-Forwarded-Proto $forwarded_proto;
```

`$client_ip` is the first address in the inbound `X-Forwarded-For` when there is
one, falling back to the connecting peer. That way a CDN hop in front of this
proxy doesn't become the reported location — but it only works if that CDN sets
`X-Forwarded-For` itself. Cloudflare's proxy does; a custom Cloudflare Worker
has to [set it from `CF-Connecting-IP`](https://posthog.com/docs/advanced/proxy/cloudflare).
If every event suddenly geolocates to one place, that header is the first thing
to check.

## Health check

`GET /health` makes a cheap `HEAD` request to `<region>.i.posthog.com` before
answering, so it reflects whether this container can actually reach PostHog:

- `200 OK` — nginx is up and the ingest host is reachable
- `503 upstream unreachable` — DNS, egress or TLS to PostHog is broken

Point your platform's health check at it. It is deliberately not cached.

## Configuring the SDK

```js
posthog.init('<ph_project_api_key>', {
    api_host: 'https://ph.example.com',
    ui_host: 'https://us.posthog.com', // or https://eu.posthog.com
})
```

`ui_host` is required, otherwise the toolbar and replay player link to the wrong
place. Avoid obvious hostnames and paths such as `analytics`, `tracking`,
`telemetry` or `posthog` — tracking blockers match on those.

## Testing config changes locally

`nginx.conf.template` is not valid nginx config on its own; render it first:

```bash
SERVER_NAME=localhost POSTHOG_CLOUD_REGION=us PORT=8080 \
  envsubst '${SERVER_NAME} ${POSTHOG_CLOUD_REGION} ${PORT}' \
  < nginx.conf.template > /tmp/nginx.conf
nginx -t -c /tmp/nginx.conf
```

The image build runs `nginx -t` too, so an invalid config fails the build rather
than the deploy.
