# Saudi-hosted Nafath callback and gateway

This Node.js service must run on a server physically hosted in Saudi Arabia.
It proxies NSI002/NSI003 requests from the Supabase Edge Function using a
private gateway secret, fetches the NSI001 JWK, and verifies the signed callback
JWT using RS256, `kid`, issuer, audience, status, and time claims.

After verification, it atomically marks only the matching waiting transaction
as final and records Nafath verification on the existing user profile. The raw
JWT and arbitrary JWT claims are never stored. The Edge Function creates a
one-time Supabase Auth session only for the existing Aqar account linked to the
verified national ID. It does not create new accounts; a person without an
existing Aqar profile must use the current registration flow first.

## Requirements before production

- Register the exact public HTTPS callback URL with Nafath.
- Use the APP-ID, APP-KEY, JWK endpoint, issuer, and audience provided for the
  selected environment. Rotate any credentials exposed in screenshots or chat.
- The JWK request includes both the end-user IP and this host's static public IP
  in `X-Forwarded-For`.
- Keep `SUPABASE_SERVICE_ROLE_KEY` and all Nafath credentials on the server.
- Confirm with Nafath/Elm and your privacy/compliance owner that transaction
  data may be sent between this Saudi host and the configured Supabase project.
- Apply the pending database migration
  `supabase/migrations/20261115040000_nafath_nsi_standards.sql`.

## Environment

Configure these values on the Saudi host:

```env
SUPABASE_URL=https://<project>.supabase.co
SUPABASE_SERVICE_ROLE_KEY=<server-only-service-role-key>
NAFATH_BASE_URL=<approved-https-api-host>
NAFATH_APP_ID=<rotated-app-id>
NAFATH_APP_KEY=<rotated-app-key>
NAFATH_AUDIENCE=<configured-jwt-audience>
NAFATH_ISSUER=<configured-jwt-issuer>
NAFATH_SERVICE_PROVIDER_IP=<static-public-ip-of-this-host>
NAFATH_GATEWAY_SECRET=<random-secret-of-at-least-32-characters>
```

Set `NAFATH_GATEWAY_URL` and the same `NAFATH_GATEWAY_SECRET` in Supabase Edge
Function secrets. Never put Nafath credentials or the service-role key in the
Flutter app or a client `.env` file.

## Local checks

```sh
npm test
```

## Deploy with Docker Compose and Caddy

1. Copy `.env.example` to `.env` on the Saudi host and fill it there.
2. Point the domain's DNS A record at this host; allow inbound TCP ports 80/443
   for Caddy's TLS certificate.
3. Build and start the service with `docker compose up -d --build`.
4. Confirm `https://<DOMAIN>/healthz` returns `{"ok":true}`.
5. Register `https://<DOMAIN>/callback` with Nafath.
6. Confirm the callback source IP allow-list in `Caddyfile` with Nafath/Elm.
   Do not add a proxy/CDN unless real-client-IP and allow-list handling are
   verified.
7. Test approval, rejection, expiration, bad signature, wrong audience/issuer,
   transaction mismatch, and callback replay in the approved test environment.

The local source and tests do not deploy this service or provision a Saudi host.
