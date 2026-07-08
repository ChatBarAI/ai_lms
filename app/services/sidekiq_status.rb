require "sidekiq/api"
require "uri"

class SidekiqStatus
  Result = Struct.new(
    :available,
    :error,
    :redis_url,
    :processes,
    :default_queue_size,
    :retry_size,
    :dead_size,
    :scheduled_size,
    keyword_init: true
  ) do
    def running?
      available && processes.any?
    end

    def default_queue_running?
      running? && processes.any? { |process| process[:queues].include?("default") }
    end
  end

  def self.current
    new.call
  end

  def call
    Result.new(
      available: true,
      redis_url: masked_redis_url,
      processes: processes,
      default_queue_size: Sidekiq::Queue.new("default").size,
      retry_size: Sidekiq::RetrySet.new.size,
      dead_size: Sidekiq::DeadSet.new.size,
      scheduled_size: Sidekiq::ScheduledSet.new.size
    )
  rescue => e
    Result.new(
      available: false,
      error: "#{e.class}: #{e.message}",
      redis_url: masked_redis_url,
      processes: [],
      default_queue_size: nil,
      retry_size: nil,
      dead_size: nil,
      scheduled_size: nil
    )
  end

  private

  def processes
    Sidekiq::ProcessSet.new.map do |process|
      {
        identity: process["identity"].presence || process["hostname"].presence || "unknown",
        hostname: process["hostname"],
        tag: process["tag"],
        queues: Array(process["queues"]).map(&:to_s),
        busy: process["busy"].to_i,
        concurrency: process["concurrency"].to_i,
        started_at: process["started_at"] && Time.zone.at(process["started_at"].to_f)
      }
    end.sort_by { |process| [ process[:hostname].to_s, process[:identity].to_s ] }
  end

  def masked_redis_url
    raw_url = SiteSetting.current.redis_url.presence || ENV["REDIS_URL"].presence || "redis://localhost:6379/0"
    uri = URI.parse(raw_url)
    uri.password = "[FILTERED]" if uri.password.present?
    uri.to_s
  rescue URI::InvalidURIError
    "Invalid Redis URL"
  end
end
