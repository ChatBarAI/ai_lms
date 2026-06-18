Rails.application.config.after_initialize do
  if ActiveRecord::Base.connection.data_source_exists?("site_settings") &&
     SiteSetting.column_names.include?("terminology")
    TerminologyApplier.call
  end
rescue ActiveRecord::NoDatabaseError, ActiveRecord::ConnectionNotEstablished
  # First-time setup before db:create — skip.
end
