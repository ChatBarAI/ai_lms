# AI LMS

An AI centric open-source Rails LMS/e-learning system with a built-in AI tutor on every lesson,
powered by [ChatBar AI](https://chatbar-ai.com). [Anam](https://https://anam.ai/) or your own embeded custom AI.
Instructors author courses and lessons, students enrol,
work through lesson videos and quizzes, and can ask the lesson-scoped AI tutor
follow-up questions in a popup or slide-in drawer.

Use Chatbar AI or provide your own endpoint to create lesson questions. Free-form Quiz and Test answers can be automatically marked by ChatBar AI or your own authenticated AI RAG end-point with callbacks.

## Contents

- [Roles](#roles) and [key features](#key-features)
- [Stack](#stack), [domain model](#domain-model), and [namespaces](#namespaces)
- [Authentication and SSO](#authentication-and-sso)
- [ChatBar AI integration](#chatbar-ai-integration)
- [Getting started](#getting-started) and [PWA](#pwa-chrome)
- [Deployment](#deployment) and [command reference](#command-reference)
- [Backups](#backups) and [cloning an instance](#cloning-an-instance)
- [Local Docker restore](#restore-locally-in-docker-recommended)
- [Native local restore](#restore-locally-without-docker)
- [Configuration](#configuration), [conventions](#conventions), and [known gotchas](#known-gotchas)

## Roles

| Role           | Description                                                                                                                                                                                                                      |
| -------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Guest**      | Unauthenticated visitor. Can browse subjects and read only published courses that have **Allow public access** enabled. Cannot enrol, rate, submit quizzes, or access private course assets. |
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
- Guest access toggle plus per-course **Allow public access** — courses are private to signed-in users by default, with explicit public opt-in.
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
- ActiveStorage (course/lesson assets, lesson materials, ActionText/Trix embeds, site branding)
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
- **Course** public access is explicit. Published courses are visible to signed-in
  users by default, but anonymous users can read only courses where
  `public_access_enabled` is true and `SiteSetting#allow_guest_access` is enabled.
  Private course, lesson, lesson-material, and Trix/ActionText assets require a
  signed-in user even when someone has a signed ActiveStorage URL.
- **Lesson** key columns:
  `title, position, body, cbai_token, cbai_api_key, cbai_display_mode,
   video_url, published_at`.
  - `has_one_attached :intro_video` (mp4/webm/ogg, ≤100 MB)
  - `has_one_attached :poster_image` (image, ≤5 MB)
- **LessonMaterial** represents supplementary content attached to a lesson,
  including ChatBar conversation materials that store and submit their starting
  prompt and instance token independently of any EverLink URL. A lesson's token
  is only offered as the initial default when authoring the material; starting
  the conversation mounts ChatBar directly inside the material container.
  Material kinds cover PDFs, rich or imported HTML, audio, images, video, web
  pages, and ChatBar conversations. Materials can be marked `required`, in
  which case students must acknowledge them before the lesson counts as fully
  complete.
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
| Public        | `/courses/:slug`, `/courses/:slug/lessons/:id`                  | Anonymous reads are allowed only for published courses with **Allow public access** enabled, and only when site-wide guest access is enabled. |
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

### Kinde Google connection

Configure the Google social connection in the same Kinde environment used by
the LMS:

1. In Kinde, open **Settings → Environment → Authentication** (shown as
   **Settings → Authentication** in some dashboard versions).
2. Under **Social connections**, select **Configure** on the Google tile.
3. Copy its Connection ID and store it in Rails credentials as
   `kinde.connections.google`.
4. In the connection's **Upstream params** field, enter:

   ```json
   {
     "prompt": {
       "value": "select_account"
     },
     "login_hint": {
       "alias": "login_hint"
     }
   }
   ```

5. Enable the connection for the LMS application and save it.

The relevant Rails credentials have this shape:

```yaml
kinde:
  domain: https://your-business.kinde.com
  client_id: your-kinde-client-id
  client_secret: your-kinde-client-secret
  host: https://lms.example.com
  connections:
    google: conn_your_google_connection_id
    microsoft: conn_your_microsoft_connection_id
```

The LMS passes the address entered on its sign-in page to Kinde as
`login_hint` and requests a fresh Kinde login. The upstream configuration then
forwards that hint to Google and uses `prompt=select_account` so an existing
browser Google session does not silently select the wrong account. A login
hint guides the provider UI; it is not authorization and must not be used as
proof of identity.

After deploying authentication changes, restart the production Rails process;
production does not reload controller classes. To troubleshoot, inspect the
LMS-to-Kinde redirect in the Rails log. A Google request should contain
`connection_id`, `prompt=login`, and `login_hint` (filtered in some log
contexts).

Official Kinde documentation:

- [Google social sign-in](https://docs.kinde.com/authenticate/social-sign-in/google/)
- [Pass parameters to identity providers](https://docs.kinde.com/authenticate/auth-guides/pass-params-idp/)

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

The production stack is designed for a fresh Debian server with SSH access.
It runs Rails, Sidekiq, PostgreSQL, Redis, and Caddy in Docker containers.
Caddy obtains and renews the HTTPS certificate automatically.

Persistent state lives in named Docker volumes. Application releases live
under `/opt/ai_lms/releases`, and `/opt/ai_lms/current` points to the active
release.

### Command reference

Run `bin/` commands from your local checkout. The `deploy/` scripts operate
on the machine where they run.

| Command | Purpose |
| --- | --- |
| `bin/deploy root@HOST DOMAIN` | Deploy application code to the remote server; no automatic data backup. |
| `bin/backup USER@HOST [FILE]` | Create a remote snapshot and download one archive locally. |
| `bin/export USER@HOST [FILE]` | Same portable archive as `bin/backup`. |
| `bin/restore --force USER@HOST FILE` | Upload and restore onto a prepared remote Docker instance. |
| `bin/local-clone restore --force FILE` | Build and restore an isolated local Docker test instance. |
| `bin/local-clone start\|stop\|logs\|status` | Manage the local Docker clone. |
| `deploy/backup [FILE\|DIRECTORY]` | Back up the instance on this machine. |
| `deploy/export [FILE]` | Export the instance on this machine as one archive. |
| `deploy/restore --force FILE` | Restore into the instance on this machine. |

Backup, export, restore, and local-clone commands support `--help`.
Remote wrappers accept `SSH_PORT` and `DEPLOY_ROOT`.

### Single-instance limitation

The current Docker deployment supports one LMS instance per server. It uses
the fixed Compose project name `ai_lms`, fixed image and named-volume names,
the fixed `/opt/ai_lms` deployment root, and a Caddy container bound to host
ports 80 and 443.

Do not run an unchanged second copy on the same server. Besides port and
container conflicts, the fixed PostgreSQL and Active Storage volume names
could cause instances to share persistent data. A multi-instance deployment
must parameterize every stack, image, directory, network, and volume name and
use one shared edge proxy to route each domain to its corresponding Rails
service.

### Source-only sync for native installations

`bin/sync-source` is a small rsync wrapper for an existing native installation:

```bash
bin/sync-source USER@HOST /absolute/path/to/ai_lms
```

It mirrors the current working tree, including uncommitted source changes, but
protects remote `log`, `tmp`, `storage`, and compiled assets and excludes local
secrets, Git metadata, dependencies, clone bundles, and common database backup
files (`*.dump`, `*.sql`, `*.sql.gz`, and `*.backup`). It does not install gems,
migrate the database, compile assets, or restart Puma/Sidekiq.

Preview the exact changes first with:

```bash
bin/sync-source --dry-run USER@HOST /absolute/path/to/ai_lms
```

Set `SSH_PORT` when the target does not use port 22. Run any required native
maintenance separately after syncing:

```bash
RAILS_ENV=production bundle install
RAILS_ENV=production bin/rails db:migrate
RAILS_ENV=production bin/rails assets:precompile
sudo systemctl restart puma-ai_lms.service sidekiq-ai_lms.service
```

### Deployment prerequisites

The pre-commit Brakeman review reported that the pinned Rails 7.2.3.2 version
is past its support date (2026-08-09). Track the Rails upgrade separately;
backup tooling does not resolve this dependency warning. Do not extend the
EOL exception in `config/brakeman.ignore` without a maintenance decision.

- A Debian server reachable over SSH by root (or another account that is
  already able to run the deploy as root).
- Ports 22, 80, and 443 open at the provider/firewall.
- A DNS `A`/`AAAA` record for the application domain pointing at the server.
- `config/credentials/production.key` on the deploying computer. It remains
  ignored by Git and is copied through SSH only for the deployment.
- A clean, committed local Git `HEAD`.

Docker does not need to be preinstalled. The first deployment installs Docker
using Docker's official Debian installer.

### Deploy

From the repository root:

```bash
bin/deploy root@SERVER_IP learn.example.com
```

SSH will prompt for the root password if no key is configured. A nonstandard
SSH port can be supplied with `SSH_PORT=2222`.

The first run:

1. Sends an archive of the committed local `HEAD` (repository access is not
   required on the server).
2. Installs Docker and Docker Compose.
3. Creates `/opt/ai_lms/shared/.env` with generated database credentials and
   the Rails production key.
4. Builds the application image, prepares the database, and starts the web,
   worker, database, Redis, and HTTPS proxy services.

Subsequent runs repeat only the release, build, migration, and restart steps.
The five newest source releases are retained. Deploys intentionally refuse
tracked uncommitted changes so the deployed revision is reproducible.

While developing the deployment mechanism itself, an explicit development mode
can package the current working tree:

```bash
bin/deploy --dirty root@SERVER_IP learn.example.com
```

This includes tracked modifications and non-ignored new files, but continues
to exclude ignored secrets such as `.env` files and Rails credential keys.
Dirty releases receive a timestamped `-dirty-` suffix and should not be used
for normal production releases.

#### Domain aliases

Point every alias domain at the same server, then include the aliases after the
canonical domain:

```bash
bin/deploy root@SERVER_IP learn.example.com academy.example.com courses.example.com
```

Caddy obtains certificates for all supplied names and serves the same
application on each. `APP_HOST` remains the canonical first domain for email
links and authentication callbacks. Once aliases have been configured, normal
deploy commands that omit them preserve the existing list. Supplying aliases
again replaces the complete alias list.

To change the canonical domain explicitly:

```bash
bin/deploy --change-domain root@SERVER_IP new.example.com
```

The previous canonical domain and configured aliases remain aliases unless a
new complete alias list is supplied on the same command. The change updates
`APP_HOST`, `CALLBACK_HOST`, and generated default mail/ACME addresses. Update
DNS first, and update allowed callback/logout URLs in external identity
providers such as Kinde.

For Kinde, update its permitted callback and logout URLs:

```text
https://new.example.com/kinde/callback
https://new.example.com/kinde/logout_callback
```

### Configuration and operations

The environment is stored on the server at `/opt/ai_lms/shared/.env` with mode
`0600`. Add SMTP provider settings there, for example:

```dotenv
MAIL_DELIVERY_METHOD=smtp
SMTP_ADDRESS=smtp.example.com
SMTP_PORT=587
SMTP_DOMAIN=example.com
SMTP_USERNAME=...
SMTP_PASSWORD=...
SMTP_AUTHENTICATION=plain
SMTP_ENABLE_STARTTLS_AUTO=true
```

After editing it, recreate the app processes:

```bash
cd /opt/ai_lms/current
export APP_IMAGE="ai_lms:$(basename "$(readlink -f /opt/ai_lms/current)")"
docker compose --env-file /opt/ai_lms/shared/.env up -d web worker proxy
```

Useful checks:

```bash
cd /opt/ai_lms/current
export APP_IMAGE="ai_lms:$(basename "$(readlink -f /opt/ai_lms/current)")"
docker compose --env-file /opt/ai_lms/shared/.env ps
docker compose --env-file /opt/ai_lms/shared/.env logs -f --tail=200 web worker
```

### Docker console and logs

Open a production Rails console inside the running web container:

```bash
ssh root@SERVER_IP
docker exec -it ai_lms-web-1 ./bin/rails console
```

Follow the Rails/Puma log (the Docker equivalent of following the native Puma
systemd journal):

```bash
docker logs --follow --tail=200 ai_lms-web-1
```

Inspect recent Rails, Sidekiq, or Caddy logs:

```bash
docker logs --since=10m ai_lms-web-1
docker logs --since=10m ai_lms-worker-1
docker logs --since=10m ai_lms-proxy-1
```

Native installations continue to use systemd, for example:

```bash
sudo journalctl -u puma-ai_lms.service -f
sudo journalctl -u sidekiq-ai_lms.service -f
```

### Rollback

List the retained releases and choose a full Git SHA:

```bash
ls -1t /opt/ai_lms/releases
```

Then recreate the application from that release:

```bash
release=FULL_GIT_SHA
cd "/opt/ai_lms/releases/$release"
export APP_IMAGE="ai_lms:$release"
docker compose --env-file /opt/ai_lms/shared/.env up -d
ln -sfn "/opt/ai_lms/releases/$release" /opt/ai_lms/current
```

This rolls back application containers, not PostgreSQL migrations. Restore the
pre-deploy database backup as well if the schema change is not backward
compatible.

### Backups

#### Run from your computer

The `bin/` commands connect over SSH, like `bin/deploy`. Updated scripts must
already be deployed on the remote Docker instance:

```bash
SSH_PORT=51760 bin/backup root@148.72.159.88
```

This creates a remote snapshot and downloads a single timestamped
`ai-lms-clone-*.tar.gz` into your current directory. To choose the local filename:

```bash
SSH_PORT=51760 bin/backup root@148.72.159.88 ./ai-lms-clone-craig.tar.gz
```

`bin/export HOST [LOCAL_OUTPUT.tar.gz]` does the same. Both wrappers call
`deploy/export` remotely, including on older deployments where `deploy/backup`
still creates two separate files.
Both archives work with either restore command. A successful download removes
the temporary remote copy; failed backups/downloads print the retained remote
staging path for recovery. Existing local files are never overwritten.

To restore onto another **already deployed** Docker server:

```bash
SSH_PORT=22 bin/restore --force root@NEW_SERVER ./ai-lms-clone-craig.tar.gz
```

This uploads the archive and replaces the destination data. To restore on
your own computer, use [the local Docker clone](#restore-locally-in-docker-recommended)
or [the native restore](#restore-locally-without-docker) described below. All three wrappers support `--help`, `SSH_PORT` (default 22), and
`DEPLOY_ROOT` (default `/opt/ai_lms`). They target Docker deployments;
use the `deploy/` scripts directly for native instances.

#### Run directly on the source instance

Run the bundled backup command on the server:

```bash
/opt/ai_lms/current/deploy/backup
```

It creates one `ai-lms-clone-TIMESTAMP.tar.gz` in `/opt/ai_lms/backups`,
containing a PostgreSQL custom-format dump, all local Active Storage files,
and metadata identifying the source release. An optional argument selects an
output `.tar.gz` file or a backup directory. Existing files are never overwritten;
the final filename appears only after the archive is complete, with mode `0600`.
`deploy/export` uses the same format and remains available.

For example, create a backup on the server and download it:

```bash
ssh root@SERVER_IP '/opt/ai_lms/current/deploy/backup /tmp/ai-lms-clone.tar.gz'
scp root@SERVER_IP:/tmp/ai-lms-clone.tar.gz .
```

Docker web and worker services are stopped during the snapshot; services that
were running are restarted even if the backup fails. Allow for this downtime
and do not deploy or run other database/storage writers during the backup.
For native installations, stop all writers yourself and set
`DEPLOY_MODE=native NATIVE_WRITES_STOPPED=1`.

The archive contains application data and stored API credentials. Keep it
private and copy it off the server. It does not include application source,
environment files, Rails credential keys, Redis queues, or external media
referenced by URL. Keep the matching code and required keys separately; set up
destination infrastructure before restoring.

Restore only archives from trusted instances: a PostgreSQL dump can contain
SQL executed with the restoring database user's privileges. Archive path and
file-type checks do not make an untrusted database dump safe. Archives are
not encrypted at rest; SSH protects transfers. Keep all backups private.

**Deploys do not automatically back up data.** Retained source releases are
not database backups. Run this command explicitly before a deploy or schedule
it separately.

Database migrations are applied before a release starts. Rolling application
code back after a migration is not universally safe, so take a backup before
deploying schema changes.

### Cloning an instance

`deploy/export` creates a portable clone bundle containing a custom-format
PostgreSQL dump and all Active Storage files. It auto-detects the Docker
deployment or a native Rails/PostgreSQL installation.

For a native source, first copy these files into the source application's
`deploy/` directory if that checkout does not have them:

```text
deploy/export
deploy/restore
deploy/database_transfer.rb
deploy/unpack-bundle
```

Stop the native Puma and Sidekiq services, then export as the application user:

```bash
cd /path/to/native/ai_lms
NATIVE_WRITES_STOPPED=1 DEPLOY_MODE=native \
  deploy/export /tmp/ai-lms-clone.tar.gz
```

Restart the source services immediately after the export. Copy the resulting
bundle through the deploying computer:

```bash
scp root@OLD_SERVER:/tmp/ai-lms-clone.tar.gz .
scp ai-lms-clone.tar.gz root@NEW_SERVER:/tmp/
```

Deploy the current code to the Docker destination before restoring so its
restore script and migrations are current. Then restore on the destination:

```bash
ssh root@NEW_SERVER
/opt/ai_lms/current/deploy/restore \
  --force /tmp/ai-lms-clone.tar.gz
```

The restore command deliberately replaces the entire destination database and
Active Storage volume. On Docker it stops and restarts Rails, Sidekiq, and
Caddy automatically. It retains destination infrastructure configuration from
`/opt/ai_lms/shared/.env`; cloned `SiteSetting#redis_url` and `app_url` values
are cleared so Redis uses the Docker service and generated links use the new
canonical hostname. Set `PRESERVE_INSTANCE_SETTINGS=1` only when those two
source settings should also be copied literally.

For a Docker source, `deploy/export /tmp/ai-lms-clone.tar.gz` pauses and
restarts web/worker processes automatically. Native service names vary, so the
operator must stop and restart those services and acknowledge this with
`NATIVE_WRITES_STOPPED=1`.

#### Restore locally in Docker (recommended)

Use the standalone local clone stack to avoid installing Ruby gems or matching
PostgreSQL client versions on your computer:

```bash
bin/local-clone restore --force ./ai-lms-clone-20260905T094642Z.tar.gz
```

This builds the current checkout using the production Dockerfile, starts
PostgreSQL 16 and Redis, restores the archive, runs migrations, and starts the
app at **http://localhost:3100**. The first build downloads Ruby gems and system
dependencies. Docker Compose with `up --wait` support is required.

The `ai_lms_local_clone` Compose project has its own database and storage
volumes. It does not use the production Compose file, `/opt/ai_lms`, or the
native development database/storage directory.

**Why `--force`?** Restore deletes the local clone's database and uploaded
files before importing the backup. Any courses, users, or uploads changed
while testing that clone will be lost. The flag explicitly acknowledges this
replacement and is required even for the first restore; it does not bypass
archive validation. To resume an existing clone with its data intact, use
`bin/local-clone start` instead of restoring again.

The web port binds only to loopback. Set `LOCAL_PORT=3101`
on each command if port 3100 is occupied.

```bash
bin/local-clone status
bin/local-clone logs
bin/local-clone stop
bin/local-clone start
```

Stopping preserves the Docker volumes. This is a production-mode test copy,
not a live-reloading development environment. Restore again after source
changes to rebuild it. Local HTTP is enabled, email delivery is disabled,
and no background worker runs. Source accounts and integration credentials
remain; SSO callbacks and external integrations may need local configuration.
The command reads `config/credentials/production.key` if present; alternatively
provide `RAILS_MASTER_KEY` for credentials required by your checkout.
The wrapper generates a private `.env.local-clone-secret` signing key, excluded
from Git and Docker builds. Existing clone sessions will be invalidated once
when switching from the earlier fixed signing key. Remote Docker endpoints
are refused; the wrapper requires a local Unix Docker socket. There is one
local clone stack per Docker daemon; run its restore/start/stop commands one
at a time, including across checkouts.

An `unsupported version (1.15) in file header` error from native `pg_restore`
means the local client cannot read that dump format. This Docker workflow
uses the PostgreSQL 16 client matching the deployed database.

#### Restore locally without Docker

Use a separate checkout of the source release (or a compatible newer release),
install its gems, and install PostgreSQL client tools compatible with the source
database (the Docker source uses PostgreSQL 16). These shell scripts require
Bash and GNU `tar`/`readlink`, as on the project's Linux development environment.
Configure the local database and required Rails keys first. Make sure
`DATABASE_URL`, if set, points to the intended local database.

Stop the local Rails server and background workers. From that checkout:

```bash
RAILS_ENV=development bin/rails db:create &&
DEPLOY_MODE=native RAILS_ENV=development NATIVE_WRITES_STOPPED=1 \
  deploy/restore --force /absolute/path/to/ai-lms-clone.tar.gz
bin/dev
```

This replaces the configured development database contents and the checkout's
`storage/` files, then runs migrations. `RAILS_ENV` defaults to `production`
when omitted. Set `STORAGE_PATH` only if the destination uses a custom Disk
storage root. The restore clears source `app_url` and `redis_url` settings by
default; other source settings, users, and integration credentials remain.
Review those integrations before using the clone with external services.

Standalone backup script checks (no Rails boot or database access):

```bash
ruby test/deploy/backup_test.rb
ruby test/deploy/remote_transfer_test.rb
ruby test/deploy/local_clone_test.rb
ruby test/deploy/unpack_bundle_test.rb
```

### Rate limiting

Production request throttling is provided by Rack::Attack. Rules protect
password login and reset, Kinde and SSO routes, public token-based endpoints,
certificate verification, callbacks, video imports, and AI question
generation. Throttled requests return `429 Too Many Requests` with a
`Retry-After` header.

Rack::Attack stores its counters in Redis using the URL configured in
**Admin → Site settings → Integration**. If that setting is blank, it uses
`REDIS_URL`, then falls back to `redis://localhost:6379/0`. Counters use the
`ai_lms:rack_attack` namespace so they do not collide with Sidekiq or other
application keys in the same Redis database.

Each deployed LMS instance sharing a Redis server must use a unique Redis DB
number in its URL, for example `redis://localhost:6379/2`. All Puma processes
for one instance must use the same URL and DB so they share counters. Redis
configuration is read at boot; restart Puma and Sidekiq after changing it in
Admin. Moving an instance to another Redis DB also starts a fresh set of rate
limit counters.

Throttle names, limits, and periods are defined centrally in
[`config/initializers/rack_attack.rb`](config/initializers/rack_attack.rb).

## Configuration

- `config/database.yml` — Postgres connection. The username defaults to
  the current OS user (peer auth); override via `PGUSER` env var or
  `DATABASE_URL` in production.
- Production email:
  configure delivery from Admin -> Site settings -> Integration after the
  database migrations have run. Environment variables still work as bootstrap
  defaults and fallbacks.

  By default production uses the local `sendmail` command so a local MTA such
  as Postfix can deliver Devise emails without Rails connecting to
  `localhost:25` over SMTP. Override `SENDMAIL_LOCATION` or
  `SENDMAIL_ARGUMENTS` in the environment, or set the equivalent fields in the
  Admin panel, if your server uses non-standard paths.

  To use an SMTP provider instead, set `MAIL_DELIVERY_METHOD=smtp` and provide
  `SMTP_ADDRESS`, `SMTP_PORT`, `SMTP_DOMAIN`, `SMTP_USERNAME`,
  `SMTP_PASSWORD`, and `SMTP_AUTHENTICATION` as required by the provider.
  You can also enter these values in Admin -> Site settings -> Integration.
  `SMTP_ENABLE_STARTTLS_AUTO=false` disables STARTTLS for a trusted local relay;
  do not disable TLS verification for internet SMTP providers.
- `config/initializers/devise.rb` + `app/controllers/kinde_auth_controller.rb` — auth setup.
  Kinde is the primary SSO path; sign-in and JIT behavior are controlled by
  `SiteSetting` auth policy fields and, optionally, per-organization SSO settings.
- ChatBar AI integration: no global credentials are needed. Each lesson
  stores its own `cbai_api_key`. Use `CBAI_BASE_URL` to point the recordings
  client at a non-production host in development, `CBAI_TASK_API_URL` to
  point the Task API client elsewhere, and `CALLBACK_HOST` to control the
  public host used when generating Task API callback URLs.
- Imported videos are downloaded through an SSRF-safe, size-bounded downloader.
  Set `VIDEO_DOWNLOAD_ALLOWED_HOSTS` to a comma-separated list of exact storage
  hostnames to additionally restrict ChatBar, Synthesia, and HeyGen download
  redirects in production (for example, your S3 or CDN hostnames). Provider API
  hosts are added automatically. Downloads otherwise require public HTTPS
  destinations and are capped at 100 MB.
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
