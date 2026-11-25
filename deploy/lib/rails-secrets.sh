#!/usr/bin/env bash

# Only call when creating an instance's .env. Never rotate existing secrets:
# Active Record Encryption derives its keys from secret_key_base.
lms_write_rails_secrets() {
  local key_file=${1:-} secret
  if [[ -n $key_file ]]; then
    if [[ ! -s $key_file ]]; then
      echo "Supplied Rails production key is missing or empty." >&2
      return 1
    fi
    secret=$(tr -d '\r\n' < "$key_file")
    [[ $secret =~ ^[a-fA-F0-9]{32}$ ]] || {
      echo "Supplied Rails production key must contain 32 hexadecimal characters." >&2
      return 1
    }
    printf 'RAILS_MASTER_KEY=%s\n' "$secret"
  else
    # Rails treats encrypted credentials as empty without a master key. An
    # independent install needs its own signing/encryption secret, not the
    # key for the public repository's encrypted credentials.
    secret=$(openssl rand -hex 64) || return 1
    printf 'SECRET_KEY_BASE=%s\n' "$secret"
  fi
}
