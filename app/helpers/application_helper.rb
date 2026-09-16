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
  #   crop_size:           Optional [width, height] from the LMS image sizes guide. Enables
  #                        Cropper.js zoom/crop for raster images; omit for free-aspect crop.
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
                   required: false,
                   crop_size: nil)
    parts = []
    has_current_attachment = current_attachment&.attached?
    croppable = preview_type == :image

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
    crop_source_url = croppable && has_current_attachment && !current_attachment.content_type.to_s.include?("svg") ? initial_preview_src : nil

    input_actions = [ "change->file-preview#update" ]
    input_actions << "change->image-crop#fileChanged" if croppable
    input_data = { "file-preview-target": "input", action: input_actions.join(" ") }
    input_data["image-crop-target"] = "input" if croppable

    # ── Hidden native file input (screen-reader accessible; JS triggers .click()) ──
    parts << content_tag(:p, hint, class: "text-sm font-medium mb-2") if hint.present?
    parts << f.label(attribute, label, class: "sr-only")
    parts << f.file_field(attribute,
                          accept: accept,
                          required: required,
                          class: "sr-only",
                          data: input_data)

    # ── Styled drop zone (contains placeholder ↔ preview) ──────────────────
    # Layout matches Brod's PR #49 mock: preview + Adjust/Replace inside dashed box.
    parts << content_tag(:div,
      class: [
        "border-2 border-dashed rounded-lg p-6 text-center cursor-pointer transition-colors",
        show_initial_preview ? "border-indigo-400 bg-indigo-50/30" : "border-gray-300 hover:border-indigo-400 hover:bg-indigo-50/40",
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
            safe_join([
              upload_field_icon,
              content_tag(:p, class: "mt-3 text-sm text-gray-700 dark:text-gray-300 pointer-events-none") {
                safe_join([
                  content_tag(:span, "Browse files", class: "font-semibold text-indigo-600 dark:text-indigo-400"),
                  " or drag and drop"
                ])
              },
              content_tag(:p, label, class: "mt-1 text-xs text-gray-400 dark:text-gray-500 pointer-events-none")
            ])
          end,

          # ── Selection / current preview ───────────────────────────────────
          content_tag(:div, class: [ ("hidden" unless show_initial_preview) ].compact.join(" "), data: { "file-preview-target": "previewContainer" }) do
            nodes = []
            if preview_type == :image
              preview_data = { "file-preview-target": "preview" }
              preview_data["image-crop-target"] = "preview" if croppable
              nodes << image_tag(initial_preview_src.to_s, alt: "Preview",
                        class: "max-h-28 max-w-full mx-auto rounded object-contain pointer-events-none",
                        data: preview_data)
            end
            nodes << content_tag(:p, initial_filename.to_s, class: "text-xs text-gray-600 dark:text-gray-400 mt-2 font-mono pointer-events-none",
                                         data: { "file-preview-target": "filename" })

            if croppable
              nodes << content_tag(:div, class: "mt-3 flex flex-wrap items-center justify-center gap-2") do
                safe_join([
                  tag.button("Adjust image",
                             type: "button",
                             class: "hidden inline-flex items-center rounded border border-indigo-300 bg-white px-3 py-1.5 text-xs font-medium text-indigo-700 hover:bg-indigo-50",
                             data: { "image-crop-target": "adjustButton", action: "click->image-crop#open:stop" }),
                  tag.button("Replace image",
                             type: "button",
                             class: "inline-flex items-center rounded border border-gray-300 bg-white px-3 py-1.5 text-xs font-medium text-gray-800 hover:bg-gray-50",
                             data: { action: "click->file-preview#openPicker:stop" })
                ])
              end
            else
              nodes << content_tag(:div, class: "mt-3") do
                tag.button("Replace file",
                           type: "button",
                           class: "inline-flex items-center rounded border border-gray-300 bg-white px-3 py-1.5 text-xs font-medium text-gray-800 hover:bg-gray-50",
                           data: { action: "click->file-preview#openPicker:stop" })
              end
            end

            nodes << content_tag(:p, "or drag and drop to replace", class: "mt-2 text-xs text-gray-500 pointer-events-none")
            nodes << content_tag(:p, label, class: "mt-1 text-xs text-gray-400 dark:text-gray-500 pointer-events-none")
            safe_join(nodes)
          end
        ])
    end

    parts << image_crop_dialog if croppable

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

    wrapper_data = {
      controller: croppable ? "file-preview image-crop" : "file-preview",
      "file-preview-type-value": preview_type.to_s
    }
    if croppable && crop_size.is_a?(Array) && crop_size.size == 2
      wrapper_data["image-crop-width-value"] = crop_size[0]
      wrapper_data["image-crop-height-value"] = crop_size[1]
    end
    wrapper_data["image-crop-source-url-value"] = crop_source_url if crop_source_url.present?

    content_tag(:div, safe_join(parts), data: wrapper_data)
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

  # Cropper.js dialog for image upload_field wrappers (Adjust button lives in the drop zone).
  def image_crop_dialog
    tag.dialog(
      class: "m-0 h-dvh w-screen max-w-none max-h-none border-0 bg-slate-950 p-0 text-white backdrop:bg-black/70",
      aria: { label: "Adjust image" },
      data: { "image-crop-target": "dialog", action: "cancel->image-crop#cancel" }
    ) do
      content_tag(:div, class: "flex h-full min-h-0 flex-col") do
        safe_join([
          content_tag(:div, class: "flex shrink-0 flex-wrap items-center justify-between gap-3 border-b border-slate-700 bg-slate-900 px-4 py-3") do
            safe_join([
              content_tag(:div) do
                safe_join([
                  content_tag(:h2, "Adjust image", class: "text-base font-semibold"),
                  content_tag(:p, "Zoom and crop, then use the selected area.", class: "text-xs text-slate-300")
                ])
              end,
              content_tag(:div, class: "flex flex-wrap items-center gap-2") do
                safe_join([
                  tag.button("Cancel", type: "button",
                             class: "rounded border border-slate-500 bg-slate-800 px-3 py-2 text-sm font-medium text-white hover:bg-slate-700",
                             data: { action: "image-crop#cancel" }),
                  tag.button("Use cropped image", type: "button",
                             class: "rounded bg-indigo-600 px-3 py-2 text-sm font-medium text-white hover:bg-indigo-500",
                             data: { action: "image-crop#use" })
                ])
              end
            ])
          end,
          content_tag(:div, class: "flex min-h-0 flex-1 items-center justify-center overflow-hidden p-4") do
            tag.img(alt: "Image to crop",
                    class: "block max-h-full max-w-full",
                    data: { "image-crop-target": "image" })
          end,
          content_tag(:p, "",
                      role: "status",
                      class: "shrink-0 px-4 pb-3 text-xs text-gray-500",
                      data: { "image-crop-target": "status" })
        ])
      end
    end
  end

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
