# Course payments: deployment and acceptance

This implements the first-release design in [course-payments-and-entitlements.md](course-payments-and-entitlements.md), tracked by [issue #166](https://github.com/ChatBarAI/Chatbar-AI-Pte-Issue-Tracker/issues/166). Checkout is disabled by default. Live sales require local Rails tests and real Stripe staging acceptance; static checks are not a substitute.

## Configuration

1. Run `bin/rails db:migrate`, restart Rails and Sidekiq. Existing courses default to free. Keep the payment tables in backups.
2. Use a separate database/deployment for Stripe test mode and production. In **Site settings → Payments → Stripe connection**, enter the secret key and webhook secret, then save. The account ID is retrieved from Stripe automatically and stored encrypted; it is not accepted from form input. The application verifies the candidate API key with `/v1/account` and `/v1/balance` before saving; restricted keys need read access to both endpoints in addition to the payment integration permissions. The webhook secret is verified separately by a signed Stripe delivery. Blank fields preserve current values, and saved secrets are never redisplayed. Failed verification leaves all settings unchanged.

   Credentials are encrypted in the database with Active Record Encryption. The existing `config/initializers/active_record_encryption.rb` derives encryption keys from the application secret. Web and Sidekiq must share the same stable secret; back it up separately from the database. Rotating the application secret requires a deliberate re-encryption plan. Do not replace the existing encryption initializer or regenerate keys for a deployment with stored encrypted data.

   Database credentials take priority over `STRIPE_SECRET_KEY`, `STRIPE_WEBHOOK_SECRET` and `STRIPE_ACCOUNT_ID` environment variables, with Rails credentials (`stripe.secret_key`, `stripe.webhook_secret`, `stripe.account_id`) as the final fallback. Existing deployments can continue using these fallbacks. Settings changes take effect for subsequent requests and jobs without process restarts. The initial code deployment/migration still needs the normal application restart; later Stripe credential edits do not.

   Same-account, same-mode credential rotation is supported. Switching account or test/live mode is blocked when purchases or payment inbox records belong to another identity, including pending purchases. Without conflicting history, an identity change requires a new webhook secret and clears live-readiness confirmation. Use a separate deployment/database or a planned migration for an identity switch with history. Settings updates and purchase-attempt creation share a database lock to prevent racing the first purchase. Coordinate webhook-secret rotation with Stripe and verify a test delivery immediately afterward; failed deliveries can be replayed after the configuration is corrected.
3. Set the HTTPS origin under Site settings → Integration → App URL. Checkout return URLs come only from this setting. In development only, Stripe test keys also allow HTTP loopback origins (`localhost`, `127.0.0.1`, or `[::1]`). Other environments and live keys require HTTPS. Local webhook delivery still needs Stripe CLI forwarding or an HTTPS tunnel.
4. Under Site settings → Payments choose EUR, USD, GBP or JPY, tax configuration, seller, support email and purchaser terms. Prices are integers in minor units (JPY has zero decimal places). Currency changes disable checkout until all paid courses are explicitly repriced; old purchase snapshots are unchanged.
5. For `automatic` tax configure Stripe Tax registrations, business origin, and the default product tax code for these courses in Stripe. Choose inclusive/exclusive pricing explicitly. `exempt` is an explicit operator declaration that no tax is due, not a silent default. Stripe owns tax calculation and financial records; the LMS stores base/tax/total and refunded amounts for reconciliation. Configure receipts and your business details in Stripe. Live-readiness confirmation records that these checks and your retention policy have been completed.
6. Configure a **snapshot** webhook destination at `/stripe/webhook`, for **your account** (not Connect), pinned to `2026-10-28.endive`, matching `Payments::StripeClient::API_VERSION`.
7. Subscribe to `checkout.session.completed`, `checkout.session.expired`, `charge.refunded`, `refund.created`, `refund.updated`, `refund.failed`, `charge.dispute.created`, `charge.dispute.updated`, `charge.dispute.closed`, `charge.dispute.funds_reinstated`, and `charge.dispute.funds_withdrawn`. Checkout is hard-coded to card payments (`payment_method_types: ["card"]`); payment methods enabled in the Stripe dashboard do not change this. A paid session settled by any other method is flagged `Unsupported payment method` for review and never grants access. Do not enable delayed methods without implementing their lifecycle.
8. Install the scheduler below and monitor it. Then enable test purchases. Only confirm live readiness after the acceptance checklist passes.

Authoritative integration references: [Checkout fulfilment](https://docs.stripe.com/checkout/fulfillment), [webhook signatures and delivery](https://docs.stripe.com/webhooks), [Stripe Tax with Checkout](https://docs.stripe.com/tax/checkout), and [currency rules](https://docs.stripe.com/currencies).

## Scheduler and alerts

Sidekiq processes payment jobs using the existing `default` queue. The database inbox closes the gap between event persistence and queue submission. Scheduling must run outside Sidekiq so a failed Redis connection is retried by the next scheduler invocation.

Install this cron entry **on one application host**, replacing the path, Ruby environment setup, and alert address to match deployment. Export the same Rails/Stripe environment as the web and worker processes through the deployment's environment loader. Ensure cron mail delivery is configured and tested, or route stderr and nonzero exit codes to the existing monitoring system.

```cron
MAILTO=payments-ops@example.com
* * * * * cd /srv/ai_lms && RAILS_ENV=production bundle exec rake payments:recover
15 3 * * * cd /srv/ai_lms && RAILS_ENV=production bundle exec rake payments:prune_events
```

`payments:recover` dispatches unprocessed/failed inbox entries older than one minute and reconciles relevant non-expired purchases at least hourly. It continues with checkout disabled. Open attempts (created in the last 7 days) and fulfilment exceptions are reconciled hourly. Paid and disputed purchases from the last 180 days are reconciled daily so missed refund/dispute events are repaired; refunded, lost and expired purchases are terminal and are not rescanned. At larger purchase volumes, move this scan to batched scheduling with a rate budget before increasing volume.

A successful dispatch updates the heartbeat shown in Payments settings. Live checkout requires a heartbeat less than ten minutes old. Exceptions and inbox items older than fifteen minutes produce a nonzero task exit and an alert message. Monitor cron failure, worker availability, oldest pending event, and paid-but-unfulfilled purchases. Verify that the alert reaches a human; merely retaining a log is insufficient.

Admin → Site settings → Payments → Manage purchases and access grants shows exceptions and offers safe retries. Fix credentials/configuration or course availability, then retry. A retry reads current Stripe facts and cannot restore an explicitly revoked grant. Resolve duplicate-charge exceptions with a Stripe Dashboard refund. Do not delete the purchase or edit its snapshots.

Checkout requests use a committed local attempt and stable Stripe idempotency key. Ambiguous attempts older than 23 hours are recovered by listing existing sessions, never by creating another session with a potentially expired idempotency key. If no session is found, the purchase is flagged `ambiguous_checkout_attempt`. When the buyer next starts checkout, the attempt is retired automatically: sessions are searched again by attempt key, any open session is expired through Stripe, and a new attempt is created. If the session was already completed, it is reconciled at the price the buyer paid instead of being replaced. The same retirement applies when the course price, currency, tax settings or application URL changed since the attempt was created, so buyers are never sent to a session quoting old terms. Attempts made on a previous Stripe account or mode are not retired automatically; checkout reports payments unavailable until an operator resolves them.

## Retention and access boundaries

- Stripe retains provider financial facts. The LMS retains immutable purchase snapshots, grant records and their append-only application audit events independently of enrolments. Purchases and grants block destructive course/user deletion. Use course unpublishing and paid-course withdrawal (which archives participation).
- The payment inbox stores event/account/object identifiers only, never full Stripe payloads, card data or billing addresses. Processed identifiers are pruned after 90 days; replay remains safe because fulfilment and grant operations are independently repeat-safe. Failed events remain for investigation. Error summaries exclude provider response bodies.
- User deletion with retained history is intentionally blocked. Before live sales the operator must approve a retention/anonymisation policy for local identity and learning records; anonymise identity through a reviewed administrative process while preserving stable IDs and financial/audit references. There is no automatic destructive financial-history purge or legal retention period assumed by the application. Keep sensitive personal details out of grant reasons. This is an operational policy decision, not an LMS tax engine.
- Test purchase grants are ineffective when the configured account/mode does not match. Manual grants are independent. Never use production learner data in a test database.
- Keep object storage private. Learning files use authenticated proxies and `private, no-store`; redirect routes for protected files lead to proxies. Previously issued object-storage/disk URLs and already-downloaded files cannot be recalled. Wait out the configured service URL lifetime after changing storage settings. Public/unlisted external videos cannot be revoked at their host.
- Course covers are marketing assets. Certificate backgrounds are restricted to authors/admins. Earned certificates and public verification remain available after refunds or revocation.
- The token lesson API now also enforces session-based lesson authorization. External consumers of paid lesson metadata must use an authorized learner session; the shared tutor token alone does not grant paid access.
- Rollback means disabling new checkout while keeping access enforcement, webhooks and recovery running. Do not deploy pre-entitlement authorization code after selling courses. After a database restore, run reconciliation before reopening checkout.

## Required verification

Per AGENTS.md, a human runs Rails tests against local PostgreSQL. Start with:

```sh
bin/rails test test/controllers/admin/stripe_settings_test.rb test/services/entitlements test/services/payments test/controllers/paid_course_access_test.rb test/controllers/purchases_controller_test.rb test/controllers/stripe_webhooks_controller_test.rb test/jobs/payment_event_job_test.rb
bin/rails test test/models/ability_test.rb test/models/enrollment_test.rb test/controllers/active_storage_access_control_test.rb test/controllers/enrollments_controller_test.rb test/controllers/lessons_controller_test.rb test/controllers/lesson_materials_controller_test.rb test/controllers/progresses_controller_test.rb test/controllers/sso_enforcement_test.rb
bin/rails test
```

Run these staging checks with real Stripe test-mode deliveries, without live charges:

- Free browsing, enrolment and learning with Stripe unconfigured and payments disabled; owner/admin drafts and SSO policy unchanged.
- Paid catalogue displays cover, description, price and syllabus titles only. Direct lesson, start, quiz, progress, material, design, tutor/token API, blob redirect/proxy, representation, variant and rich-text URLs deny unauthorized access.
- A valid purchase fulfils without a browser return. A return/webhook race, duplicate event, double-click and multiple tabs produce one fulfilment/grant/enrolment. Confirm provider session reuse, not just database deduplication.
- Declined, cancelled, expired and unpaid sessions do not grant access; an expired session can be replaced. Tampered signature, foreign session, wrong amount/currency/account/mode are rejected.
- Prerequisites block checkout; a later prerequisite change honours recorded eligibility. Repricing honours the open quote. Unpublishing after checkout records payment but raises a fulfilment exception.
- Partial refund retains access, full refund revokes only its grant. Open/lost/won disputes suspend/revoke/restore appropriately. A late success cannot undo refund or independent revocation. Manual grants survive Stripe refunds.
- Withdrawal archives participation, rejoin reuses access, and revocation retains progress and certificates. Free→paid conversion creates audited grants atomically for enrolled learners; paid→free preserves financial history.
- Stop Redis or the worker, deliver a webhook, restart, and verify inbox recovery. Replay events out of order. Suppress refund delivery and verify hourly reconciliation. Simulate checkout creation timeout and restart; verify the same session is recovered. Test the old ambiguous-attempt support path.
- Exercise admin grants/revocation/retries, changing currency, disabling new payments, alert delivery, backups and restore/reconciliation. Confirm test grants cannot unlock production access.

Record test output and staging evidence in issue #166 before checking live readiness.
