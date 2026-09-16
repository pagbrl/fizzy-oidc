# AGENTS.md

Instructions for AI agents (and humans) working on this repo.

## What this is

`fizzy-oidc` is a Rails engine gem that adds OIDC single sign-on to [Fizzy](https://github.com/basecamp/fizzy) and blocks every other sign-in/signup path. Users are provisioned just-in-time from the OIDC callback; IdP groups are mapped to Fizzy boards via a YAML file.

This repo is a **plugin**. It is not a Fizzy fork. Fizzy itself lives upstream; we install this gem into a Fizzy deployment.

## Pinned Fizzy version

We are pinned to Fizzy commit **`3068c2a7`** (Rails 8.x, Ruby 3.4.8). All monkey-patches target that tree. Any time the pin moves, re-verify every file in `lib/fizzy/oidc/patches/` still has a corresponding upstream controller with the same action signatures.

## What gets monkey-patched

All five of these are prepended in `lib/fizzy/oidc/engine.rb` inside `config.to_prepare`:

| Upstream controller | Actions overridden | Effect |
|---|---|---|
| `SessionsController` | `new`, `create` | Redirect to `/auth/fizzy_oidc` |
| `SignupsController` | `new`, `create` | Redirect to `/auth/fizzy_oidc` |
| `Sessions::MagicLinksController` | `show`, `create` | Redirect to `/auth/fizzy_oidc` |
| `Signups::CompletionsController` | `new`, `create` | Redirect to `/auth/fizzy_oidc` |
| `Sessions::PasskeysController` | `create` | Redirect to `/auth/fizzy_oidc` |

`SessionsController#destroy` (logout) is intentionally left alone.

## Architecture

```
request  → omniauth_openid_connect middleware (mounted at /auth)
         → /auth/fizzy_oidc/callback
         → Fizzy::Oidc::CallbacksController#create
              → Claims.from_omniauth
              → Provisioner#call   (all inside ActiveRecord transaction)
                   ├── find_or_create Identity  (by provider+sub, email fallback)
                   ├── find_or_bootstrap Account  (first ever user → owner)
                   ├── find_or_create User
                   ├── reconcile_role (owner never demoted)
                   └── reconcile_accesses (additive + revocation within managed set)
              → start_new_session_for(identity)
              → redirect into account landing
```

Key files:

- `lib/fizzy/oidc/engine.rb` — middleware + monkey-patch wiring + migration path injection
- `lib/fizzy/oidc/config.rb` — ENV + YAML config (Singleton with `reload!` for tests)
- `lib/fizzy/oidc/claims.rb` — OmniAuth hash → normalized claims
- `lib/fizzy/oidc/provisioner.rb` — the only place that writes to Fizzy's models
- `app/controllers/fizzy/oidc/callbacks_controller.rb` — OIDC + failure endpoints

## Non-obvious behaviors to preserve

- **`Access` reconciliation is scoped.** Only boards listed in the mapping (`default_boards` + any board named in any group's `boards:`) are eligible for revocation. Manual grants and `boards.all_access = true` boards are untouched. Don't widen this scope without a real reason — it'll start clobbering things admins added by hand.
- **Owners are never demoted.** `reconcile_role` early-returns on `user.owner?`. If you change this, you'll strand single-tenant installs where the IdP doesn't know about an "owner" group.
- **Identity lookup is `(provider, sub)` first, email second.** The email fallback exists so pre-existing magic-link identities migrate cleanly on first OIDC login. Don't remove it without a migration plan.
- **The first OIDC user bootstraps the Account** via `Account.create_with_owner`. If no Account exists, they become `owner`. This is intentional for single-tenant. Multi-tenant will need explicit account selection.
- **Boards are matched by `name` within the account.** Missing boards are logged and skipped — the provisioner does not auto-create boards.

## Running tests

Tests run in a containerized Ruby env (the host may not have Ruby). SQLite `:memory:` with stub models that mirror Fizzy's interface — no real Fizzy checkout needed.

```sh
# If docker compose is available:
bin/test

# Otherwise (podman, no compose plugin):
docker build -t fizzy-oidc-dev .
docker run --rm -v "$PWD":/gem fizzy-oidc-dev
```

21 tests / 51 assertions cover Claims parsing, Config/YAML, and the full Provisioner reconciliation matrix. Stub models live in `test/test_helper.rb` and do **not** include Fizzy's `User::Accessor#grant_access_to_boards` callback — tests assert provisioner-added accesses only, not Fizzy's auto-grant for `all_access: true` boards. Keep that in mind when writing new tests.

## What's deliberately NOT here

- **No SCIM / directory sync.** Deprovisioning only happens on the user's next login. Stale users retain access indefinitely.
- **No board auto-creation.** Admins pre-create boards; the plugin just grants access.
- **No multi-tenant routing.** `Account.first` wins.
- **No RP-initiated logout.** `destroy` clears the local session only.
- **No passkey authentication.** Passkeys are blocked at the controller; re-enable only if you want a second auth path alongside OIDC.
- **No full end-to-end Docker stack yet.** Only the gem's own test env is containerized. A Fizzy + Dex + plugin compose stack is a potential follow-up.

## When upstream Fizzy changes

Before bumping the pin:

1. Diff these upstream files against the tree we pinned:
   - `app/controllers/sessions_controller.rb`
   - `app/controllers/signups_controller.rb`
   - `app/controllers/sessions/magic_links_controller.rb`
   - `app/controllers/signups/completions_controller.rb`
   - `app/controllers/sessions/passkeys_controller.rb`
   - `app/models/identity.rb` (esp. the columns we've added indices on)
   - `app/models/user.rb` and `app/models/user/role.rb` (enum values, owner semantics)
   - `app/models/account.rb` (`create_with_owner` signature)
   - `app/controllers/concerns/authentication.rb` (the `start_new_session_for` hook)
2. Run the test suite against the stub models.
3. Smoke-test against a Fizzy checkout with the gem path-mounted.

## Conventions

- Ruby 3.4.8 (matches Fizzy's `.ruby-version`). Managed via `mise`.
- Minitest. No RSpec.
- No comments unless WHY is non-obvious.
- The gemspec's `add_development_dependency` list is the source of truth for test deps — don't add a Gemfile.
