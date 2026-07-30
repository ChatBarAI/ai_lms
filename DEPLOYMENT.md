# Deployment

The production stack is designed for a fresh Debian server with SSH access.
It runs Rails, Sidekiq, PostgreSQL, Redis, and Caddy in Docker containers.
Caddy obtains and renews the HTTPS certificate automatically.

Persistent state lives in named Docker volumes. Application releases live
under `/opt/ai_lms/releases`, and `/opt/ai_lms/current` points to the active
release.

## Single-instance limitation

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

## Source-only sync for native installations

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

Set `SSH_PORT` when the target does not use port 22.

## Prerequisites

- A Debian server reachable over SSH by root (or another account that is
  already able to run the deploy as root).
- Ports 22, 80, and 443 open at the provider/firewall.
- A DNS `A`/`AAAA` record for the application domain pointing at the server.
- `config/credentials/production.key` on the deploying computer. It remains
  ignored by Git and is copied through SSH only for the deployment.
- A clean, committed local Git `HEAD`.

Docker does not need to be preinstalled. The first deployment installs Docker
using Docker's official Debian installer.

## Deploy

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

### Domain aliases

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

## Configuration and operations

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

## Rollback

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

## Backups

Run the bundled backup command on the server:

```bash
/opt/ai_lms/current/deploy/backup
```

It creates timestamped PostgreSQL and uploaded-file archives in
`/opt/ai_lms/backups`. Copy these files off the server. A backup that exists
only on the application server does not protect against server loss.

Database migrations are applied before a release starts. Rolling application
code back after a migration is not universally safe, so take a backup before
deploying schema changes.

## Cloning an instance

`deploy/export` creates a portable clone bundle containing a custom-format
PostgreSQL dump and all Active Storage files. It auto-detects the Docker
deployment or a native Rails/PostgreSQL installation.

For a native source, first copy these three files into the source application's
`deploy/` directory if that checkout does not have them:

```text
deploy/export
deploy/restore
deploy/database_transfer.rb
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
