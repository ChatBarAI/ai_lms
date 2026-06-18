require "net/http"
require "uri"
require "json"

# Talks to the chatbar-ai dashboard API on behalf of a Lesson.
# Uses the lesson's stored CBAI token + API key.
class CbaiClient
  class Error < StandardError; end

  DEFAULT_BASE_URL = ENV.fetch("CBAI_BASE_URL", "https://dashboard.chatbar-ai.com").freeze
  ALLOWED_HOSTS = %w[dashboard.chatbar-ai.com].freeze

  def initialize(api_key:, base_url: DEFAULT_BASE_URL)
    @api_key = api_key.to_s.strip
    @base_url = base_url
    raise Error, "Missing CBAI API key" if @api_key.empty?
  end

  # Returns an Array of recording hashes (or raises CbaiClient::Error).
  def recordings
    uri = build_uri("/api/cbai/recordings")
    body = get(uri)
    JSON.parse(body)
  rescue JSON::ParserError => e
    raise Error, "Invalid JSON from CBAI: #{e.message}"
  end

  # Returns a Hash of instance details (including the token) for the API key.
  def details
    uri = build_uri("/api/cbai/details")
    body = get(uri)
    JSON.parse(body)
  rescue JSON::ParserError => e
    raise Error, "Invalid JSON from CBAI: #{e.message}"
  end

  # Yields a Tempfile containing the recording binary; caller owns the file.
  def download_recording(recording_id, &block)
    uri = build_uri("/api/cbai/recordings/#{recording_id}/download")
    download_to_tempfile(uri, &block)
  end

  # Submits a Task to the ChatBar AI Task API. Returns the parsed response hash.
  # `payload` is the `task` hash to send as the JSON body.
  def create_task(payload:)
    uri = build_uri("/api/cbai/tasks")
    body = post_json(uri, { task: payload })
    JSON.parse(body)
  rescue JSON::ParserError => e
    raise Error, "Invalid JSON from CBAI Task API: #{e.message}"
  end

  # Notifies the ChatBar AI dashboard that a task has completed.
  # `cbai_task_id` is the integer task ID returned by create_task.
  # Status 30 = completed per the chatbar-ai Task::STATUS constant.
  def update_task(cbai_task_id:, status: 30)
    uri = build_uri("/api/tasks/update/#{cbai_task_id}")
    patch_json(uri, { task: { status: status } })
  end

  # Asks the CBAI to rate how correct a free-text answer is.
  # Returns an integer 1..10, or raises CbaiClient::Error.
  def score_answer(question:, student_answer:, expected_answer:)
    prompt = "Given the following question \"#{question}\", " \
             "the answer \"#{student_answer}\", " \
             "and the expected answer \"#{expected_answer}\", " \
             "provide a rating of the correctness between 1 and 10, " \
             "where 10 is completely correct. " \
             "Only provide the number in your answer nothing else."
    uri = build_uri("/api/cbai/query")
    body = post_json(uri, { query: prompt })
    parsed = JSON.parse(body)
    score = parsed["answer"].to_s.strip.to_i
    raise Error, "Unexpected score value: #{parsed["answer"].inspect}" unless (1..10).cover?(score)
    score
  rescue JSON::ParserError => e
    raise Error, "Invalid JSON from CBAI query: #{e.message}"
  end

  private

  def post_json(uri, body_hash)
    request_with_json_body(Net::HTTP::Post, uri, body_hash)
  end

  def patch_json(uri, body_hash)
    request_with_json_body(Net::HTTP::Patch, uri, body_hash)
  end

  def request_with_json_body(http_method_class, uri, body_hash)
    Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: 10, read_timeout: 30) do |http|
      req = http_method_class.new(uri.request_uri)
      req["Authorization"] = @api_key
      req["Content-Type"] = "application/json"
      req["Accept"] = "application/json"
      req.body = JSON.generate(body_hash)
      res = http.request(req)
      case res
      when Net::HTTPSuccess
        res.body
      else
        raise Error, "CBAI API error #{res.code}: #{res.body.to_s[0, 200]}"
      end
    end
  rescue SocketError, Errno::ECONNREFUSED, Errno::ETIMEDOUT, Net::OpenTimeout, Net::ReadTimeout => e
    raise Error, "CBAI API network error: #{e.class}: #{e.message}"
  end


  def build_uri(path)
    uri = URI.parse(@base_url + path)
    unless %w[http https].include?(uri.scheme) &&
           (ALLOWED_HOSTS.include?(uri.host) || @base_url != DEFAULT_BASE_URL)
      raise Error, "Refusing to call non-allowlisted host: #{uri.host}"
    end
    uri
  end

  def get(uri, redirects_left: 3)
    Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: 10, read_timeout: 30) do |http|
      req = Net::HTTP::Get.new(uri.request_uri)
      req["Authorization"] = @api_key
      req["Accept"] = "application/json"
      res = http.request(req)
      case res
      when Net::HTTPSuccess
        res.body
      when Net::HTTPRedirection
        raise Error, "Too many redirects" if redirects_left <= 0
        get(build_uri(URI.parse(res["Location"]).request_uri), redirects_left: redirects_left - 1)
      else
        raise Error, "CBAI API error #{res.code}: #{res.body.to_s[0, 200]}"
      end
    end
  end

  def download_to_tempfile(uri, redirects_left: 5, &block)
    file = Tempfile.new([ "cbai-recording", ".bin" ], binmode: true)
    Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: 10, read_timeout: 120) do |http|
      req = Net::HTTP::Get.new(uri.request_uri)
      # Only send our Authorization header to the chatbar host; never to the
      # final signed-URL host (which already authenticates via the signature).
      req["Authorization"] = @api_key if ALLOWED_HOSTS.include?(uri.host)
      http.request(req) do |res|
        case res
        when Net::HTTPSuccess
          res.read_body { |chunk| file.write(chunk) }
        when Net::HTTPRedirection
          file.close!
          raise Error, "Too many redirects" if redirects_left <= 0
          next_uri = URI.parse(res["Location"])
          next_uri = URI.join(uri, next_uri) unless next_uri.absolute?
          return download_to_tempfile(next_uri, redirects_left: redirects_left - 1, &block)
        else
          file.close!
          raise Error, "CBAI download error #{res.code}: #{res.body.to_s[0, 200]}"
        end
      end
    end
    file.rewind
    yield file
  ensure
    file.close! if file && !file.closed?
  end
end
