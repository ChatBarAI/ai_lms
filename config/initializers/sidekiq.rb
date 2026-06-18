# Redis URL resolution order:
#   1. SiteSetting#redis_url  (set by admin in Site Settings UI — takes precedence)
#   2. REDIS_URL env var       (set in the server environment)
#   3. redis://localhost:6379/0 fallback
#
# Each deployed instance of this app must use a different Redis database number
# (0–15) so queues and job data stay isolated. Change the DB number in the admin
# Site Settings page, then restart the server and Sidekiq worker.
resolve_redis_url = lambda do
  url = begin
    SiteSetting.first&.redis_url.presence
  rescue => e
    Rails.logger.warn("[Sidekiq] Could not read redis_url from SiteSetting: #{e.message}")
    nil
  end

  url ||= ENV["REDIS_URL"].presence
  if url.nil?
    if Rails.env.production?
      Rails.logger.warn("[Sidekiq] REDIS_URL is not set; falling back to localhost. Set REDIS_URL or configure it via Admin › Site Settings.")
    end
    url = "redis://localhost:6379/0"
  end
  url
end

Rails.application.config.after_initialize do
  Sidekiq.configure_server do |config|
    config.redis = { url: resolve_redis_url.call }
  end

  Sidekiq.configure_client do |config|
    config.redis = { url: resolve_redis_url.call }
  end
end
