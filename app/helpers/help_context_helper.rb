# Live page context for Ask Us (passed as additional_context on the help Cbai iframe).
# Keep this free of secrets — ids, slugs, and titles only.
module HelpContextHelper
  def ask_help_context_string(namespace: "admin")
    parts = [
      "Role: #{namespace}",
      "Path: #{request.path}"
    ]

    if defined?(@course) && @course.respond_to?(:persisted?) && @course.persisted?
      parts << "Course: #{@course.title} (slug: #{@course.slug})"
    end

    if defined?(@lesson) && @lesson.respond_to?(:persisted?) && @lesson.persisted?
      parts << "Lesson: #{@lesson.title} (id: #{@lesson.id})"
    end

    if defined?(@user) && @user.respond_to?(:persisted?) && @user.persisted? && namespace.to_s == "admin"
      parts << "Viewing user id: #{@user.id}"
    end

    parts.join(". ")
  end

  # Dashboard hosts the help Cbai page; LMS only iframes it (same as chatbar-ai-search-fullstack Ask Us).
  def ask_help_dashboard_base_url
    ENV["CBAI_BASE_URL"].presence ||
      (Rails.env.development? ? "http://127.0.0.1:3000" : "https://dashboard.chatbar-ai.com")
  end

  def ask_help_iframe_url(token:, context:)
    base = ask_help_dashboard_base_url.to_s.chomp("/")
    "#{base}/cbais/#{CGI.escape(token.to_s)}?additional_context=#{CGI.escape(context.to_s)}"
  end
end
