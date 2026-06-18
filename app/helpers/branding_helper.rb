module BrandingHelper
  PWA_ICON_PIPELINE_REVISION = "r5".freeze

  # Caches the singleton across the request.
  def site_setting
    @_site_setting ||= SiteSetting.current
  end

  def site_brand_name
    site_setting.brand_name.presence || "ChatBar AI Learn"
  end

  def show_site_brand_name?
    site_setting.show_brand_name
  end

  def subjects_enabled?
    site_setting.subjects_enabled
  end

  def site_logo_tag(html_options = {})
    invert_class = site_setting.invert_logo_on_dark? ? " dark:invert" : ""
    options = { alt: site_brand_name, class: "h-8 w-auto#{invert_class}" }.merge(html_options)
    if site_setting.logo.attached?
      image_tag site_setting.logo, options
    else
      image_tag "default-logo.png", options
    end
  end

  def site_favicon_link_tag
    if site_setting.favicon.attached?
      tag.link rel: "icon", href: url_for(site_setting.favicon), type: site_setting.favicon.content_type
    else
      tag.link rel: "icon", href: "/favicon.png", type: "image/png"
    end
  end

  def site_favicon_img_tag(html_options = {})
    options = { alt: "", class: "h-4 w-4 brightness-0 invert" }.merge(html_options)
    image_tag "/favicon.png", options
  end

  def pwa_theme_color
    configured_brand_primary_color || "#2563eb"
  end

  def pwa_background_color
    if theme_mode_class == "theme-dark"
      site_setting.page_bg_dark.presence || "#111827"
    else
      site_setting.page_bg_light.presence || "#f9fafb"
    end
  end

  def pwa_apple_touch_background_color
    return "#ffffff" unless site_setting.favicon.attached? || site_setting.logo.attached?

    configured_brand_primary_color || "#ffffff"
  end

  def pwa_asset_version
    parts = [
      PWA_ICON_PIPELINE_REVISION,
      site_setting.updated_at&.to_i,
      (site_setting.favicon.attached? ? site_setting.favicon.blob_id : nil),
      (site_setting.logo.attached? ? site_setting.logo.blob_id : nil),
      (site_setting.pwa_screenshot_mobile.attached? ? site_setting.pwa_screenshot_mobile.blob_id : nil),
      (site_setting.pwa_screenshot_desktop.attached? ? site_setting.pwa_screenshot_desktop.blob_id : nil)
    ].compact

    parts.join("-")
  end

  def pwa_icon_source_label(setting = site_setting)
    return "Uploaded favicon" if setting.favicon.attached?
    return "Uploaded logo" if setting.logo.attached?

    "Built-in ChatBar fallback"
  end

  def pwa_manifest_screenshots(setting = site_setting)
    entries = []
    mobile = pwa_manifest_screenshot_entry(setting.pwa_screenshot_mobile, form_factor: "narrow", label: "App preview (mobile)")
    desktop = pwa_manifest_screenshot_entry(setting.pwa_screenshot_desktop, form_factor: "wide", label: "App preview (desktop)")
    entries << mobile if mobile
    entries << desktop if desktop
    entries
  end

  def default_meta_card_image_tag(html_options = {})
    if site_setting.default_meta_card_image.attached?
      image_tag site_setting.default_meta_card_image, html_options
    else
      image_tag "default-meta-card-image.jpg", html_options
    end
  end

  # CSS class to set on <html> based on the configured theme mode.
  # For "system", an inline script (theme_mode_script) swaps the class
  # to theme-light/theme-dark before paint based on prefers-color-scheme.
  def theme_mode_class
    case site_setting.theme_mode
    when "light" then "theme-light"
    when "dark"  then "theme-dark"
    else              "theme-system"
    end
  end

  # Inline script: when mode is "system", upgrade the html class to
  # theme-light or theme-dark based on the user's OS preference.
  def theme_mode_script
    js = "(function(){var c=document.documentElement;if(c.classList.contains('theme-system')){var d=window.matchMedia('(prefers-color-scheme: dark)').matches;c.classList.remove('theme-system');c.classList.add(d?'theme-dark':'theme-light');}})();"
    tag.script(js.html_safe)
  end

  # Emits a <style> block defining CSS variables for both theme-light
  # and theme-dark on <html>. The active class on <html> selects which set applies.
  def theme_style_tag
    s = site_setting
    light = {
      "--page-bg"      => s.page_bg_light.presence       || "#f9fafb",
      "--page-fg"      => s.page_fg_light.presence       || "#111827",
      "--card-bg"      => s.card_bg_light.presence       || "#ffffff",
      "--nav-bg"       => s.nav_bg_light.presence        || "#ffffff",
      "--nav-fg"       => s.nav_fg_light.presence        || "#374151",
      "--admin-nav-bg" => s.admin_nav_bg_light.presence  || "#111827",
      "--admin-nav-fg" => s.admin_nav_fg_light.presence  || "#ffffff",
      "--btn-primary-bg" => s.btn_primary_bg_light.presence || "#4f46e5",
      "--btn-primary-fg" => s.btn_primary_fg_light.presence || "#ffffff",
      "--btn-success-bg" => s.btn_success_bg_light.presence || "#16a34a",
      "--btn-success-fg" => s.btn_success_fg_light.presence || "#ffffff",
      "--btn-danger-bg"  => s.btn_danger_bg_light.presence  || "#dc2626",
      "--btn-danger-fg"  => s.btn_danger_fg_light.presence  || "#ffffff"
    }
    dark = {
      "--page-bg"      => s.page_bg_dark.presence        || "#111827",
      "--page-fg"      => s.page_fg_dark.presence        || "#f3f4f6",
      "--card-bg"      => s.card_bg_dark.presence        || "#1f2937",
      "--nav-bg"       => s.nav_bg_dark.presence         || "#1f2937",
      "--nav-fg"       => s.nav_fg_dark.presence         || "#d1d5db",
      "--admin-nav-bg" => s.admin_nav_bg_dark.presence   || "#030712",
      "--admin-nav-fg" => s.admin_nav_fg_dark.presence   || "#ffffff",
      "--btn-primary-bg" => s.btn_primary_bg_dark.presence || "#6366f1",
      "--btn-primary-fg" => s.btn_primary_fg_dark.presence || "#ffffff",
      "--btn-success-bg" => s.btn_success_bg_dark.presence || "#22c55e",
      "--btn-success-fg" => s.btn_success_fg_dark.presence || "#ffffff",
      "--btn-danger-bg"  => s.btn_danger_bg_dark.presence  || "#ef4444",
      "--btn-danger-fg"  => s.btn_danger_fg_dark.presence  || "#ffffff"
    }
    # Hover is auto-derived: mix 88% of the base colour with black for a darker shade.
    button_rules = <<~CSS.squish
      .bg-indigo-600{background-color:var(--btn-primary-bg)!important;color:var(--btn-primary-fg)!important;}
      .hover\\:bg-indigo-700:hover{background-color:color-mix(in srgb,var(--btn-primary-bg) 88%,#000)!important;}
      .bg-green-600{background-color:var(--btn-success-bg)!important;color:var(--btn-success-fg)!important;}
      .hover\\:bg-green-700:hover{background-color:color-mix(in srgb,var(--btn-success-bg) 88%,#000)!important;}
      .bg-red-600{background-color:var(--btn-danger-bg)!important;color:var(--btn-danger-fg)!important;}
      .hover\\:bg-red-700:hover{background-color:color-mix(in srgb,var(--btn-danger-bg) 88%,#000)!important;}
    CSS
    css = "html.theme-light,html.theme-system{#{light.map { |k, v| "#{k}:#{v};" }.join}}" \
          "html.theme-dark{#{dark.map { |k, v| "#{k}:#{v};" }.join}}" \
          "body{background-color:var(--page-bg);color:var(--page-fg);}" \
          ".bg-white:not(img){background-color:var(--card-bg)!important;}" \
          ".site-nav{background-color:var(--nav-bg);color:var(--nav-fg);}" \
          ".admin-nav{background-color:var(--admin-nav-bg);color:var(--admin-nav-fg);}" \
          "#{button_rules}"
    tag.style(css.html_safe)
  end

  private

  def configured_brand_primary_color
    return unless site_setting.respond_to?(:has_attribute?) && site_setting.has_attribute?(:brand_primary_color)

    site_setting[:brand_primary_color].presence
  end

  def pwa_manifest_screenshot_entry(attachment, form_factor:, label:)
    return nil unless attachment&.attached?

    width = attachment.blob.metadata["width"]
    height = attachment.blob.metadata["height"]
    return nil unless width.present? && height.present?

    {
      src: rails_blob_path(attachment, only_path: true),
      type: attachment.blob.content_type,
      sizes: "#{width}x#{height}",
      form_factor: form_factor,
      label: label
    }
  end
end
