# fizzy-oidc

OIDC single sign-on for [Fizzy](https://github.com/basecamp/fizzy), with group-to-board provisioning on login.

This is a Rails engine gem that:

- Replaces Fizzy's magic-link, signup, passkey-auth and signup-completion flows with OIDC. OIDC is the only way in.
- Provisions users just-in-time on first login.
- Maps IdP groups to Fizzy boards via a YAML config, reconciled on every login.
- Maps a configurable "admin group" claim to Fizzy's `admin` role.

Single-tenant: the first OIDC user creates the account and becomes `owner`. Every subsequent user is added to that same account.

## Compatibility

Pinned to Fizzy commit `3068c2a7` (Rails 8.x, Ruby 3.4). Monkey-patches five Fizzy controllers; expect to revisit on Fizzy upgrades. See [`AGENTS.md`](AGENTS.md) for the upgrade checklist.

## Install into Fizzy

In Fizzy's `Gemfile`:

```ruby
gem "fizzy-oidc", github: "pagbrl/fizzy-oidc"
```

Then:

```sh
bundle install
bin/rails db:migrate
```

## Configure

Environment variables:

```
FIZZY_OIDC_ISSUER=https://id.example.com
FIZZY_OIDC_CLIENT_ID=fizzy
FIZZY_OIDC_CLIENT_SECRET=...
FIZZY_OIDC_REDIRECT_URI=https://fizzy.example.com/auth/fizzy_oidc/callback
FIZZY_OIDC_SCOPES="openid email profile groups"
FIZZY_OIDC_GROUPS_CLAIM=groups
```

Copy `config/fizzy_oidc.example.yml` to `config/fizzy_oidc.yml` in the Fizzy app and edit it:

```yaml
account:
  name: "Acme"
mappings:
  admin_group: "fizzy-admins"
  default_boards: ["General"]
  groups:
    eng-team:
      boards: ["Backend", "Infra"]
    design:
      boards: ["Design"]
```

- `admin_group`: users with this group claim get the `admin` role (the first user is always `owner`).
- `default_boards`: every logged-in user gets access to these.
- `groups`: per-group board grants. Boards are matched by name within the account. Missing boards are logged and skipped (not created).

Boards marked `all_access: true` are granted automatically by Fizzy on user creation and are left untouched by this plugin. Only boards listed in the mapping are reconciled (added when earned, revoked when the user no longer has the group).

## Creating members before their first login

An outside system (for us, the community manager) can create a member before
they ever log in, so it can put them on boards straight away:

```
POST /:account_slug/oidc/users
Authorization: Bearer <personal access token of an admin, with write permission>
Content-Type: application/json

{"email_address": "alice@example.com", "name": "Alice"}
```

It answers `201` with the new user (`id`, `name`, `role`, `active`,
`email_address`), or `200` with the existing one — the call is idempotent. The
member is created verified, with the `member` role and no OIDC subject. On their
first login the identity is found by email, linked to the subject, and the user
keeps every board access granted in the meantime.

## What happens on each login

1. Receives the OIDC callback at `/auth/fizzy_oidc/callback`.
2. Finds or creates the `Identity` by `(oidc_provider, oidc_subject)`, falling back to email for first-time migration from magic-link users.
3. Finds or bootstraps the `Account`. The first-ever OIDC user becomes its owner.
4. Finds or creates the `User` in that account linked to the identity.
5. Updates the user's role: `owner` is never downgraded; otherwise `admin` if in `admin_group`, else `member`.
6. Reconciles `Access` records against the mapping (additive for earned groups, destructive for revoked groups within the managed set).
7. Starts a Fizzy session and redirects into the app.

## What it monkey-patches

| Upstream controller | Actions | Effect |
|---|---|---|
| `SessionsController` | `new`, `create` | `new` renders a sign-in button that POSTs to `/auth/fizzy_oidc`, `create` redirects to it |
| `SignupsController` | `new`, `create` | Redirect to the sign-in page |
| `Sessions::MagicLinksController` | `show`, `create` | Redirect to the sign-in page |
| `Signups::CompletionsController` | `new`, `create` | Redirect to the sign-in page |
| `Sessions::PasskeysController` | `create` | Redirect to the sign-in page |

Logout (`SessionsController#destroy`) is untouched.

## Development

### Requirements

- Ruby 3.4.8 (matches Fizzy's `.ruby-version`) — `mise install` picks it up from `.mise.toml`.
- Or: Docker, and nothing else.

### Local setup (native)

```sh
bin/setup       # mise install + bundle install
bundle exec rake test
```

### Local setup (Docker)

A minimal containerized env is provided for running the gem's tests — useful if you don't have Ruby installed.

```sh
# With docker compose plugin:
bin/test                 # runs the test suite
bin/shell                # interactive shell in the dev image

# Without the compose plugin (e.g. plain podman):
docker build -t fizzy-oidc-dev .
docker run --rm -v "$PWD":/gem fizzy-oidc-dev
```

The image is Ruby 3.4.8-slim with build tools + SQLite. Bundler installs into a named volume so rebuilds don't refetch gems.

### Local stack (Fizzy + Keycloak)

`compose.dev.yml` boots a real Fizzy checkout (pinned to `3068c2a7`) with this gem mounted in via `path:`, next to a Keycloak with the `fizzy` realm imported. This is the environment for step 3 of the upgrade checklist in [`AGENTS.md`](AGENTS.md) — the gem's own test suite runs against stubs and proves nothing about real Fizzy.

```sh
docker compose -f compose.dev.yml up --build
```

- Fizzy: http://localhost:3000
- Keycloak: http://localhost:8080 (admin / admin), realm `fizzy`
- Test users: `alice` (group `fizzy-admins`) and `bob` (group `eng-team`), password `password`

Set `KEYCLOAK_PORT` if 8080 is taken: `KEYCLOAK_PORT=18080 docker compose -f compose.dev.yml up`.

Fizzy runs inside Keycloak's network namespace, so `localhost:8080` resolves to Keycloak both in your browser and inside the Fizzy container. The issuer has to be spelled the same on both sides or issuer validation fails — this is the usual `localhost` vs Docker-service-name trap, and that is why both published ports hang off the `keycloak` service.

Two of the three things that blocked signing in here are fixed in the gem: the OIDC columns are added even when `db:prepare` loads Fizzy's schema (`Schema.ensure!`), and the sign-in page is a button that POSTs to `/auth/fizzy_oidc`, checked by a real controller (`RequestValidation`) instead of `omniauth-rails_csrf_protection`, which breaks on Fizzy's Rails 8.2. The third is this stack's alone: discovery of an `http://` issuer is attempted over TLS (`SWD.url_builder` defaults to `URI::HTTPS`), so a local `http://localhost` Keycloak still needs a hand workaround. An `https` issuer, as in production, signs in end to end.

The database starts empty (no Fizzy seeds), so the first OIDC login bootstraps the account and becomes its `owner`. Boards named in `dev/fizzy_oidc.yml` are not created for you — the plugin never creates boards — so create `General`, `Backend` and `Infra` in the UI and log in again to see the mapping reconcile.

What is where:

| File | What |
|---|---|
| `compose.dev.yml` | The stack. Separate from `docker-compose.yml`, which is the gem's unit-test env — `bin/test` is untouched. |
| `dev/Dockerfile.fizzy` | Clones Fizzy at the pin, appends `gem "fizzy-oidc", path: "/gem"` to its Gemfile, bundles. |
| `dev/fizzy-entrypoint` | Waits for Keycloak, prepares the database, starts Puma. |
| `dev/fizzy_oidc.yml` | The group-to-board mapping, mounted at `config/fizzy_oidc.yml`. |
| `dev/keycloak/fizzy-realm.json` | Realm export: client `fizzy` (confidential, direct access grants off), client scope `groups` (Group Membership mapper, full path off, in ID/access/userinfo), groups, test users. Regenerate by configuring a live Keycloak and re-exporting; a hand-written `clientScopes` block replaces Keycloak's built-in scopes instead of adding to them. |

The client secret in the realm and the users' passwords are local-only fixtures. Nothing in this stack is reachable from outside your machine.

The realm also carries a second client, `smoke`, public and with direct access grants on. It exists so a `curl` can fetch a token without a browser — the `fizzy` client deliberately keeps direct access grants off:

```sh
docker compose -f compose.dev.yml exec fizzy bash -c 'T=$(curl -s -d client_id=smoke -d username=alice -d password=password -d grant_type=password -d "scope=openid email profile groups" "$FIZZY_OIDC_ISSUER/protocol/openid-connect/token" | ruby -rjson -e "puts JSON.parse(STDIN.read)[\"access_token\"]"); curl -s -H "Authorization: Bearer $T" "$FIZZY_OIDC_ISSUER/protocol/openid-connect/userinfo"'
```

### Tests

Minitest, SQLite `:memory:`, stub models that mirror Fizzy's interface — no Fizzy checkout needed to run the suite. See `test/test_helper.rb` for the schema and model stubs.

```
21 runs, 51 assertions, 0 failures, 0 errors, 0 skips
```

Coverage:

- `test/fizzy/oidc/claims_test.rb` — OmniAuth hash parsing, configurable groups claim, missing-claim validation.
- `test/fizzy/oidc/config_test.rb` — ENV + YAML loading, `group_boards` / `all_group_boards` / `admin_group` / `default_boards`.
- `test/fizzy/oidc/provisioner_test.rb` — full reconciliation matrix: first-login bootstrap, role promotion/demotion, owner protection, board grants and revocations, `all_access` untouched, unknown boards skipped, email-fallback identity migration.

## Not included (yet)

- **SCIM / directory sync.** Deprovisioning only happens on a user's next login. Users who stop logging in retain stale access; run a periodic review or add SCIM later.
- **Board auto-creation.** Boards in the mapping must already exist in Fizzy. Create them through Fizzy's own API (`POST /:account_slug/boards`).
- **Multi-tenant routing.** Assumes a single `Account`.
- **RP-initiated logout.**

## Contributing

See [`AGENTS.md`](AGENTS.md) for architecture notes, non-obvious behaviors that must be preserved, and the checklist for bumping the Fizzy pin.
