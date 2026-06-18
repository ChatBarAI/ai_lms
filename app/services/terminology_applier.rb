# Pushes per-deployment terminology overrides from SiteSetting#terminology
# into the I18n backend so admin-editable strings (e.g. renaming "Lesson"
# to "Module") take effect without a restart.
#
# Multi-worker safety: each Puma worker has its own I18n backend. Workers
# call `ensure_fresh!` on each request and re-apply when SiteSetting has
# been updated since their last application.
class TerminologyApplier
  # Maps an override key (admin form field) to a dotted I18n path.
  OVERRIDABLE = {
    "lesson_one"    => %i[activerecord models lesson one],
    "lesson_other"  => %i[activerecord models lesson other],
    "course_one"    => %i[activerecord models course one],
    "course_other"  => %i[activerecord models course other],
    "subject_one"   => %i[activerecord models subject one],
    "subject_other" => %i[activerecord models subject other],
    "quiz_one"      => %i[activerecord models quiz one],
    "quiz_other"    => %i[activerecord models quiz other]
  }.freeze

  class << self
    def call
      setting = SiteSetting.current
      reload_yaml_defaults!
      apply_overrides(setting.respond_to?(:terminology) ? setting.terminology || {} : {})
      @applied_stamp = setting.updated_at
      true
    rescue ActiveRecord::StatementInvalid, ActiveRecord::NoDatabaseError, ActiveRecord::ConnectionNotEstablished
      # Tables may not exist yet during initial setup / db:create.
      false
    end

    # Cheap per-request check; re-applies only when SiteSetting has changed
    # since this worker last applied.
    def ensure_fresh!
      stamp = SiteSetting.current.updated_at
      return if @applied_stamp == stamp
      call
    rescue ActiveRecord::StatementInvalid, ActiveRecord::NoDatabaseError, ActiveRecord::ConnectionNotEstablished
      nil
    end

    private

    # Forces Simple backend to discard merged translations so YAML defaults
    # are re-read on next access; overrides are then layered on top.
    def reload_yaml_defaults!
      I18n.backend.reload!
      I18n.backend.send(:init_translations) if I18n.backend.respond_to?(:init_translations, true)
    end

    def apply_overrides(overrides)
      tree = {}
      OVERRIDABLE.each do |key, path|
        value = overrides[key].presence
        next unless value
        deep_set(tree, path, value.to_s)
      end
      return if tree.empty?
      I18n.available_locales.each do |locale|
        I18n.backend.store_translations(locale, tree)
      end
    end

    def deep_set(hash, path, value)
      *parents, leaf = path
      target = parents.reduce(hash) { |h, k| h[k] ||= {} }
      target[leaf] = value
    end
  end
end
