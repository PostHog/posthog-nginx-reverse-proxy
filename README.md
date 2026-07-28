# PostHog nginx reverse proxy

A small nginx container that reverse-proxies PostHog through a subdomain you own, so events
aren't dropped by ad blockers that block known analytics domains.

If you don't want to run this yourself, PostHog offers a
[managed reverse proxy](https://posthog.com/docs/advanced/proxy/managed-reverse-proxy) that needs
only a CNAME. See the [proxy docs](https://posthog.com/docs/advanced/proxy) for the full picture,
and [the nginx guide](https://posthog.com/docs/advanced/proxy/nginx) for the canonical config this
template follows.

## What it routes

`POSTHOG_CLOUD_REGION` is `us` or `eu`.

| Path        | Upstream                                    | Serves                                                                 |
| ----------- | ------------------------------------------- | ---------------------------------------------------------------------- |
| `/health`   | answered locally                            | `200 OK`, for your load balancer                                       |
| `/static/…` | `${REGION}-assets.i.posthog.com`            | `array.js` and the other SDK assets                                    |
| `/array/…`  | `${REGION}-assets.i.posthog.com`            | SDK remote config — replay conditions, flag preloading, surveys, sampling |
| everything else | `${REGION}.i.posthog.com`               | event capture, feature flags, session recordings, API                  |

The two asset paths must point at the assets host, not the ingestion host. `/static/` and
`/array/` are CDN-cached there; the ingestion host is not a CDN.

## Deploy

Build with your subdomain and region baked in:

```bash
docker build \
  --build-arg SERVER_NAME=e.yourdomain.com \
  --build-arg POSTHOG_CLOUD_REGION=us \
  --build-arg PORT=8080 \
  -t posthog-proxy .

docker run -p 8080:8080 posthog-proxy
```

Two things this container does **not** do:

- **TLS.** It listens on plain HTTP on `$PORT`. Terminate TLS in front of it (load balancer,
  Cloudflare, your platform's router). Browsers will refuse a mixed-content request from an
  HTTPS page to an HTTP proxy.
- **DNS.** Point `e.yourdomain.com` at wherever you run this.

Pick a subdomain that ad blockers won't flag — avoid `analytics`, `tracking`, `telemetry`,
`posthog`, and `ph`, or you've defeated the point.

## Point your SDK at it

Set `api_host` to your proxy and `ui_host` to PostHog, so the toolbar and in-app links keep
working:

```js
posthog.init('<your-project-api-key>', {
    api_host: 'https://e.yourdomain.com',
    ui_host: 'https://us.posthog.com', // or https://eu.posthog.com
})
```

## Verify it works

Run these against your deployed proxy. `$PROXY` is `https://e.yourdomain.com`, `$TOKEN` is your
project API key.

**1. The container is up.**

```bash
curl -s $PROXY/health
# OK
```

**2. SDK assets are served, and from the CDN.** Look for a `cf-cache-status` header — that
confirms you reached the assets host rather than falling through to ingestion:

```bash
curl -sI $PROXY/static/array.js | grep -iE 'HTTP/|content-type|cf-cache-status'
# HTTP/2 200
# content-type: application/javascript
# cf-cache-status: HIT
```

**3. Remote config is served, and also from the CDN:**

```bash
curl -sI $PROXY/array/$TOKEN/config | grep -iE 'HTTP/|content-type|cf-cache-status'
# HTTP/2 200
# content-type: application/json
# cf-cache-status: HIT
```

**4. Capture accepts events:**

```bash
curl -s -X POST $PROXY/i/v0/e/ \
  -H 'Content-Type: application/json' \
  -d '{"api_key":"'$TOKEN'","event":"proxy_check","distinct_id":"proxy-check"}'
# {"status":"Ok"}
```

**5. Feature flags respond:**

```bash
curl -s -o /dev/null -w '%{http_code}\n' -X POST "$PROXY/flags/?v=2" \
  -H 'Content-Type: application/json' \
  -d '{"api_key":"'$TOKEN'","distinct_id":"proxy-check"}'
# 200
```

**6. The end user's IP survives the hop.** This is the check that's easy to miss, because
everything above passes whether or not it's true. In PostHog, run:

```sql
SELECT properties.$ip, properties.$geoip_country_name, properties.$geoip_city_name, count()
FROM events
WHERE timestamp >= now() - INTERVAL 1 HOUR
GROUP BY 1, 2, 3
ORDER BY 4 DESC
```

You should see many different IPs. If nearly every event shares one IP — and the city is
wherever your proxy runs, not where your users are — the proxy is swallowing the client IP.
nginx does not add `X-Forwarded-For` on its own, and PostHog derives `$ip` from it. This
template sets it on every proxied location; if you've adapted the config, that's the first thing
to check.

This matters beyond skewed charts: the GeoIP transformation writes `$geoip_*` properties with
`$set`, so events carrying the proxy's IP overwrite the stored country, city, subdivision, and
timezone on each person.

**7. Finally, check a real browser.** Open your site with dev tools on the Network tab, trigger a
pageview, and confirm the request goes to your proxy subdomain and returns `200`.

## What to expect after switching

**More events, not fewer.** That's the point — requests previously blocked now get through.
PostHog's docs put the typical uplift at
[10–30%, depending on your user base](https://posthog.com/docs/advanced/proxy). How much you
actually recover depends entirely on how many of your users run a blocker, so treat a rise in
volume as the proxy working rather than as double-counting.

**Identity and history carry over unchanged.** posthog-js keys its stored state on your project
token (`ph_<token>_posthog`), not on `api_host`, so changing `api_host` doesn't reset anyone's
`distinct_id` or orphan existing persons. Returning users keep their history.

**Watch your egress bill if you self-host the proxy.** Every event, session recording, flag call,
and SDK asset now flows through your infrastructure. On platforms that bill bandwidth or
invocations this adds up.

## If you adapt this config

Two things are easy to get wrong and fail silently:

- **Forward the client IP** on every proxied location:
  ```nginx
  proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
  proxy_set_header X-Real-IP $remote_addr;
  ```
  `$proxy_add_x_forwarded_for` appends to any existing header, so the chain stays intact when a
  CDN sits in front of nginx.
- **Send `/array/` to the assets host.** Without its own location block it falls through to
  `location /` and gets served by the ingestion host. It still returns config, so nothing looks
  broken — you just lose CDN caching on a request that gates replay, surveys, and flags.
