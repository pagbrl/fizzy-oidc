# AGENTS.md

Instructions for AI agents (and humans) working on this repo.

## What this is

`fizzy-oidc` is a Rails engine gem that adds OIDC single sign-on to [Fizzy](https://github.com/basecamp/fizzy) and blocks every other sign-in/signup path. Users are provisioned just-in-time from the OIDC callback; IdP groups are mapped to Fizzy boards via a YAML file.

This repo is a **plugin**. It is not a Fizzy fork. Fizzy itself lives upstream; we install this gem into a Fizzy deployment.

## Pinned Fizzy version

We are pinned to Fizzy commit **`3068c2a7`** (Rails 8.x, Ruby 3.4.8). All monkey-patches target that tree. Any time the pin moves, re-verify every file in `lib/fizzy/oidc/patches/` still has a corresponding upstream controller with the same action signatures.

## What gets monkey-patched

All of these are prepended in `lib/fizzy/oidc/engine.rb` inside `config.to_prepare`:

| Upstream class | Methods overridden | Effect |
|---|---|---|
| `SessionsController` | `new`, `create`, `destroy` | `new` renders the sign-in button, `create` redirects to it, `destroy` ends the SSO session too |
| `SignupsController` | `new`, `create` | Redirect to the sign-in page |
| `Sessions::MagicLinksController` | `show`, `create` | Redirect to the sign-in page |
| `Signups::CompletionsController` | `new`, `create` | Redirect to the sign-in page |
| `Sessions::PasskeysController` | `create` | Redirect to the sign-in page |
| `Cards::AssignmentsController` | `new` | Loads the card's assignees once, so the picker's checkmarks cost no query per board member |
| `User::Filtering` | `users`, `cache_key`, plus `assignee_choices`, `creator_choices`, `closer_choices`, `author_choices` | Each person filter offers the active people who hold its role on a card in scope ("assigned to": assignees, "added by": creators, "closed by": closers; Activity's person filter, which filters events by author: the authors of timeline events), one SQL subquery each (the authors one is about 8 ms on 30,000 events, through the board and action index); the scope is the board on a board page, the boards picked in the filter, else the viewer's boards; people already picked stay listed; the cache key adds the cards in scope |
| `My::MenusController` | `show` | The menu's people are the active assignees and creators of cards on the viewer's boards; the etag adds those cards (their count and latest `updated_at`: a new card or an assignment, which touches its card, changes it) |
| `BoardsController` | `show`, `edit`, `update` | `show` hands the board to the filter; `edit` (a rewrite, not `super`) lists the members, the people ticked in an earlier search, and a name/email search of at most 20 non-members (`Fizzy::Oidc::People`, folded in Ruby: case and accents ignored, `%` and `_` literal), then the same for project groups (`Fizzy::Oidc::ProjectGroups`), except that with no query it offers up to 20 groups, the board's namesake first; `update` renders a search instead of saving when a Search button submitted the form; an HTML save adds the members only a group lets in to `user_ids[]` (a JSON save does not: `user_ids` wins), then in one transaction calls `super`, drops the group grants of `personal_user_ids`, and attaches the ticked groups (after, or upstream's revise would revoke whom a new group just let in) |
| `Access`, `Board`, `User` | `after_destroy` (included concerns) | Drop the gem's rows: an access's group grant, a board's attached groups and grants (Fizzy deletes its accesses without callbacks), a user's memberships |
| `AvatarsHelper` | `avatar_image_tag` | `loading: "lazy"`, the caller's options win |
| `Users::AvatarsController` | `show` | The redirect to someone else's uploaded avatar is cached 5 minutes, privately; your own stays uncached so a new photo shows at once |

Six views are overridden: `ApplicationController.prepend_view_path` puts `app/views/fizzy/oidc/overrides` first. `filters/settings/_assignees`, `_creators`, `_closers` and `events/index/filter/_user` are upstream's partials with `user_filtering.users` swapped for the role list. `boards/edit/_users.html.erb` is a copy of upstream's partial. It renders every member as a checked toggle, because upstream's `#update` revokes any member missing from `user_ids[]`. The search field, its Search button and the `board_access_search_results` frame sit inside the access menu under `toggler__visible-when-off`, so they hide when "Everyone" is on. The Search button belongs to the board's form (`name="search_people"`, `data-turbo-frame`), so a search posts the people already ticked and they come back ticked; Enter in the field clicks it through Fizzy's `clicker` controller, and a hidden submit button placed first keeps Enter elsewhere a save. Re-diff it against upstream's partial when the pin moves, then run `dev/board_access_smoke.rb`. `boards/show.json.jbuilder` is upstream's plus `group_user_ids`, which the community manager reads (contract in the README).

`SessionsController#destroy` ends Fizzy's session, then sends the browser to the IdP's `end_session_endpoint` (read from discovery) with the `id_token_hint` kept at login and a `post_logout_redirect_uri` back to the sign-in page. If discovery fails, it falls back to Fizzy's own local logout.

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
                   ├── reconcile_accesses (additive + revocation within managed set)
                   └── ProjectGroups.sync_member (claim's project groups → memberships → group grants)
              → start_new_session_for(identity)
              → redirect into account landing
```

Key files:

- `lib/fizzy/oidc/engine.rb` — middleware + monkey-patch wiring + migration path injection
- `lib/fizzy/oidc/config.rb` — ENV + YAML config (Singleton with `reload!` for tests)
- `lib/fizzy/oidc/claims.rb` — OmniAuth hash → normalized claims
- `lib/fizzy/oidc/provisioner.rb` — the only place that writes to Fizzy's models
- `lib/fizzy/oidc/precreator.rb` — creates a member before their first login
- `lib/fizzy/oidc/project_groups.rb` — project groups: memberships at login, attach/detach on a board, the grants they make; models in `app/models/fizzy/oidc/`, group toggles in `app/views/fizzy/oidc/boards/`
- `lib/fizzy/oidc/logout.rb` — the IdP end-session URL the patched `destroy` redirects to
- `app/controllers/fizzy/oidc/callbacks_controller.rb` — OIDC + failure endpoints
- `app/controllers/fizzy/oidc/users_controller.rb` — `GET /:account_slug/oidc/users?email=` (one active member by address, 404 otherwise), `POST /:account_slug/oidc/users` (the Precreator) and `PATCH /:account_slug/oidc/users/:id` (rewrite the identity's email), behind Fizzy's own bearer-token auth and `ensure_admin`

## Non-obvious behaviors to preserve

- **`Access` reconciliation is scoped.** Only boards listed in the mapping (`default_boards` + any board named in any group's `boards:`) are eligible for revocation. Manual grants and `boards.all_access = true` boards are untouched. Don't widen this scope without a real reason — it'll start clobbering things admins added by hand.
- **Owners are never demoted.** `reconcile_role` early-returns on `user.owner?`. If you change this, you'll strand single-tenant installs where the IdP doesn't know about an "owner" group.
- **Identity lookup is `(provider, sub)` first, email second.** The email fallback exists so pre-existing magic-link identities migrate cleanly on first OIDC login. Don't remove it without a migration plan.
- **The first OIDC user bootstraps the Account** via `Account.create_with_owner`. If no Account exists, they become `owner`. This is intentional for single-tenant. Multi-tenant will need explicit account selection.
- **The OIDC columns do not rely on the migration alone.** On a fresh database `db:prepare` loads Fizzy's schema and marks every older migration as run, so once Fizzy's schema version passed `20260412000001` (pin `3068c2a7`) a new install never got them. `Schema.ensure!` runs after `db:prepare`, `db:migrate` and `db:schema:load` (`engine.rb`, `rake_tasks`). Anything the gem adds to Fizzy's tables goes there, not in a migration only — `sessions.oidc_id_token` included.
- **The sign-in page is a POST button, and CSRF is checked by a real controller.** OmniAuth 2 answers a GET on `/auth/fizzy_oidc` with a 404, so the patched `SessionsController#new` renders `app/views/fizzy/oidc/sessions/new.html.erb` and every other patch redirects there. `RequestValidation` runs `ForgeryChecksController`'s `protect_from_forgery`; do not bring back `omniauth-rails_csrf_protection` (1.0.2 calls into a missing `action_name` on Rails 8.2, 2.0.1 loads `ActionController::Base` at require time and Fizzy no longer boots), and do not define a controller under `lib/` for the same reason.
- **Every page widens `form-action` to the issuer's origin.** Fizzy's CSP says `form-action 'self'` and browsers enforce it on the redirects after a form POST, so without it the sign-in button's POST stops before reaching the IdP, and so does the sign-out button in the menu of every page. `ApplicationController` gets it (`engine.rb`).
- **The ID token is kept on Fizzy's session** (`sessions.oidc_id_token`, set in the callback) so logout can send it as `id_token_hint` and skip the IdP's "log out?" screen. A session opened before the column existed has none: its logout sends `client_id` instead and the IdP asks once.
- **Pre-created members are linked by email on first login.** `Precreator` makes an identity with no OIDC subject; the Provisioner's email fallback is what attaches the subject to it. Removing that fallback strands every pre-created member.
- **A group only takes back what it gave.** `oidc_group_grants` records the accesses a project group created; an access that existed before is never recorded and never revoked by group logic. On `all_access` boards revocation keeps the access, as `Board::Accessible#revoke_from` does, but still deletes the grant: left behind, it would revoke an access the admins kept once the board is restricted again. A member only a group lets in is locked on the access page and re-added to `user_ids[]` by an HTML `update`, because the next login would re-grant anyway. A JSON `update` does not: the community manager sends the full `user_ids` and knows memberships fresher than the last login, and `personal_user_ids` is how it turns a group's access into a personal one. Do not attach a group to a board the YAML mapping manages: config reconciliation revokes any access there it does not grant, the group's too. It runs first at login, so the group grants back in the same login, but a member leaving the group loses a board the mapping also grants until their next login.
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

The suite covers Claims parsing, Config/YAML, the Precreator, `Schema.ensure!`, the logout URL and the full Provisioner reconciliation matrix. Stub models live in `test/test_helper.rb` and do **not** include Fizzy's `User::Accessor#grant_access_to_boards` callback — tests assert provisioner-added accesses only, not Fizzy's auto-grant for `all_access: true` boards. Keep that in mind when writing new tests.

## What's deliberately NOT here

- **No SCIM / directory sync.** Deprovisioning only happens on the user's next login. Stale users retain access indefinitely.
- **No board auto-creation.** Admins pre-create boards; the plugin just grants access.
- **No multi-tenant routing.** `Account.first` wins.
- **No back-channel logout.** Signing out elsewhere does not end Fizzy's session; only Fizzy's own logout reaches the IdP.
- **No passkey authentication.** Passkeys are blocked at the controller; re-enable only if you want a second auth path alongside OIDC.

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
   - `app/controllers/boards_controller.rb` (our `edit` is a copy, not `super`; `update` must still revoke members missing from `user_ids[]`), and `app/views/boards/show.json.jbuilder` (copied into `app/views/fizzy/oidc/overrides/boards/`)
   - `app/models/board/accessible.rb` (`revoke_from` skips `all_access`, `has_many :accesses, dependent: :delete_all`), `app/models/access.rb` and `User#deactivate` (accesses destroyed with callbacks), which the group cleanup relies on
   - `app/views/boards/edit/_users.html.erb` (copied into `app/views/fizzy/oidc/overrides/boards/edit/`), `app/views/boards/_access_toggle.html.erb` and `app/helpers/accesses_helper.rb` (`access_menu_tag`, `access_toggles_for`), which the copy renders
   - `app/models/user/filtering.rb` (`users`, `cache_key`), and `app/views/filters/settings/_assignees.html.erb`, `_creators.html.erb`, `_closers.html.erb` and `app/views/events/index/filter/_user.html.erb` (copied into `app/views/fizzy/oidc/overrides/`); `app/models/user/day_timeline.rb` (`TIMELINEABLE_ACTIONS`, and the events still filtered by `creator_id`); `Assignment`, `Closure` and `Card` must still store `assignee_id`, `user_id` and `creator_id`, and assignments must still `touch` their card or the menu etag goes stale
   - `app/controllers/my/menus_controller.rb` (our `show` is a copy)
   - `app/controllers/cards/assignments_controller.rb`
   - `app/controllers/users/avatars_controller.rb` and `app/helpers/avatars_helper.rb`
2. Run the test suite against the stub models.
3. Smoke-test against a Fizzy checkout with the gem path-mounted: `docker compose -f compose.dev.yml up --build` (see the README's "Local stack" section).
4. Mandatory: run the board access round trip in that Fizzy, `bin/rails runner /path/to/dev/board_access_smoke.rb`. It renders a board's edit page, checks every member comes back checked, searches twice, saves, and checks members kept and both searched people granted; then searches and attaches a project group, checks its member is let in and rendered locked, saves without them, and detaches the group; then reads `group_user_ids` from the board's JSON, revokes the member with a JSON `user_ids`, and claims them back in person with `personal_user_ids`; it creates and deletes its own board, people and group. A member the override fails to render checked is a member the next save revokes, and no unit test sees that.

## Conventions

- Ruby 3.4 from `flake.nix` (`.envrc` → `use flake`). Fizzy pins 3.4.8; the dev shell takes nixpkgs' latest 3.4 patch, the Dockerfile keeps 3.4.8.
- Minitest. No RSpec.
- No comments unless WHY is non-obvious.
- The gemspec's `add_development_dependency` list is the source of truth for test deps — don't add a Gemfile.
