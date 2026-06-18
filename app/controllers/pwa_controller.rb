class PwaController < ApplicationController
  skip_forgery_protection only: :service_worker

  def manifest
    response.set_header("Cache-Control", "public, max-age=300")
    render "pwa/manifest", formats: [ :json ], content_type: "application/manifest+json"
  end

  def service_worker
    response.set_header("Cache-Control", "no-cache, no-store, must-revalidate")
    render "pwa/service-worker", formats: [ :js ], layout: false, content_type: "application/javascript"
  end

  def icon
    response.set_header("X-PWA-Icon-Kind", params[:kind].to_s)

    source_image = icon_source_image(params[:kind])
    unless source_image
      response.set_header("X-PWA-Icon-Source", "none")
      redirect_to icon_fallback_path(params[:kind]), allow_other_host: false
      return
    end

    response.set_header("X-PWA-Icon-Source", icon_source_label(params[:kind]))

    expires_in 5.minutes, public: true

    if params[:kind].to_s == "apple-touch"
      render_apple_touch_icon(source_image, 180)
      return
    end

    if params[:kind].to_s == "maskable-512"
      render_maskable_icon(source_image, 512)
      return
    end

    render_standard_icon(source_image, icon_size_for(params[:kind]))
  end

  private

  def icon_source_attachment(kind)
    setting = SiteSetting.current
    candidates = [ setting.favicon, setting.logo ]

    candidates.find(&:attached?)
  end

  def icon_size_for(kind)
    case kind.to_s
    when "192" then 192
    when "apple-touch" then 180
    else 512
    end
  end

  def icon_fallback_path(kind)
    case kind.to_s
    when "apple-touch" then "/favicon.png"
    else "/favicon.png"
    end
  end

  def icon_source_image(kind)
    require "mini_magick"

    source = icon_source_attachment(kind)
    return MiniMagick::Image.read(source.download) if source&.attached?

    fallback_path = Rails.root.join("app/assets/images/chatbar-icon.png")
    return MiniMagick::Image.open(fallback_path.to_s) if File.exist?(fallback_path)

    nil
  end

  def icon_source_label(kind)
    source = icon_source_attachment(kind)
    return "favicon" if source == SiteSetting.current.favicon
    return "logo" if source == SiteSetting.current.logo

    "fallback"
  end

  def render_standard_icon(source_image, size)
    require "mini_magick"

    icon = source_image.clone
    icon.auto_orient
    icon.format("png")

    icon.combine_options do |cmd|
      cmd.resize("#{size}x#{size}")
      cmd.gravity("center")
      cmd.background("none")
      cmd.extent("#{size}x#{size}")
    end

    send_data icon.to_blob, type: "image/png", disposition: "inline"
  rescue StandardError => e
    Rails.logger.warn("[PWA] standard icon generation failed: kind=#{size} error=#{e.class}: #{e.message}")
    response.set_header("X-PWA-Icon-Error", e.class.name)
    redirect_to icon_fallback_path("192"), allow_other_host: false
  end

  def render_maskable_icon(source_image, size)
    require "mini_magick"

    icon = source_image.clone
    icon.auto_orient
    icon.format("png")

    # Keep icon artwork inside Android's recommended safe zone.
    safe_zone = (size * 0.78).round

    icon.combine_options do |cmd|
      cmd.resize("#{safe_zone}x#{safe_zone}")
      cmd.gravity("center")
      cmd.background("none")
      cmd.extent("#{safe_zone}x#{safe_zone}")
    end

    icon.combine_options do |cmd|
      cmd.gravity("center")
      cmd.background(maskable_background_color)
      cmd.extent("#{size}x#{size}")
    end

    send_data icon.to_blob, type: "image/png", disposition: "inline"
  rescue StandardError => e
    Rails.logger.warn("[PWA] maskable icon generation failed: error=#{e.class}: #{e.message}")
    response.set_header("X-PWA-Icon-Error", e.class.name)
    redirect_to icon_fallback_path("192"), allow_other_host: false
  end

  def render_apple_touch_icon(source_image, size)
    require "mini_magick"

    icon = source_image.clone
    icon.auto_orient
    icon.format("png")

    # iOS home screen icons should be opaque; transparent artwork can appear with dark fill.
    safe_zone = (size * 0.82).round

    icon.combine_options do |cmd|
      cmd.resize("#{safe_zone}x#{safe_zone}")
      cmd.gravity("center")
      cmd.background("none")
      cmd.extent("#{safe_zone}x#{safe_zone}")
    end

    icon.combine_options do |cmd|
      cmd.gravity("center")
      cmd.background(apple_touch_background_color)
      cmd.extent("#{size}x#{size}")
    end

    send_data icon.to_blob, type: "image/png", disposition: "inline"
  rescue StandardError => e
    Rails.logger.warn("[PWA] apple-touch icon generation failed: error=#{e.class}: #{e.message}")
    response.set_header("X-PWA-Icon-Error", e.class.name)
    redirect_to icon_fallback_path("apple-touch"), allow_other_host: false
  end

  def maskable_background_color
    setting = SiteSetting.current
    if setting.theme_mode == "dark"
      setting.page_bg_dark.presence || "#111827"
    else
      setting.page_bg_light.presence || "#f9fafb"
    end
  end

  def apple_touch_background_color
    setting = SiteSetting.current
    return "#ffffff" unless icon_source_attachment("apple-touch")&.attached?

    color = if setting.respond_to?(:has_attribute?) && setting.has_attribute?(:brand_primary_color)
      setting[:brand_primary_color].presence
    end
    color || "#ffffff"
  end
end
