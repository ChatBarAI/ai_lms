# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```bash
# Setup (first time)
bin/setup --help                 # see options (db user, admin email/name, brand, app URL)
bin/setup                        # minimal setup, uses OS user as Postgres role

# Dev server (Rails + Tailwind watcher + Sidekiq worker, via Procfile.dev)
bin/dev

# Tests (Minitest)
bin/rails test                   # full suite
bin/rails test test/path/to/file.rb        # one file
bin/rails test test/path/to/file.rb:42     # one test at a line

# Static analysis
bin/brakeman --no-pager
bin/rubocop -f github
bin/lint-views                   # Haml checks RuboCop cannot see (secrets in pages); also runs in CI

# Importmap (no Node/npm toolchain in this app)
bin/importmap pin <package>

# Deploy (bootstraps/updates a Debian server from the local committed revision)
bin/deploy root@SERVER_IP learn.example.com
bin/deploy --change-domain root@SERVER_IP new.example.com
bin/sync-source --dry-run USER@HOST /absolute/path/to/ai_lms   # source-only sync, no build/migrate/restart
```

`bin/dev` caches the schema — restart it after migrations or attribute additions. There is no Node toolchain: Tailwind compiles via `tailwindcss-rails` and JS ships via Importmap.

## Architecture

### Domain model

```
Subject ─< Course ─< Lesson ─< Question
                       │         └─ QuizAttempt  (per progress)
                       │
                       ├─ LessonMaterial ─< LessonMaterialAcknowledgement
                       ├─ Rating          (per user, per lesson)
                       └─ Progress        (per enrolment, per lesson)

User ─< Enrollment >─ Course
User ─< Certificate >─ Course
User >─ Organization
Course / Lesson ─< Tagging >─ Tag
```

- `Subject` and `Course` are routed by `slug`; both implement `to_param` returning the slug, and controllers look up via `find_by(slug: params[:id]) || find(params[:id])` — never build `/courses/#{id}` manually, always use the path helpers.
- `Course` visibility: published courses are visible to signed-in users by default; anonymous users can read a course only when it is published **and** `public_access_enabled` is true **and** `SiteSetting#allow_guest_access` is enabled. Private assets require sign-in even with a valid signed ActiveStorage URL.
- `SiteSetting.current` is a singleton driving branding, guest access, auth policy, terminology, and integration config (Redis URL, mail delivery) — read from `Admin → Site settings`, not env vars, except where the README notes an env fallback.
- `Certificate` is issued once `Enrollment#fully_completed?` (every required `LessonMaterial` acknowledged, all required lessons done) and carries a public verification `token` at `/certificates/:token`.
- Publishing (`publish`/`unpublish` member actions) exists on both `Course` and `Lesson`; drafts are visible only to their owner.

### Authorization (CanCanCan)

All authorization lives in `app/models/ability.rb`, built per-role in this order: guest catalog access (gated by `SiteSetting.current.allow_guest_access?`) → return early for `admin?` with `can :manage, :all` → authenticated catalog access → student capabilities → instructor capabilities (owner-scoped via `owner_id: user.id` chains through `course: { owner_id: ... }`). When adding a custom member action to a controller, CanCanCan authorizes it against `:<action_name>` by default — alias it (see `alias_action :publish, :unpublish, to: :update` at the top of `Ability#initialize`) rather than leaving it unaliased or over-broadening an existing `:manage`/`:update` check.

### Namespaces

| Surface | Mounting | Notes |
|---|---|---|
| Public | `/courses/:slug`, `/courses/:slug/lessons/:id` | Anonymous reads only for published + `public_access_enabled` courses when guest access is site-wide enabled |
| Authenticated | Enrolments, ratings, quizzes, materials, certs | Students manage only their own records |
| Instructor | Same paths, CanCanCan-gated | Owner-scoped; cannot manage another instructor's content |
| Admin | `/admin/...` | Full catalogue/user/site-settings/certificate administration |
| API | `/api/...` | Public lesson lookup by `cbai_token`; question-generation task callback |
| Verification | `/certificates/:token` | Public, unauthenticated |

### ChatBar AI integration (per-lesson AI tutor)

