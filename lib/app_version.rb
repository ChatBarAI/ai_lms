# Reports which commit of the app is running, so admins can match a deployed
# instance against GitHub. bin/deploy writes the commit into a REVISION file in
# each release (the server has no .git); APP_REVISION covers other builds, and
# development falls back to asking git.
module AppVersion
  REPOSITORY_URL = "https://github.com/ChatBarAI/ai_lms".freeze
  LICENSE_URL = "#{REPOSITORY_URL}/blob/main/LICENSE".freeze
  # Keep in step with the copyright line in LICENSE.
  COPYRIGHT = "© 2026 ChatBar AI PTE LTD".freeze
  SHA_PATTERN = /\A(\h{40})(-dirty)?/

  module_function

  def revision
    @revision ||= detect_revision
  end

  def sha
    revision[SHA_PATTERN, 1]
  end

  def short_sha
    sha&.first(7)
  end

  def dirty?
    revision.match(SHA_PATTERN)&.[](2).present?
  end

  # Commit history starting at the running commit (GitHub can't highlight a
  # commit within commits/main, so this puts it at the top instead).
  def history_url
    "#{REPOSITORY_URL}/commits/#{sha}" if sha
  end

  # Commits on main that this instance does not have yet.
  def whats_new_url
    "#{REPOSITORY_URL}/compare/#{sha}...main" if sha
  end

  def label
    return "unknown" unless sha

    dirty? ? "#{short_sha}-dirty" : short_sha
  end

  def reset!
    @revision = nil
  end

  def detect_revision(root: Rails.root, env: ENV)
    from_file(root.join("REVISION")) ||
      env["APP_REVISION"].to_s.strip.presence ||
      from_git(root) ||
      "unknown"
  end

  def from_file(path)
    File.read(path).strip.presence if File.file?(path)
  end

  def from_git(root)
    return unless File.exist?(root.join(".git"))

    sha = IO.popen([ "git", "-C", root.to_s, "rev-parse", "--verify", "HEAD" ], err: File::NULL, &:read).to_s.strip
    return unless $?.success? && sha.match?(/\A\h{40}\z/)

    clean = system("git", "-C", root.to_s, "diff", "--quiet", "HEAD", out: File::NULL, err: File::NULL)
    clean ? sha : "#{sha}-dirty"
  rescue SystemCallError
    nil
  end
end
