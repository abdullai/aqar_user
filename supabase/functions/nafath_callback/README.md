# Saudi-hosted Nafath callback

This standalone Node.js service is intended to run on a server physically hosted
in Saudi Arabia. It proxies Nafath start/status requests from the Supabase Edge
Function using a private gateway secret. It accepts Elm's `requestId`, `transId`,
and signed callback `token`, retrieves Elm's RSA JWK, verifies the RS256
signature and configured issuer and audience, and atomically updates only the
matching waiting `nafath_logins` row. It never stores the raw JWT or user
attributes in Supabase.

The KSA service makes all calls to Elm so the provider sees the configured
static service-provider IP. The Supabase Edge Function records the request and
polls through this service. A successful Nafath verification is **not** by
itself a Supabase Auth session; the app must not treat it as a login until a
supported account/session flow is configured.

## Requirements before production

- Register the exact public HTTPS callback URL with Elm.
- Use the APP-ID, APP-KEY, JWK endpoint, issuer, and audience provided for the
  selected environment. The sample values are not production credentials.
- The JWK endpoint requires `X-Forwarded-For`. The original request's client IP
  is retained in `nafath_logins.client_ip`; set
  `NAFATH_SERVICE_PROVIDER_IP` to the actual static public IP of this server.
- Keep `SUPABASE_SERVICE_ROLE_KEY` on the server only.
- Confirm with the Nafath/Elm contact and your privacy/compliance owner whether
  the national ID, client IP, transaction identifiers, and status may be sent
  between the KSA host and the existing Supabase project outside Saudi Arabia.
  This service deliberately does not send the JWT or callback attributes to
  Supabase, but the current application stores the national ID and client IP in
  its Supabase project.
- Apply the additive migration
  `supabase/migrations/20261113000000_nafath_callback_ip.sql` to the existing
  Supabase database.

## Local checks

```sh
npm test
```

## Deploy with Docker Compose and Caddy

1. Copy `.env.example` to `.env`; enter real credentials only on the server.
2. Set `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`, `NAFATH_APP_ID`,
   `NAFATH_APP_KEY`, `NAFATH_AUDIENCE`, `NAFATH_ISSUER`, and the verified
   `NAFATH_SERVICE_PROVIDER_IP`. Generate a random secret of at least 32
   characters for `NAFATH_GATEWAY_SECRET`; add the same value to the Supabase
   Edge Function secret `NAFATH_GATEWAY_SECRET`. Set
   `NAFATH_GATEWAY_URL=https://<your-domain>` in Supabase. Keep the
   staging/sandbox URLs until Elm approves production credentials and endpoints.
3. Point the domain's DNS A record at this server and allow inbound TCP ports
   80 and 443 for Caddy's automatic TLS certificate.
4. Install Docker Engine and its Compose plugin from Docker's official
   instructions, then run `docker compose up -d --build`.
5. Caddy forwards `/nafath/start` and `/nafath/status` to the authenticated
   gateway, and allows `/callback` only from the two source IPs in the product
   guide (`195.170.180.7` and `195.170.180.6`). Reconfirm these IPs with Elm;
   do not put another proxy/CDN in front unless its real-client-IP handling and
   allow-list behavior are configured correctly.
6. Confirm `https://<DOMAIN>/healthz` returns `{"ok":true}`. Register
   `https://<DOMAIN>/callback` as the callback URL in the Elm portal.
7. Test a valid completion, rejection, expired transaction, wrong signature,
   wrong audience/issuer, transaction mismatch, and callback replay in the
   approved test environment before switching to production.

Never commit `.env`, display it in logs, or send its secrets in chat.
