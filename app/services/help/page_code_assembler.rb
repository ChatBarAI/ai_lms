# frozen_string_literal: true

# Assembles view/controller source for a help page (incl. -# HELP: comments).
# ponytail: no HelperContextExtractor / LLM — export markdown from comments + tasks.
module Help
  class PageCodeAssembler
    MAX_PARTIAL_DEPTH = 8

    def self.manifest_path(namespace)
      Rails.root.join("config", "help_pages", "#{namespace}.yml")
    end

    def self.load_all_pages(namespace)
      path = manifest_path(namespace)
      return {} unless path.exist?

      YAML.load_file(path) || {}
    end

    def self.page_keys(namespace)
      load_all_pages(namespace).keys
    end

    def initialize(page_key, config, namespace:)
      @page_key = page_key
      @config = config.with_indifferent_access
      @namespace = namespace
      @collected = {}
    end

    def assemble
      Array(@config["entry_files"]).each do |spec|
        if spec.include?("#")
          path, = spec.split("#", 2)
          collect_file(path)
        else
          collect_view_with_partials(spec)
        end
      end
      collect_file("app/views/layouts/admin.html.haml") if @namespace.to_s == "admin"
      collect_file("app/views/shared/_ask_help_panel.html.haml")
      {
        page_key: @page_key,
        url: @config["url"],
        title: @config["title"],
        user_tasks: Array(@config["user_tasks"]),
        help_comments: extract_help_comments,
        files: @collected.transform_values { |h| h[:content] }
      }
    end

    def to_markdown
      ctx = assemble
      lines = []
      lines << "# #{ctx[:title]}"
      lines << ""
      lines << "Page key: `#{ctx[:page_key]}`"
      lines << "URL: `#{ctx[:url]}`"
      lines << ""
      if ctx[:user_tasks].any?
        lines << "## What you can do here"
        ctx[:user_tasks].each { |t| lines << "- #{t}" }
        lines << ""
      end
      if ctx[:help_comments].any?
        lines << "## Author notes (from -# HELP: comments)"
        ctx[:help_comments].each do |block|
          lines << ""
          lines << "### #{block[:title]}"
          lines << block[:body] if block[:body].present?
        end
        lines << ""
      end
      lines << "## Source files included"
      ctx[:files].keys.sort.each { |path| lines << "- `#{path}`" }
      lines.join("\n")
    end

    private

    def collect_view_with_partials(path, depth = 0)
      return if depth > MAX_PARTIAL_DEPTH
      return unless collect_file(path)

      content = @collected[path][:content]
      find_partial_references(content, File.dirname(path)).each do |partial|
        collect_view_with_partials(partial, depth + 1)
      end
    end

    def collect_file(path)
      return false if @collected.key?(path)

      full = Rails.root.join(path)
      return false unless full.exist?

      @collected[path] = { content: full.read }
      true
    end

    def find_partial_references(content, base_dir)
      names = []
      content.scan(/render\s+(?:partial:\s*)?['"]([^'"]+)['"]/) { |m| names << m[0] }
      names.filter_map { |name| resolve_partial_path(name, base_dir) }.uniq
    end

    def resolve_partial_path(name, base_dir)
      name = name.sub(/\A_/, "")
      if name.include?("/")
        dir = File.dirname(name)
        file = File.basename(name)
        search_dir = "app/views/#{dir}"
      else
        search_dir = base_dir
        file = name
      end

      %w[.html.haml .haml .html.erb].each do |ext|
        candidate = "#{search_dir}/_#{file}#{ext}"
        return candidate if Rails.root.join(candidate).exist?
      end
      nil
    end

    def extract_help_comments
      blocks = []
      @collected.each_value do |data|
        lines = data[:content].to_s.lines.map(&:chomp)
        i = 0
        while i < lines.length
          line = lines[i]
          if line =~ /\A\s*-#\s*HELP:\s*(.*)\z/
            title = Regexp.last_match(1).to_s.strip
            body_lines = []
            i += 1
            while i < lines.length && lines[i] =~ /\A\s*-#\s*(.*)\z/
              body_lines << Regexp.last_match(1).to_s.strip
              i += 1
            end
            blocks << { title: title.presence || "Note", body: body_lines.join("\n").presence }
            next
          end
          i += 1
        end
      end
      blocks
    end
  end
end
