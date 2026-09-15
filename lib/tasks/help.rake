# frozen_string_literal: true

namespace :help do
  desc "Print local Ask Us setup checklist (dashboard Cbai + ai_search + LMS SiteSetting)"
  task setup: :environment do
    setting = SiteSetting.current
    puts <<~MSG
      Ask Us — local setup
      ====================

      Stack reminder:
        dashboard (Cbai + chunks) → ai_search (vectors) → LMS (panel + token)

      1) On ChatBar dashboard (chatbar-ai-search-fullstack):
         - Create a Cbai for LMS help (suggested token: help-lms-admin)
         - Enable it after chunks exist
         - Point it at your ai_search server config

      2) Seed knowledge (pick one):
         - Paste manuals into the dashboard Cbai, or
         - Run:  rake help:export_guides && rake help:generate[admin]
           then upload tmp/help_guides_export.md (or tmp/help_pages/*.md) as chunks
         - Sync / reload_website_txts so ai_search embeds them

      3) In this LMS:
         - Admin → Settings → Integration → Ask Us help
         - Paste the Cbai token into "Admin help ChatBar token"
         - Turn on "Enable Ask Us"
         - Save

      Current LMS SiteSetting:
        help_enabled:            #{setting.help_enabled?}
        help_admin_token:        #{setting.help_admin_token.presence || "(blank)"}
        help_instructor_token:   #{setting.help_instructor_token.presence || "(blank)"}
        ask_help admin ready:    #{setting.ask_help_available_for?(:admin)}
        ask_help instructor ready: #{setting.ask_help_available_for?(:instructor)}
    MSG
  end

  desc "Export docs/guides manuals into tmp/ for seeding the dashboard help Cbai"
  task export_guides: :environment do
    sources = [
      "docs/guides/admin-manual.md",
      "docs/guides/instructor-manual.md",
      "docs/guides/student-manual.md",
      "docs/guides/lms-image-sizes-guide.md",
      "docs/guides/enrolment-gating-staging-qa.md"
    ].map { |rel| Rails.root.join(rel) }.select(&:exist?)

    abort "ERROR: no guide markdown found under docs/guides/" if sources.empty?

    out_dir = Rails.root.join("tmp/help_guides")
    FileUtils.mkdir_p(out_dir)

    combined = +""
    sources.each do |path|
      body = path.read
      combined << "# #{path.basename(".md")}\n\n#{body}\n\n---\n\n"
      File.write(out_dir.join(path.basename), body)
      puts "  wrote #{out_dir.join(path.basename)}"
    end

    combined_path = Rails.root.join("tmp/help_guides_export.md")
    File.write(combined_path, combined)
    puts "\nCombined export: #{combined_path}"
    puts "Upload these into the dashboard help Cbai, then sync to ai_search."
    puts "Then: rake help:setup"
  end

  desc "Generate help markdown from config/help_pages + -# HELP: comments (no LLM)"
  task :generate, [ :namespace ] => :environment do |_t, args|
    namespace = (args[:namespace].presence || "admin").to_s
    pages = Help::PageCodeAssembler.load_all_pages(namespace)
    abort "ERROR: no pages in config/help_pages/#{namespace}.yml" if pages.empty?

    out_dir = Rails.root.join("tmp/help_pages", namespace)
    FileUtils.mkdir_p(out_dir)

    combined = +"# LMS help pages (#{namespace})\n\nGenerated from source + -# HELP: comments.\n\n"
    pages.each do |page_key, config|
      md = Help::PageCodeAssembler.new(page_key, config, namespace: namespace).to_markdown
      path = out_dir.join("#{page_key}.md")
      File.write(path, md)
      combined << "#{md}\n\n---\n\n"
      puts "  wrote #{path} (#{md.scan(/### /).size} HELP blocks)"
    end

    combined_path = Rails.root.join("tmp/help_pages_#{namespace}_export.md")
    File.write(combined_path, combined)
    puts "\nCombined: #{combined_path}"
    puts "Upload into the dashboard help Cbai, then sync to ai_search."
  end

  desc "List help page keys for a namespace"
  task :pages, [ :namespace ] => :environment do |_t, args|
    namespace = (args[:namespace].presence || "admin").to_s
    Help::PageCodeAssembler.page_keys(namespace).each { |k| puts k }
  end

  desc "Show Ask Us configuration status"
  task status: :environment do
    setting = SiteSetting.current
    puts "help_enabled=#{setting.help_enabled?}"
    puts "admin_token=#{setting.help_admin_token.presence || '(blank)'} ready=#{setting.ask_help_available_for?(:admin)}"
    puts "instructor_token=#{setting.help_instructor_token.presence || '(blank)'} ready=#{setting.ask_help_available_for?(:instructor)}"
    puts "admin_pages=#{Help::PageCodeAssembler.page_keys('admin').size}"
  end
end
