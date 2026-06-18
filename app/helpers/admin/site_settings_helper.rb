module Admin::SiteSettingsHelper
  SECTION_NAV_ITEMS = [
    [ "general", "General", "Access and pass mark" ],
    [ "branding", "Branding", "Logo, favicon, brand name" ],
    [ "theme", "Theme", "Mode and base palette" ],
    [ "buttons", "Buttons", "Primary, success, danger" ],
    [ "terminology", "Terminology", "Rename lesson/course/subject" ],
    [ "hero", "Home hero", "Homepage banner content" ],
    [ "certificates", "Certificates", "Default template and signer" ],
    [ "integration", "Integration", "App URL, Redis, and background jobs" ]
  ].freeze

  def site_settings_section_nav_items
    SECTION_NAV_ITEMS
  end

  def site_settings_default_sets
    column_defaults = SiteSetting.column_defaults
    theme_fields = SiteSetting::COLOR_FIELDS.reject { |field| field.start_with?("btn_") }
    button_fields = SiteSetting::COLOR_FIELDS.select { |field| field.start_with?("btn_") }

    {
      "palette" => {
        "theme_mode" => column_defaults["theme_mode"] || "system"
      }.merge(column_defaults.slice(*theme_fields)),
      "buttons" => column_defaults.slice(*button_fields)
    }
  end

  def show_section_errors?(section)
    @site_setting.errors.any? && @active_section.to_s == section.to_s
  end
end
