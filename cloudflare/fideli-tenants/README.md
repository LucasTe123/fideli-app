# Fideli tenant router

This Worker sends every first-level tenant hostname, such as
`flor.fideli.site`, to the shared Fideli frontend. The browser hostname remains
unchanged, so the frontend can resolve the business by its `public_slug`.

Cloudflare production configuration:

- DNS: proxied CNAME `*.fideli.site` to `fideli.site`.
- Worker route: `*.fideli.site/*` to `fideli-tenants`.
- Tenant responses include `X-Robots-Tag: noindex, nofollow, noarchive`.

No DNS record or Worker deployment is needed when a new business is created.
