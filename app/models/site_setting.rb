class SiteSetting < ApplicationRecord
  has_one_attached :logo
  has_one_attached :favicon
  has_one_attached :default_meta_card_image
  has_one_attached :pwa_screenshot_mobile
  has_one_attached :pwa_screenshot_desktop
  has_one_attached :certificate_template

  validates :logo, content_type: %w[image/png image/jpeg image/svg+xml image/webp],
                   size: { less_than: 2.megabytes }
  validates :favicon, content_type: %w[image/png image/svg+xml image/webp],
                      size: { less_than: 1.megabyte }
  validates :default_meta_card_image, content_type: %w[image/png image/jpeg image/webp],
                                      size: { less_than: 5.megabytes }
  validates :pwa_screenshot_mobile, content_type: %w[image/png image/jpeg image/webp],
                                    size: { less_than: 8.megabytes }
  validates :pwa_screenshot_desktop, content_type: %w[image/png image/jpeg image/webp],
                                     size: { less_than: 8.megabytes }
  validates :certificate_template, content_type: %w[image/png image/jpeg],
                                   size: { less_than: 10.megabytes }
  validates :pass_mark, numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }
  validates :app_url, format: { with: /\Ahttps?:\/\/.+\z/, message: "must start with http:// or https://" }, allow_blank: true
  validates :redis_url, format: { with: /\Aredis(?:s)?:\/\/.+\z/, message: "must start with redis:// or rediss://" }, allow_blank: true

  HERO_CONTENT_FORMATS = %w[markdown html].freeze

  validates :hero_content_format, inclusion: { in: HERO_CONTENT_FORMATS }

  THEME_MODES = %w[system light dark].freeze
  COLOR_FIELDS = %w[
    page_bg_light page_fg_light nav_bg_light nav_fg_light admin_nav_bg_light admin_nav_fg_light
    card_bg_light card_bg_dark
    page_bg_dark page_fg_dark nav_bg_dark nav_fg_dark admin_nav_bg_dark admin_nav_fg_dark btn_primary_bg_light btn_primary_fg_light btn_primary_bg_dark btn_primary_fg_dark
    btn_success_bg_light btn_success_fg_light btn_success_bg_dark btn_success_fg_dark
    btn_danger_bg_light btn_danger_fg_light btn_danger_bg_dark btn_danger_fg_dark  ].freeze

  validates :theme_mode, inclusion: { in: THEME_MODES }
  validates(*COLOR_FIELDS, format: { with: /\A#[0-9a-fA-F]{6}\z/, message: "must be a hex colour like #1f2937" }, allow_blank: true)
  validates :brand_primary_color,
            format: { with: /\A#[0-9a-fA-F]{6}\z/, message: "must be a hex colour like #1f2937" },
            allow_blank: true,
            if: -> { has_attribute?(:brand_primary_color) }

  TERMINOLOGY_KEYS = TerminologyApplier::OVERRIDABLE.keys.freeze
  TERMINOLOGY_LOCALES = -> { I18n.available_locales.map(&:to_s) }

  validate :terminology_keys_whitelisted
  before_validation :normalise_terminology

  after_commit :reapply_terminology

  def self.current
    first_or_create!(brand_name: "ChatBar AI Learn", pass_mark: 70)
  end

  def kinde_jit_provisioning_enabled_for?(provider)
    case provider.to_s
    when "google"
      kinde_google_jit_provisioning_enabled?
    when "microsoft"
      kinde_microsoft_jit_provisioning_enabled?
    else
      false
    end
  end

  def kinde_provider_sign_in_enabled?(provider)
    case provider.to_s
    when "google"
      kinde_google_sign_in_enabled?
    when "microsoft"
      kinde_microsoft_sign_in_enabled?
    else
      true
    end
  end

  def terminology_for(locale)
    normalised_terminology.fetch(locale.to_s, {})
  end

  private

  def normalise_terminology
    self.terminology = normalised_terminology
  end

  def terminology_keys_whitelisted
    return if terminology.blank?

    raw = (terminology || {}).to_h.deep_stringify_keys
    if flat_terminology?(raw)
      unknown = raw.keys - TERMINOLOGY_KEYS
      errors.add(:terminology, "contains unknown keys: #{unknown.join(', ')}") if unknown.any?
      return
    end

    unknown_locales = raw.keys - TERMINOLOGY_LOCALES.call
    errors.add(:terminology, "contains unknown locales: #{unknown_locales.join(', ')}") if unknown_locales.any?

    raw.each do |locale, locale_terms|
      next unless TERMINOLOGY_LOCALES.call.include?(locale)

      unknown = (locale_terms || {}).to_h.keys.map(&:to_s) - TERMINOLOGY_KEYS
      errors.add(:terminology, "contains unknown keys for #{locale}: #{unknown.join(', ')}") if unknown.any?
    end
  end

  def reapply_terminology
    TerminologyApplier.call
  end

  def normalised_terminology
    raw = (terminology || {}).to_h.deep_stringify_keys
    raw = { I18n.default_locale.to_s => raw } if flat_terminology?(raw)

    raw.slice(*TERMINOLOGY_LOCALES.call).each_with_object({}) do |(locale, locale_terms), result|
      cleaned = (locale_terms || {}).to_h.deep_stringify_keys
        .slice(*TERMINOLOGY_KEYS)
        .transform_values { |v| v.to_s.strip }
        .reject { |_, v| v.blank? }
      result[locale] = cleaned if cleaned.any?
    end
  end

  def flat_terminology?(hash)
    (hash.keys & TERMINOLOGY_KEYS).any?
  end
end
