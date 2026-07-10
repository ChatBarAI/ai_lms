class BrandedDeviseMailer < Devise::Mailer
  layout "branded_mailer"

  def reset_password_instructions(record, token, opts = {})
    prepare_branding(record)
    super
  end

  private

  def prepare_branding(record)
    @site_setting = SiteSetting.current
    @brand_name = @site_setting.brand_name.presence || "ChatBar AI Learn"
    @recipient_name = record.name.presence || record.email
    @page_background = @site_setting.page_bg_light.presence || "#f9fafb"
    @page_foreground = @site_setting.page_fg_light.presence || "#111827"
    @card_background = @site_setting.card_bg_light.presence || "#ffffff"
    @button_background = @site_setting.brand_primary_color.presence ||
                         @site_setting.btn_primary_bg_light.presence ||
                         "#4f46e5"
    @button_foreground = @site_setting.btn_primary_fg_light.presence || "#ffffff"
    embed_logo
  end

  def embed_logo
    filename, content_type, content = logo_email_asset
    attachments.inline[filename] = { mime_type: content_type, content: content }
    @logo_cid = attachments[filename].url
  end

  def logo_email_asset
    if @site_setting.logo.attached?
      blob = @site_setting.logo.blob
      extension = File.extname(blob.filename.to_s)
      return [ "brand-logo#{extension}", blob.content_type, blob.download ]
    end

    path = Rails.root.join("app/assets/images/default-logo.png")
    [ "brand-logo.png", "image/png", File.binread(path) ]
  end
end
