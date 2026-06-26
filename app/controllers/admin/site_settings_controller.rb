class Admin::SiteSettingsController < Admin::BaseController
  before_action :set_site_setting

  SECTION_ATTRIBUTES = {
    "branding" => %i[
      brand_name show_brand_name invert_logo_on_dark logo favicon default_meta_card_image
      brand_primary_color
      pwa_screenshot_mobile pwa_screenshot_desktop
    ],
    "general" => %i[
      subjects_enabled allow_guest_access pass_mark
      self_service_sign_up_enabled
      kinde_google_sign_in_enabled
      kinde_microsoft_sign_in_enabled
      kinde_google_jit_provisioning_enabled
      kinde_microsoft_jit_provisioning_enabled
    ],
    "theme" => [ :theme_mode, *SiteSetting::COLOR_FIELDS.reject { |field| field.start_with?("btn_") }.map(&:to_sym) ],
    "buttons" => SiteSetting::COLOR_FIELDS.select { |field| field.start_with?("btn_") }.map(&:to_sym),
    "hero" => %i[hero_content hero_content_format],
    "certificates" => %i[
      certificate_template certificate_heading certificate_body certificate_signatory_name certificate_signatory_title
    ],
    "integration" => %i[app_url redis_url],
    "terminology" => []
  }.freeze

  SECTION_TITLES = {
    "branding" => "Branding",
    "general" => "General",
    "theme" => "Theme",
    "buttons" => "Buttons",
    "terminology" => "Terminology",
    "hero" => "Home page hero",
    "certificates" => "Certificates",
    "integration" => "Integration"
  }.freeze

  SECTION_ATTACHMENT_PURGE_FLAGS = {
    "branding" => {
      logo: :remove_logo,
      favicon: :remove_favicon,
      default_meta_card_image: :remove_default_meta_card_image,
      pwa_screenshot_mobile: :remove_pwa_screenshot_mobile,
      pwa_screenshot_desktop: :remove_pwa_screenshot_desktop
    },
    "certificates" => {
      certificate_template: :remove_certificate_template
    }
  }.freeze

  def edit
    @active_section = current_section
    @current_base_url = request.base_url
    @redis_info = probe_redis
  end

  def probe_redis
    redis_url = @site_setting.redis_url.presence ||
                 ENV.fetch("REDIS_URL") { "redis://localhost:6379/0" }
    uri = URI.parse(redis_url)
    current_db = uri.path.delete_prefix("/").to_i

    # Connect on DB 0 so INFO keyspace sees all databases regardless of which DB
    # this instance is configured to use.
    base_url = "#{uri.scheme}://#{[ uri.userinfo, uri.host ].compact.join("@")}:#{uri.port}"
    client = Redis.new(url: "#{base_url}/0")
    keyspace = client.info("keyspace")   # { "db0" => "keys=3,...", "db2" => ... }
    client.close

    used_dbs = keyspace.keys.map { |k| k.delete_prefix("db").to_i }.sort
    {
      url: redis_url,
      current_db: current_db,
      used_dbs: used_dbs,
      available_dbs: (0..15).to_a - used_dbs,
      error: nil
    }
  rescue => e
    { url: ENV["REDIS_URL"].presence || "(not set)", current_db: nil, used_dbs: [], available_dbs: [], error: e.message }
  end
  private :probe_redis

  def update
    section = current_section
    purge_requested_attachments(section)

    if @site_setting.update(site_setting_params(section))
      redirect_to edit_admin_site_setting_path(anchor: section), notice: "#{SECTION_TITLES.fetch(section)} settings updated."
    else
      @active_section = section
      @current_base_url = request.base_url
      @redis_info = probe_redis
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def set_site_setting
    @site_setting = SiteSetting.current
  end

  def current_section
    requested = params[:section].to_s
    SECTION_ATTRIBUTES.key?(requested) ? requested : "general"
  end

  def site_setting_params(section)
    if section == "terminology"
      params.require(:site_setting).permit(terminology: I18n.available_locales.index_with { SiteSetting::TERMINOLOGY_KEYS })
    else
      params.require(:site_setting).permit(*SECTION_ATTRIBUTES.fetch(section))
    end
  end

  def purge_requested_attachments(section)
    flags = SECTION_ATTACHMENT_PURGE_FLAGS.fetch(section, {})
    flags.each do |attachment_name, remove_flag|
      next unless ActiveModel::Type::Boolean.new.cast(params.dig(:site_setting, remove_flag))

      purge_attachment(attachment_name)
    end
  end

  def purge_attachment(attachment_name)
    case attachment_name
    when :logo
      @site_setting.logo.purge
    when :favicon
      @site_setting.favicon.purge
    when :default_meta_card_image
      @site_setting.default_meta_card_image.purge
    when :pwa_screenshot_mobile
      @site_setting.pwa_screenshot_mobile.purge
    when :pwa_screenshot_desktop
      @site_setting.pwa_screenshot_desktop.purge
    when :certificate_template
      @site_setting.certificate_template.purge
    end
  end
  private :purge_attachment
end
