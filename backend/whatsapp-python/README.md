# Fideli WhatsApp connector

Local Python service for separate WhatsApp Web sessions and Gemini assistants per
Fideli business. Bind to `127.0.0.1:8790`; keep this Mac running for replies.

## Run

Python 3.12+:

```sh
python3 -m venv backend/whatsapp-python/.venv
backend/whatsapp-python/.venv/bin/python -m pip install -r backend/whatsapp-python/requirements.txt
backend/whatsapp-python/.venv/bin/uvicorn app:app --app-dir backend/whatsapp-python --host 127.0.0.1 --port 8790 --no-access-log
```

In Fideli open WhatsApp for the signed-in business. Each business scans its own
QR and uses its own WhatsApp number. Existing saved sessions reconnect on service
startup. Switching dashboards does not reassign or stop another business's bot.
One WhatsApp account cannot be used by two business configurations.

## Ownership and persistence

All management routes are under `/api/whatsapp/{business_id}/...` and require
`Authorization: Bearer <Fideli Supabase user access token>`. The server validates
the token with Supabase Auth, loads that user's business with RLS, and rejects
mismatched business IDs. Verification is cached for at most 25 seconds; access
tokens are not stored on disk. Anonymous storefront visitors cannot administer
sessions. This matches the app's current `CloudStore.businessId == user.id` model.

Configure `SUPABASE_URL` and `SUPABASE_PUBLISHABLE_KEY` for another deployment.
During local development they default to the same public project settings in
`lib/config/supabase_config.dart`. No service-role key is used.

Private files live in `state/tenants/<verified-business-id>/`:

- `account.json` and `account.json.keys`: WhatsApp authentication/encryption keys.
- `config.json`: bot settings, image metadata and last verified public profile.
- `media/`: uploaded, validated images.

All `state/` files are excluded from Git. Session directories are private and
uploaded files and credentials use restrictive permissions. Keep backups private.
Images removed from the gallery become inaccessible to the bot/API; their files
are retained as local recoverable backups. The API never exposes Gemini keys or
WhatsApp account files. Revoke a session in the phone's linked-device settings.

The pre-multitenant local session can migrate only to the explicitly specified
`FIDELI_LEGACY_BUSINESS_ID` or `state/legacy-owner.json` business ID. Names alone do
not grant ownership. The existing session was bound to the verified PadelBo ID.
Original files remain as a private backup; other businesses start unlinked.

## Bot configuration

The dashboard offers Connection, Messages, Images and Instructions tabs:

- Enable/pause automatic replies to ordinary incoming messages.
- Send the configured welcome on every new message, using `{negocio}` for the
  verified business name. There is no 24-hour welcome restriction or command-only
  mode. Up to two configured images can accompany it.
- Send a separate second message containing `catalog_message` and the catalog URL.
  The catalog defaults to the actual Fideli store URL; a custom HTTPS link can
  override it. These two messages do not wait for or depend on Gemini.
- For questions beyond greetings/catalog requests, Gemini then answers using the
  business context and custom prompt.
- Up to eight JPEG/PNG/WebP images per business, compressed by the app and validated
  and re-encoded on the server. Each image has a title, caption, selection guidance,
  welcome option and enabled state. Only owned enabled images can be sent.
- Custom instructions for tone, hours, location and policies. Gemini receives
  the correct business name, category, branches, published products and catalog.
  Public products are refreshed at most once per minute for background replies.
  If fetching the catalog fails, the bot does not quote stale products/prices.
- A preview endpoint invokes Gemini and shows the response in the dashboard.
  It does not send a WhatsApp message. Save changes before previewing.

Incoming synchronized history, outgoing messages, groups, statuses, messages older
than startup and duplicate events are ignored. Replies are serialized per tenant with a bounded pending queue; consecutive
questions are accepted. The welcome and catalog are sent before any Gemini request. Temporary network/timeout and
5xx failures are retried once, with a 60-second timeout per attempt. Each prompt is
independent; no customer orders, payments or cross-business history are supplied.
The bot cannot confirm orders, payments or bookings. A shared free Gemini project
has shared quotas; quota failures are reported and never enable paid billing.

## Gemini

Set `GEMINI_API_KEY` or store the key in `state/gemini.key` with mode `0600`.
The default model is `gemini-3.1-flash-lite`, overridable through
`FIDELI_GEMINI_MODEL`. Gemini structured responses may select up to two image IDs;
the server independently checks each selection against that tenant's gallery.
Only public store context and the new incoming question are sent to Google.
Google's free-tier terms allow prompts to improve its products: use test content
while evaluating the free project.

## Checks

```sh
backend/whatsapp-python/.venv/bin/python -m unittest discover -s backend/whatsapp-python -p 'test_*.py'
```

Coverage includes the Signal signature compatibility fix, Gemini request/error
handling, business authorization, separate settings/galleries, rejection of stale
messages, owned-image dispatch and explicit legacy session ownership.

Outbound DM/media delivery validates device pre-key signatures and requires a
WhatsApp server acknowledgement. Missing recipients, encryption errors and server
rejections are surfaced rather than silently counted as successful replies.
The status panel counts server-accepted message acknowledgements separately from
incoming messages. Incoming decryption failures are also reported without logging
customer message contents or identifiers.
