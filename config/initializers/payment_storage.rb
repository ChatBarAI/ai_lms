# Protected requests are authorised by ActiveStorageAccessControl before proxying.
Rails.application.config.active_storage.resolve_model_to_route = :rails_storage_proxy
