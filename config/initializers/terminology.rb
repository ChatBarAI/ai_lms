# Every translation gets the terminology placeholders (%{lesson}, %{courses_l}, ...)
# filled in automatically, so `t("key")` and `I18n.t("key")` never render a raw
# "%{courses}". Explicit options still win. Defined here, not in app/ or lib/,
# because it is prepended into a framework class and must not be reloaded.
module TerminologyInterpolation
  TERMS = {
    lesson: [ "lesson", "Lesson", "Lessons" ],
    course: [ "course", "Course", "Courses" ],
    subject: [ "subject", "Subject", "Subjects" ],
    quiz: [ "quiz", "Quiz", "Quizzes" ]
  }.freeze

  class << self
    def values(locale)
      cache[locale.to_sym] ||= compute(locale)
    end

    def clear!
      @cache = nil
    end

    private

    def cache
      @cache ||= Concurrent::Map.new
    end

    # Reads activerecord.models.* (where TerminologyApplier stores admin overrides)
    # with injection switched off, since the lookups go back through this backend.
    def compute(locale)
      Thread.current[:terminology_interpolation_off] = true
      TERMS.each_with_object({}) do |(name, (model_key, one_default, other_default)), terms|
        one = I18n.t("activerecord.models.#{model_key}.one", locale: locale, default: one_default)
        other = I18n.t("activerecord.models.#{model_key}.other", locale: locale, default: other_default)
        plural = name == :quiz ? :quizzes : :"#{name}s"
        terms[name] = one
        terms[plural] = other
        terms[:"#{name}_l"] = one.downcase
        terms[:"#{plural}_l"] = other.downcase
      end.freeze
    ensure
      Thread.current[:terminology_interpolation_off] = nil
    end
  end

  TERM_PLACEHOLDER = /(?<!%)%\{(\w+)\}/

  def translate(locale, key, options = I18n::EMPTY_HASH)
    return super if Thread.current[:terminology_interpolation_off]

    terms = TerminologyInterpolation.values(locale)
    return super(locale, key, terms.merge(options)) if (options.keys - I18n::RESERVED_KEYS).any?

    # With no values of its own the caller may want other placeholders kept raw
    # (e.g. a template handed to a Stimulus controller), so fill in only the terms.
    entry = super
    entry.is_a?(String) ? entry.gsub(TERM_PLACEHOLDER) { terms.fetch($1.to_sym, $&) } : entry
  end

  def store_translations(...)
    TerminologyInterpolation.clear!
    super
  end

  def reload!
    TerminologyInterpolation.clear!
    super
  end
end

I18n::Backend::Simple.prepend(TerminologyInterpolation)

Rails.application.config.after_initialize do
  if ActiveRecord::Base.connection.data_source_exists?("site_settings") &&
     SiteSetting.column_names.include?("terminology")
    TerminologyApplier.call
  end
rescue ActiveRecord::NoDatabaseError, ActiveRecord::ConnectionNotEstablished
  # First-time setup before db:create — skip.
end