- Mounted via `app/views/lessons/_cbai_embed.html.haml` + `app/javascript/controllers/cbai_embed_controller.js` — loads `https://scripts.chatbar-ai.com/cb-ai-search.min.js` directly and calls `_bl_ai_search.init(token, mountElement, { additional_context, callback })`. This is a direct on-page embed, not an iframe; the loader script is deduped with a `data-cbai-loader="1"` marker and mounts on both `DOMContentLoaded` and `turbo:load` behind a `data-initialised` guard so it survives Turbo navigation.
- `Lesson#cbai_token` is not directly editable — entering a ChatBar API key on the lesson form triggers `GET /api/cbai/details` (`app/services/cbai_client.rb`, called from `lessons_controller.rb`'s `assign_lesson_form_attributes`) which resolves and stores the token.
- Recordings API and the Task API (AI-generated draft questions via `QuestionGenerationTask`) both go through `app/services/cbai_client.rb`, with strict allowed-host lists (`dashboard.chatbar-ai.com`, `api.chatbar-ai.com`, overridable via `CBAI_BASE_URL`/`CBAI_TASK_API_URL` for local testing) and a per-task `callback_secret` embedded in the callback URL so unknown/duplicate callbacks are safely ignored.
- Separate from the AI tutor: a distinct, iframe-based "Ask Us" help chat (admin/instructor guidance) exists on branch `50-integration-ask-help-system` — see `docs/planning/ask-us-*.md` if present for the current state of that effort; it is not the same code path as the lesson tutor above and currently has a different (iframe + one-shot context string) integration pattern.

### Authentication / SSO

Kinde is the primary SSO path (`app/controllers/kinde_auth_controller.rb`, `config/initializers/devise.rb`), alongside Devise email/password. Sign-in and JIT provisioning are controlled by `SiteSetting` auth-policy fields (`Enable Google sign-in`, `Enable Microsoft sign-in`, provider JIT toggles) and, optionally, per-`Organization` SSO settings (`Kinde Connection ID`, `Require SSO`, domain-based auto-redirect). Provider sign-in and provider JIT are independent switches — see README's "Authentication and SSO" section for the Kinde Google connection setup steps if touching this area. Production does not reload controller classes; restart the Rails process after auth config changes.

### Known gotchas

- `kinde_sdk` 1.7.1 pins `jwt ~> 2.2`; an app-level hardening patch in `config/initializers/kinde_jwt_hardening.rb` restricts Kinde token validation to asymmetric algorithms and rejects tokens without `kid` — this is a temporary mitigation pending an upstream Kinde SDK update, don't remove it without also upgrading `jwt`.
- Imported lesson videos (YouTube/Synthesia/HeyGen/ChatBar recordings) go through an SSRF-safe, size-bounded downloader capped at 100 MB; `VIDEO_DOWNLOAD_ALLOWED_HOSTS` extends the allowed redirect targets in production.
- Rack::Attack throttling reads its Redis URL from `Admin → Site settings → Integration` (falling back to `REDIS_URL` then localhost) under the `ai_lms:rack_attack` namespace — each LMS instance sharing a Redis server needs a unique DB number, and Puma/Sidekiq must be restarted after changing it.

### Conventions

- Haml everywhere for views (no ERB); Tailwind utility classes inline, no app-specific SCSS.
- Forms post HTML, not Turbo Streams.
- `flash.now[:alert]` when re-rendering after a failed action inside a GET-style flow; `flash[:alert]` only on redirects.

## Rules and what enforces them

When the operator corrects an agent, fix the mistake and add a row. If the rule is already here and nothing enforces it, fix it at the highest level that works (architecture → types → lint → test) in the same change. Drop a row once its mistake can no longer happen.

| Rule | Enforced by |
|---|---|
| Never render a saved secret (API key, token, password) into a page. Secret inputs are `f.password_field <attr>, value: nil` with a "saved — leave blank to keep it" placeholder, and a blank submission keeps the saved value. | `bin/lint-views` in the CI lint job; behaviour tests in `test/controllers/lessons_controller_test.rb` (video import forms) and `test/services/lesson_form_assignment_service_test.rb`. |
| Translations fill terminology placeholders (`%{course}`, `%{lessons_l}`, ...) by themselves, including admin overrides. Don't pass `**terms` to `t`/`I18n.t`; use `terms[:x]` only for a bare term outside a translation. | Architecture: `TerminologyInterpolation` in `config/initializers/terminology.rb`; `test/lib/terminology_interpolation_test.rb`. |
| A new outbound HTTP client keeps the host allow-list *and* honours its `*_BASE_URL` env override, like `CbaiClient`. | Nothing yet (one correction: fa815da). Candidate: extract the `build_uri` allow-list check shared by the five clients in `app/services/`. |

Exceptions to `bin/lint-views` go on the line directly above the offending line: `-# lint-views:allow <rule> -- <reason> (expires YYYY-MM-DD, approved by <name>)`.
