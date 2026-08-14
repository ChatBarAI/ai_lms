# Derive stable Active Record Encryption keys from the application's secret.
# Rotating secret_key_base requires re-encrypting encrypted database attributes first.
encryption_key_generator = Rails.application.key_generator
Rails.application.config.active_record.encryption.primary_key =
  encryption_key_generator.generate_key("active-record-encryption-primary", 32)
Rails.application.config.active_record.encryption.deterministic_key =
  encryption_key_generator.generate_key("active-record-encryption-deterministic", 32)
Rails.application.config.active_record.encryption.key_derivation_salt =
  encryption_key_generator.generate_key("active-record-encryption-salt", 32)
