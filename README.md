# AI LMS

An AI centric open-source Rails LMS/e-learning system with a built-in AI tutor on every lesson,
powered by [ChatBar AI](https://chatbar-ai.com). [Anam](https://https://anam.ai/) or your own embeded custom AI.
Instructors author courses and lessons, students enrol,
work through lesson videos and quizzes, and can ask the lesson-scoped AI tutor
follow-up questions in a popup or slide-in drawer.

Use Chatbar AI or provide your own endpoint to create lesson questions. Free-form Quiz and Test answers can be automatically marked by ChatBar AI or your own authenticated AI RAG end-point with callbacks.

## Roles

| Role           | Description                                                                                                                                                                                                                      |
| -------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Guest**      | Unauthenticated visitor. Can browse and read published subjects, courses, and lessons. Cannot enrol, rate, submit quizzes, or access lesson materials.                                                                           |
| **Student**    | Default role assigned on self-service registration (when enabled) or first SSO JIT sign-in. Can enrol in published courses, track lesson progress, submit quiz answers, rate lessons, view and acknowledge lesson materials, and download their own completion certificates. |
| **Instructor** | Can create and own courses. Manages the full lifecycle of their courses: CRUD for lessons, questions (including AI-generated), lesson materials, video sources, and certificate layout. Cannot manage other instructors' content. |
| **Admin**      | Full access to everything via the `/admin` namespace: catalogue CRUD, user management, site settings (branding, theme, terminology, auth policy), organization SSO setup, and certificate administration. |

## Key Features

**Quick setup**
- Less than 5 min to setup for LINUX with bin/setup

**AI Tutor**
- Per-lesson AI tutor widget powered by [ChatBar AI](https://chatbar-ai.com) — popup, drawer, or hidden per lesson.
- [Anam AI](https://anam.ai) avatar-based AI tutor as an alternative provider — configurable per lesson with a persona ID.
- Free-text quiz and test answers automatically scored by ChatBar AI (or any authenticated callback endpoint) with live score updates via Action Cable.
- AI-generated questions via the ChatBar Task API — instructor reviews before publishing.

**Video**
- Multiple video sources per lesson: YouTube/URL, direct upload, [Synthesia](https://synthesia.io) AI video import, [HeyGen](https://heygen.com) AI video import, or ChatBar AI recording download.
- Poster image per lesson.

**Courses and Content**
- Full course and lesson authoring with rich-text body (ActionText), quizzes, and lesson materials (PDF, audio, HTML, external links).
- Required materials with per-student acknowledgement tracking before a lesson counts as complete.
- Customisable completion certificates per course — exportable as PDF.
- Tags for courses and lessons.

**Authentication and Organisations**
- Email/password (Devise) and SSO via [Kinde](https://kinde.com) — Google and Microsoft providers.
- Per-organisation SSO with JIT provisioning, domain-based auto-redirect, and optional SSO enforcement.
- Self-service sign-up toggle.

**Platform**
- Fully themeable: colours, brand name, logo, and per-term terminology overrides.
- PWA support: installable, offline fallback, configurable icons and manifest.
- Guest access toggle — public catalogue browsing without an account.
- Admin panel for full catalogue, user, and site management.

## Stack

- Ruby `3.4.2`
- Rails `7.2.3`
- PostgreSQL
- ActiveJob via Sidekiq 7 + Redis (background AI scoring)
- Action Cable + Turbo Streams (live UI updates from background jobs)
- Devise 4.9 + Kinde SDK (primary SSO flow)
- CanCanCan (authorisation, see [`app/models/ability.rb`](app/models/ability.rb))
- Tailwind CSS via `tailwindcss-rails`
- Haml for views (no ERB)
- Importmap, Turbo, Stimulus
- ActiveStorage (lesson intro videos, lesson poster images, site logo)
- `active_storage_validations` for content-type and size limits
- Ransack, Pagy, Rack::Attack, HTTParty (utility gems)

## Domain model

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

- **Subject** and **Course** are routed publicly by `slug`. Both define
  `to_param` returning the slug and controllers fall back to id:
  `find_by(slug: params[:id]) || find(params[:id])`.
- **Lesson** key columns:
  `title, position, body, cbai_token, cbai_api_key, cbai_display_mode,
   video_url, published_at`.
  - `has_one_attached :intro_video` (mp4/webm/ogg, ≤100 MB)
  - `has_one_attached :poster_image` (image, ≤5 MB)
- **LessonMaterial** represents supplementary content attached to a lesson.
  Supports five `kind` values: `pdf` (uploaded PDF, ≤25 MB), `html` (rich
  text via ActionText), `raw_html` (sanitised HTML pasted directly),
  `audio_upload` (uploaded audio file, ≤50 MB), and `audio_url` (external
  audio link). Materials can be marked `required`, in which case students
  must acknowledge them before the lesson counts as fully complete.
  - `has_one_attached :document` (PDF)
  - `has_one_attached :audio_file` (audio)
- **LessonMaterialAcknowledgement** records that a specific enrolled student
  has acknowledged a required material. Scoped to an `Enrollment` so the
  record is automatically invalidated if the student leaves and re-enrols.
- **Certificate** is issued to a student when they have fully completed every
  required lesson in a course (`Enrollment#fully_completed?`). Records are
  unique per `(user, course)` pair. Each certificate carries a
  `token` (URL-safe base64, 16 bytes) used for public verification at
  `/certificates/:token`. Instructors can customise the certificate layout
  (background colour, logo placement, signature line, etc.) per course via
  the `certificate_layout` member action on `Course`.
- **SiteSetting** is a singleton (`SiteSetting.current`) with `brand_name`
  and `has_one_attached :logo`. Used by the layout via `BrandingHelper`.
- **Publishing**: both `Course` and `Lesson` support `publish` / `unpublish`
  member actions. Drafts are visible to their owner but not to other users.

## Namespaces

| Surface       | Mounting                                                        | Notes                                                                                      |
| ------------- | --------------------------------------------------------------- | ------------------------------------------------------------------------------------------ |
| Public        | `/courses/:slug`, `/courses/:slug/lessons/:id`                  | Anonymous reads of the published catalogue allowed.                                        |
| Authenticated | Enrolments, ratings, quiz submissions, lesson materials, certs  | Students manage their own enrolments, ratings, progress, acknowledgements, and certificates. |
| Instructor    | Same paths, gated via CanCanCan                                 | `can :manage, Course, owner_id: user.id` and equivalents for lessons, materials, questions. |
| Admin         | `/admin/...`                                                    | Full catalogue CRUD, user management, site settings, certificate administration.           |
| API           | `/api/...`                                                      | Public lesson lookup by `cbai_token`; question-generation task callback endpoint.          |
| Verification  | `/certificates/:token`                                          | Public, unauthenticated certificate verification page.                                     |

## Authentication and SSO

Authentication is configured in **Admin → Site settings → General → Authentication policy (Kinde)**.

- `Enable Google sign-in` controls whether the Google sign-in path is shown and accepted.
- `Enable Microsoft sign-in` controls whether the Microsoft/Entra sign-in path is shown and accepted.
- `Allow self-service sign up` controls whether `/users/sign_up` is available.
- Provider JIT toggles control auto-provisioning on first SSO login:
  - `Google via Kinde: auto-create LMS users (JIT)`
  - `Microsoft Entra via Kinde: auto-create LMS users (JIT)`

Provider sign-in toggles and provider JIT toggles are independent:

- If provider sign-in is disabled, that provider cannot be used at all.
- If provider sign-in is enabled but JIT is disabled, only pre-existing LMS users can sign in with that provider.

### Organization-specific SSO (optional)

Use **Admin → Organizations** to configure per-organization SSO (for org links and domain routing):

- `Kinde Connection ID`
- `Provider label` (`microsoft`, `google`, `other`)
- `Require SSO`
- `Email domain (for auto-redirect)`
- `Auto-create LMS account on first SSO sign-in`

Organization setup is required for org-specific SSO flows (`/auth/org/:org_slug`) and domain-based SSO routing. It is not required for global provider buttons.

## ChatBar AI integration

### Tutor embed

- The lesson show page mounts the tutor via
  [`app/views/lessons/_cbai_embed.html.haml`](app/views/lessons/_cbai_embed.html.haml).
- Loader script: `https://scripts.chatbar-ai.com/cb-ai-search.min.js`.
- Init signature:
  `_bl_ai_search.init(token, mountElement, { additional_context, callback })`.
- The partial is robust against Turbo navigation: the script is loaded once
  with a `data-cbai-loader="1"` marker, the mount runs on both
  `DOMContentLoaded` and `turbo:load`, and the mount node has a
  `data-initialised` guard.
- Display mode per lesson: `popup` (centred modal), `drawer` (slide-in), or
  `none` (tutor hidden for that lesson).

### Auto-resolving the tutor token

When an instructor enters a ChatBar AI **API key** on a lesson, the
controller calls `GET /api/cbai/details` and stores the returned token on
`Lesson#cbai_token`. The token field is therefore not directly editable in
the lesson form. See
[`app/services/cbai_client.rb`](app/services/cbai_client.rb) and the
`assign_lesson_form_attributes` flow in
[`app/controllers/lessons_controller.rb`](app/controllers/lessons_controller.rb).

### Recordings API (ChatBar download page)

- Service: [`app/services/cbai_client.rb`](app/services/cbai_client.rb).
- Auth header: `Authorization: <api_key>` (no scheme prefix).
- `GET https://dashboard.chatbar-ai.com/api/cbai/recordings` lists recordings.
- `GET .../recordings/<ID>/download` returns a 302 to a signed ActiveStorage
  blob URL. `download_to_tempfile` follows the redirect but **drops the
  Authorization header on the cross-host hop** (signature alone authenticates
  the blob URL).
- Allowed hosts: `dashboard.chatbar-ai.com`. Override with `CBAI_BASE_URL`
  for local testing.

### Task API (AI-generated questions)

The Questions index page exposes an "Generate questions with ChatBar AI"
card to lesson owners whenever the lesson has both a `cbai_api_key` and a
`cbai_id` (the latter is captured automatically from `/api/cbai/details`
when the API key is saved). Submitting the form creates a
`QuestionGenerationTask` row and POSTs to the ChatBar Task API:

- Endpoint: `POST https://api.chatbar-ai.com/v1/tasks` (override with
  `CBAI_TASK_API_URL`).
- Auth headers: `Authorization: Bearer <api_key>` plus `Cbai-Id: <cbai_id>`.
- Allowed hosts (strict, no localhost loophole): `api.chatbar-ai.com`.
- A unique `callback_secret` is generated per task and embedded in the
  callback URL (`POST /api/question_generation_tasks/:token/callback`).
  Unknown tokens return `404`. The second callback for the same task is a
  no-op so duplicates from ChatBar AI never double-create questions.
- The callback payload is parsed defensively — `questions`,
  `result.questions`, `output.questions`, top-level array, or a `summary`
  string containing JSON are all accepted. Unknown question kinds fall
  back to `free_text` so nothing is silently dropped.
- Generated questions are auto-created as draft `Question` records on the
  lesson; the instructor edits or deletes them after.

#### Public callback URL

ChatBar AI POSTs to the callback URL when the task finishes. In production
set `CALLBACK_HOST` so the helper resolves to a publicly reachable host:

```bash
CALLBACK_HOST=https://lms.example.com bin/dev
# in dev, point at an ngrok / cloudflared tunnel:
CALLBACK_HOST=https://xxx.ngrok.app bin/dev
```

Without `CALLBACK_HOST`, URLs fall back to the current request host.

## Getting started

### Prerequisites

| Requirement | Notes |
|---|---|
| Ruby `3.4.2` | See [`.ruby-version`](.ruby-version). RVM, rbenv, or asdf all work. |
| PostgreSQL `≥ 14` | Default dev DB: `ai_lms_development` |
| **libvips** | ActiveStorage image variants — `apt install libvips-tools` / `brew install vips` |
| **ImageMagick** | PWA icon generation — `apt install imagemagick` / `brew install imagemagick` |
| Redis _(optional)_ | Required in production for Action Cable + Sidekiq. Not needed for basic dev. |
| No Node toolchain | Tailwind compiles via `tailwindcss-rails` — no npm/yarn required. |

`bin/setup --help` will check these automatically before proceeding.

### Install and run

```bash
# Minimal — uses your OS user as the PostgreSQL role (peer auth)
bin/setup

# With options
bin/setup --db-user mydbuser \
          --admin-email alice@example.com \
          --admin-name "Alice" \
          --brand-name "My LMS" \
          --app-url https://learn.example.com

bin/dev   # Rails + Tailwind watcher (Procfile.dev)
```

Setup prints a clear summary of all seeded accounts and their passwords at the
end. Passwords are randomly generated unless you set env vars:
`SEED_ADMIN_PASSWORD`, `SEED_INSTRUCTOR_PASSWORD`, `SEED_STUDENT_PASSWORD`.

### Tests

```bash
bin/rails test
bin/rails test test/path/to/file.rb:42
```

### Static analysis

```bash
bin/brakeman --no-pager
bin/rubocop -f github
```

### JWT / Kinde security note

`kinde_sdk` `1.7.1` currently pins `jwt` to `~> 2.2`, so this app cannot yet
move to `jwt` `3.2.0+` without an upstream Kinde SDK update (or a fork).

To reduce risk while pinned, this app applies an app-level hardening patch in
[`config/initializers/kinde_jwt_hardening.rb`](config/initializers/kinde_jwt_hardening.rb):

- Kinde token validation only allows asymmetric algorithms (`RS*`, `PS*`, `ES*`, `EdDSA`).
- Tokens without `kid` are rejected.

This is a temporary mitigation. Remove the local patch and policy ignore once
`kinde_sdk` supports `jwt` `3.2.0+` and the lockfile is upgraded.

### JavaScript / Stimulus

JS is delivered via Importmap (no Node toolchain). The entry point is
[`app/javascript/application.js`](app/javascript/application.js), which
imports Turbo and auto-registers every Stimulus controller under
[`app/javascript/controllers/`](app/javascript/controllers). To add a
controller, create `app/javascript/controllers/<name>_controller.js` — it
will be picked up automatically on the next request. New external packages
are pinned with `bin/importmap pin <package>`.

## PWA (Chrome)

This app is wired for Chrome PWA installability and offline fallback:

- Manifest endpoint: `/manifest` via
  [`app/views/pwa/manifest.json.erb`](app/views/pwa/manifest.json.erb)
- Service worker endpoint: `/service-worker` via
  [`app/views/pwa/service-worker.js`](app/views/pwa/service-worker.js)
- Registration and install CTA:
  [`app/javascript/application.js`](app/javascript/application.js) and
  [`app/javascript/controllers/pwa_install_controller.js`](app/javascript/controllers/pwa_install_controller.js)
- Offline fallback page: [`public/offline.html`](public/offline.html)
- PWA icons in `public/`: `icon-192.png`, `icon-512.png`,
  `icon-maskable-512.png`, `apple-touch-icon.png`

### Validate in Chrome

1. Open DevTools -> Application -> Manifest and confirm no installability errors.
2. Open DevTools -> Application -> Service Workers and confirm it is active and controlling the page.
3. Run a Lighthouse report with the PWA category enabled.
4. In DevTools Network tab, toggle Offline and verify navigation falls back to `offline.html`.

## Deployment

There is no deploy script in the repository — deployment is intentionally
left to the operator. A typical rsync-over-SSH workflow is:

```bash
rsync -avz --delete \
  --exclude='.git' --exclude='log' --exclude='tmp' \
  --exclude='storage' --exclude='public/assets' \
  --exclude='vendor/bundle' --exclude='.bundle' \
  --exclude='.env*' \
  ./ deploy_user@your-host:/path/to/ai_lms/
```

Then SSH in and finish the deploy:

```bash
bundle config set deployment true
bundle config set without 'development test'
bundle install
RAILS_ENV=production bin/rails db:migrate
RAILS_ENV=production bin/rails assets:precompile
sudo systemctl restart puma-ai_lms
```

### Background jobs

Production uses ActiveJob with Sidekiq and Redis for background work such as
AI quiz marking and ActiveStorage analysis. The Rails web process does not run
these jobs by itself, so run a separate Sidekiq worker process on the server.

A basic manual way to start the worker is:

```bash
nohup env RAILS_ENV=production bundle exec sidekiq >> log/sidekiq.log 2>&1 &
```

Then confirm it stayed up and is processing the default queue:

```bash
ps aux | grep sidekiq
tail -n 100 log/sidekiq.log
RAILS_ENV=production bin/rails runner 'puts "default queue: #{Sidekiq::Queue.new("default").size}"; puts "retries: #{Sidekiq::RetrySet.new.size}"; puts "dead: #{Sidekiq::DeadSet.new.size}"'
```

Sidekiq and the Rails web process must use the same Redis URL. The app resolves
Redis from `SiteSetting#redis_url`, then `REDIS_URL`, then falls back to
`redis://localhost:6379/0`. After changing the Redis URL, restart both Puma and
Sidekiq.

For a durable deployment, run Sidekiq under systemd or the same process manager
used for Puma. The `nohup` command is useful for a quick manual start, but it
will not reliably survive deploys or server restarts.

### First-time server setup

Before the first deploy the target host needs:

- Ruby 3.4.2 (rbenv/rvm), PostgreSQL, libvips, ImageMagick, and build
  essentials (`build-essential`, `libpq-dev`, `libyaml-dev`).
- A PostgreSQL role and database for production:
  ```bash
  sudo -u postgres createuser -P ai_lms
  sudo -u postgres createdb -O ai_lms ai_lms_production
  ```
- Rails credentials: commit `config/credentials.yml.enc` and provide
  `RAILS_MASTER_KEY` in the service environment, or drop `config/master.key`
  on the server out of band.
- Environment variables in the systemd unit or an `EnvironmentFile`:
  `RAILS_ENV=production`, `RAILS_MASTER_KEY`, `DATABASE_URL` (or
  `AI_LMS_DATABASE_PASSWORD`), `PUMA_BIND=unix:///run/ai_lms/puma.sock`,
  and optionally `CALLBACK_HOST=https://<your-host>` for the ChatBar Task
  API callback URL.
- A Puma systemd unit (`puma-ai_lms.service`) with `RuntimeDirectory=ai_lms`
  and a reverse proxy (Nginx/Caddy) terminating TLS and forwarding to the
  Puma UNIX socket.

## Configuration

- `config/database.yml` — Postgres connection. The username defaults to
  the current OS user (peer auth); override via `PGUSER` env var or
  `DATABASE_URL` in production.
- `config/initializers/devise.rb` + `app/controllers/kinde_auth_controller.rb` — auth setup.
  Kinde is the primary SSO path; sign-in and JIT behavior are controlled by
  `SiteSetting` auth policy fields and, optionally, per-organization SSO settings.
- ChatBar AI integration: no global credentials are needed. Each lesson
  stores its own `cbai_api_key`. Use `CBAI_BASE_URL` to point the recordings
  client at a non-production host in development, `CBAI_TASK_API_URL` to
  point the Task API client elsewhere, and `CALLBACK_HOST` to control the
  public host used when generating Task API callback URLs.
- Logs filter `:password`, `:api_key`, and similar parameters
  (`[FILTERED]`). Inspect stored credentials with
  `bin/rails runner` if you need to debug them.

## Conventions

- Haml everywhere for views.
- Tailwind utility classes inline; no app-specific SCSS beyond defaults.
- Path helpers use slugs for `Course`/`Subject` automatically — never
  construct `/courses/#{id}` manually.
- Forms post HTML, not Turbo Streams.
- Use `flash.now[:alert]` when rendering on error inside a GET action that
  fetched something; `flash[:alert]` only on redirects.

## Known gotchas

- CanCanCan defaults custom member actions to authorising `:<action_name>`
  unless aliased. Instructor video actions rely on `:manage` — don't
  tighten this to `:update` without re-aliasing.
- `bin/dev` caches the schema. Restart it after migrations or attribute
  additions.
- Rails `password_field` on `form_with model:` does not auto-populate from
  the model. Always pass `value: @lesson.cbai_api_key` explicitly when you
  want the field pre-filled.

## License

Copyright (c) 2026 ChatBar AI PTE LTD. Released under the [MIT License](LICENSE).
