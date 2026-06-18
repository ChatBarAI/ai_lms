module ApplicationHelper
  TOGGLE_TRACK_CLASSES = "cb-toggle-track".freeze

  def preview_text_for(field, course)
    case field
    when "name"           then "Student Name"
    when "course_title"   then course&.title.presence || "Course Title"
    when "date"           then I18n.l(Date.current, format: :long)
    when "certificate_no" then "Certificate No: XXXX-XXXX-XXXX"
    else field.to_s.humanize
    end
  end

  # Renders a form-builder backed toggle switch with a visible text label.
  # Switch stays on the left; label text wraps on the right for long titles.
  def toggle_switch_field(form, attribute, label:, title: nil, wrapper_class: "", label_class: "text-sm text-gray-700", label_style: nil, checkbox_options: {})
    input_id = form.field_id(attribute)

    content_tag(:label,
                for: input_id,
                class: [ "flex items-start gap-2 cursor-pointer", wrapper_class.presence ].compact.join(" "),
                title: title) do
      safe_join([
        form.check_box(attribute, checkbox_options.merge(class: [ "sr-only peer", checkbox_options[:class] ].compact.join(" "))),
        content_tag(:div, "", class: "#{TOGGLE_TRACK_CLASSES} mt-0.5 shrink-0"),
        content_tag(:span, label, class: label_class, style: label_style)
      ])
    end
  end

  # Renders a check_box_tag backed toggle switch with a visible text label.
  def toggle_switch_tag(name, label:, checked: false, title: nil, id: nil, value: "1", wrapper_class: "", label_class: "text-sm text-gray-700", label_style: nil, include_hidden: true)
    input_id = id.presence || sanitized_checkbox_id(name)
    hidden = include_hidden ? hidden_field_tag(name, "0", id: nil) : "".html_safe

    content_tag(:label,
                for: input_id,
                class: [ "flex items-start gap-2 cursor-pointer", wrapper_class.presence ].compact.join(" "),
                title: title) do
      safe_join([
        hidden,
        check_box_tag(name, value, checked, id: input_id, class: "sr-only peer"),
        content_tag(:div, "", class: "#{TOGGLE_TRACK_CLASSES} mt-0.5 shrink-0"),
        content_tag(:span, label, class: label_class, style: label_style)
      ])
    end
  end

  # Renders a standardised file/image upload field with styled drop zone and live preview.
  #
  # Options:
  #   label:               Descriptive text shown inside the drop zone (file types / size hint).
  #   accept:              MIME-type string for the file input (e.g. "image/png,image/jpeg").
  #   hint:                Optional hint paragraph rendered below the drop zone.
  #   preview_type:        :image (default) shows an <img> preview; :file shows just the filename.
  #   current_attachment:  ActiveStorage::Attached::One for the current file.
  #   default_image_path:  Asset path shown when nothing is attached (e.g. "default-logo.png").
  #   default_image_note:  Note shown alongside the default image (e.g. "(default logo)").
  #   remove_name:         Param name for the "remove" checkbox (e.g. "course[remove_cover_image]").
  #                        Checkbox is only rendered when an attachment is present.
  #   remove_label:        Label text for the remove checkbox.
  #   preview_class:       CSS classes for the current and preview <img> elements.
  #   required:            Whether the file input is required.
  def upload_field(f, attribute, label:, accept:,
                   hint: nil,
                   preview_type: :image,
                   current_attachment: nil,
                   default_image_path: nil,
                   default_image_note: nil,
                   remove_name: nil,
                   remove_label: "Remove current file",
                   remove_actions: nil,
                   preview_class: "h-24 w-auto rounded border border-gray-200 object-cover",
                   required: false)
    parts = []
    has_current_attachment = current_attachment&.attached?

    initial_preview_src = nil
    initial_filename = nil

    if preview_type == :image
      if has_current_attachment
        initial_preview_src = rails_blob_path(current_attachment)
        initial_filename = "#{current_attachment.filename} (#{number_to_human_size(current_attachment.byte_size)})"
      elsif default_image_path.present?
        initial_preview_src = default_image_path
        initial_filename = default_image_note.presence || "Default image"
      end
    elsif has_current_attachment
      initial_filename = "#{current_attachment.filename} (#{number_to_human_size(current_attachment.byte_size)})"
    end

    show_initial_preview = initial_preview_src.present? || initial_filename.present?

    # ── Hidden native file input (screen-reader accessible; JS triggers .click()) ──
    parts << content_tag(:p, hint, class: "text-sm font-medium mb-2") if hint.present?
    parts << f.label(attribute, label, class: "sr-only")
    parts << f.file_field(attribute,
                          accept: accept,
                          required: required,
                          class: "sr-only",
                          data: {
                            "file-preview-target": "input",
                            action: "change->file-preview#update"
                          })

    # ── Styled drop zone (contains placeholder ↔ preview) ──────────────────
    parts << content_tag(:div,
      class: [
        "border-2 border-dashed rounded-lg p-4 text-center cursor-pointer transition-colors",
        "border-gray-300 hover:border-indigo-400 hover:bg-indigo-50/40",
        "dark:border-gray-600 dark:hover:border-indigo-400 dark:hover:bg-indigo-950/20",
        "data-[dragging]:border-indigo-500 data-[dragging]:bg-indigo-50/60",
        "dark:data-[dragging]:bg-indigo-950/30"
      ].join(" "),
      tabindex: 0,
      role: "button",
      "aria-label": label,
      data: {
        "file-preview-target": "dropzone",
        action: [
          "click->file-preview#openPicker",
          "keydown.enter->file-preview#openPicker",
          "keydown.space->file-preview#openPicker",
          "dragover->file-preview#dragover",
          "dragleave->file-preview#dragleave",
          "drop->file-preview#drop"
        ].join(" ")
      }) do
        safe_join([
          # ── Placeholder (shown when no file is selected) ──────────────────
          content_tag(:div, class: [ "py-4", ("hidden" if show_initial_preview) ].compact.join(" "), data: { "file-preview-target": "placeholder" }) do
            upload_field_icon
          end,

          # ── Selection preview (hidden until a file is picked or dropped) ───
          content_tag(:div, class: [ ("hidden" unless show_initial_preview) ].compact.join(" "), data: { "file-preview-target": "previewContainer" }) do
            nodes = []
            if preview_type == :image
              nodes << content_tag(:div,
                                   class: "mx-auto w-fit rounded-lg border border-gray-200 bg-gradient-to-br from-slate-50 via-white to-indigo-50 p-2 shadow-sm dark:border-gray-600 dark:from-gray-700 dark:via-gray-800 dark:to-indigo-950/40") do
                image_tag(initial_preview_src.to_s, alt: "Preview",
                          class: "max-h-24 max-w-full mx-auto rounded object-contain pointer-events-none",
                          data: { "file-preview-target": "preview" })
              end
            end
            nodes << content_tag(:p, initial_filename.to_s, class: "text-xs text-gray-600 dark:text-gray-400 mt-2 font-mono pointer-events-none",
                                         data: { "file-preview-target": "filename" })
            safe_join(nodes)
          end,

          # ── Persistent helper text (always visible) ───────────────────────
          content_tag(:div, class: "mt-3 pointer-events-none") do
            safe_join([
              content_tag(:p, class: "text-sm text-gray-700 dark:text-gray-300") {
                safe_join([
                  content_tag(:span, "Browse files", class: "font-semibold text-indigo-600 dark:text-indigo-400"),
                  "  or drag and drop"
                ])
              },
              content_tag(:p, label, class: "mt-1 text-xs text-gray-400 dark:text-gray-500"),
              content_tag(:p, "Click or drag to replace", class: "mt-1 text-xs text-gray-400")
            ])
          end
        ])
    end

    # ── Remove checkbox ─────────────────────────────────────────────────────
    if remove_name.present? && has_current_attachment
      remove_controls = []
      remove_controls << toggle_switch_tag(remove_name,
                                           label: remove_label,
                                           checked: false)
      remove_controls << content_tag(:div, remove_actions, class: "ml-auto") if remove_actions.present?

      parts << content_tag(:div,
                           safe_join(remove_controls),
                           class: "mt-2 flex w-full flex-wrap items-center gap-3")
    elsif remove_actions.present?
      parts << content_tag(:div,
                           remove_actions,
                           class: "mt-2 flex flex-wrap items-center gap-3")
    end

    content_tag(:div,
                safe_join(parts),
                data: {
                  controller: "file-preview",
                  "file-preview-type-value": preview_type.to_s
                })
  end

  # Renders a SiteSetting hero_content field, returning nil when blank.
  # Markdown mode:  parsed via Redcarpet; raw HTML in the source is escaped (safe).
  # HTML mode:      passed through Rails sanitize with the default allowlist (safe).
  def render_hero_content(site_setting)
    content = site_setting.hero_content.to_s.strip
    return nil if content.blank?

    case site_setting.hero_content_format
    when "html"
      sanitize(content)
    else # "markdown" (default)
      renderer = Redcarpet::Render::HTML.new(
        escape_html: true,
        hard_wrap: true,
        link_attributes: { rel: "noopener noreferrer" }
      )
      md = Redcarpet::Markdown.new(renderer,
        autolink: true,
        tables: true,
        fenced_code_blocks: true,
        strikethrough: true,
        superscript: true,
        highlight: true
      )
      sanitize(md.render(content), tags: Rails::Html::SafeListSanitizer.allowed_tags + %w[pre code])
    end
  end

  private

  def upload_field_icon
    # cloud-arrow-up (Heroicons outline)
    tag.svg(
      xmlns: "http://www.w3.org/2000/svg", viewBox: "0 0 24 24",
      fill: "none", stroke: "currentColor",
      "stroke-width": "1.5", "stroke-linecap": "round", "stroke-linejoin": "round",
      class: "mx-auto h-8 w-8 text-gray-400 pointer-events-none"
    ) do
      tag.path(d: "M12 16.5V9.75m0 0 3 3m-3-3-3 3M6.75 19.5a4.5 4.5 0 0 1-1.41-8.775 5.25 5.25 0 0 1 10.233-2.33 3 3 0 0 1 3.758 3.848A3.752 3.752 0 0 1 18 19.5H6.75Z")
    end
  end

  # Renders the chevron badge used as a toggle indicator for collapsible sections.
  # Pair with data: { controller: "collapsible" } on the wrapper and
  # data: { action: "click->collapsible#toggle" } on the header.
  def collapsible_icon_badge
    content_tag(:div,
      class: "bg-indigo-50 text-indigo-800 hover:bg-indigo-200 font-medium px-2.5 py-0.5 rounded-full text-xs inline-flex items-center border border-indigo-300 cursor-pointer"
    ) do
      content_tag(:span, "",
        class: "collapsible-icon",
        data: { collapsible_target: "icon" }
      )
    end
  end

  # Returns the correct edit path for a course based on the current user's role.
  # Admins are sent to the admin namespace; owners/instructors to the public namespace.
  def edit_course_path_for(course)
    current_user&.admin? ? edit_admin_course_path(course) : edit_course_path(course)
  end

  def sanitized_checkbox_id(name)
    name.to_s.gsub(/\]\[|[^-a-zA-Z0-9:.]/, "_").gsub(/_+/, "_").sub(/_\z/, "")
  end

  private :sanitized_checkbox_id
end
