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
| `SessionsController` | `new`, `create` | Redirect to `/auth/fizzy_oidc` |
| `SignupsController` | `new`, `create` | Redirect to `/auth/fizzy_oidc` |
| `Sessions::MagicLinksController` | `show`, `create` | Redirect to `/auth/fizzy_oidc` |
| `Signups::CompletionsController` | `new`, `create` | Redirect to `/auth/fizzy_oidc` |
| `Sessions::PasskeysController` | `create` | Redirect to `/auth/fizzy_oidc` |

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
- **Board auto-creation.** Boards in the mapping must already exist in Fizzy.
- **Multi-tenant routing.** Assumes a single `Account`.
- **RP-initiated logout.**
- **End-to-end Docker stack** with Fizzy + a mock OIDC provider (Dex). Only the gem's test env is containerized today.

## Contributing

See [`AGENTS.md`](AGENTS.md) for architecture notes, non-obvious behaviors that must be preserved, and the checklist for bumping the Fizzy pin.
