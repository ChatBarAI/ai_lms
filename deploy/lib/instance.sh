# shellcheck shell=bash
# Shared naming rules for running several LMS instances on one Docker host.
# Source this file; it only defines functions and constants.
#
#   Instance   Deploy root                   Compose project   Volumes
#   default    /opt/ai_lms                   ai_lms            ai_lms_postgres, ...
#   acme       /opt/ai_lms/instances/acme    ai_lms_acme       ai_lms_acme_postgres, ...
#
# The default instance keeps the names used before multi-instance support, so
# existing single-instance servers keep their containers, volumes and paths.

LMS_BASE_ROOT=/opt/ai_lms
LMS_DEFAULT_INSTANCE=default
LMS_EDGE_PROJECT=ai_lms_edge
LMS_EDGE_NETWORK=ai_lms_edge
LMS_LEGACY_MAIL_NETWORK=172.30.25.0/24

# Lowercase letters, digits and inner hyphens; at most 30 characters. No
# underscores, so derived volume and project names cannot collide. "edge" is
# reserved because ai_lms_edge is the shared proxy's project name.
lms_valid_instance() {
  [[ $1 =~ ^[a-z0-9]([a-z0-9-]{0,28}[a-z0-9])?$ && $1 != edge ]]
}

lms_require_instance() {
  lms_valid_instance "$1" || {
    echo "Invalid instance name '$1': use 1-30 lowercase letters, digits or inner hyphens (not 'edge')." >&2
    return 2
  }
}

lms_instance_project() {
  if [[ $1 == "$LMS_DEFAULT_INSTANCE" ]]; then
    printf 'ai_lms\n'
  else
    printf 'ai_lms_%s\n' "$1"
  fi
}

lms_instance_root() {
  if [[ $1 == "$LMS_DEFAULT_INSTANCE" ]]; then
    printf '%s\n' "$LMS_BASE_ROOT"
  else
    printf '%s/instances/%s\n' "$LMS_BASE_ROOT" "$1"
  fi
}

# Network alias the edge proxy uses to reach this instance's web container.
lms_edge_upstream() {
  printf 'lms-%s-web\n' "$1"
}

# Prints the last value of KEY in an env file, or nothing.
lms_env_value() {
  [[ -f $1 ]] || return 0
  sed -n "s/^$2=//p" "$1" | tail -n 1
}

# Adds or replaces KEY=VALUE in an env file. VALUE must not contain '|'.
lms_env_set() {
  local file=$1 key=$2 value=$3
  if grep -q "^$key=" "$file"; then
    sed -i "s|^$key=.*|$key=$value|" "$file"
  else
    printf '%s=%s\n' "$key" "$value" >> "$file"
  fi
}

# Instance recorded in a deployment's env file. Env files written before
# multi-instance support have no INSTANCE and belong to the default instance.
lms_env_instance() {
  local instance
  instance=$(lms_env_value "$1" INSTANCE)
  printf '%s\n' "${instance:-$LMS_DEFAULT_INSTANCE}"
}

# Default DEPLOY_ROOT for a script running from APP_ROOT: the owning deployment
# when APP_ROOT is a release directory (DEPLOY_ROOT/releases/NAME), otherwise
# the default instance's root.
lms_default_deploy_root() {
  local app_root=$1 parent
  parent=$(dirname "$app_root")
  if [[ $(basename "$parent") == releases && -f "$(dirname "$parent")/shared/.env" ]]; then
    dirname "$parent"
  else
    printf '%s\n' "$LMS_BASE_ROOT"
  fi
}

# Sets the global `compose` array for an existing Docker deployment and exports
# the variables compose.yaml interpolates. Includes the mail overlay when the
# deployment uses the local relay.
lms_instance_compose() {
  local app_root=$1 deploy_root=$2 env_file=$3 instance
  instance=$(lms_env_instance "$env_file")
  lms_require_instance "$instance" || return
  export DEPLOY_ROOT="$deploy_root"
  export APP_IMAGE="ai_lms:$(basename "$app_root")"
  COMPOSE_PROJECT_NAME=$(lms_instance_project "$instance")
  EDGE_UPSTREAM=$(lms_edge_upstream "$instance")
  export COMPOSE_PROJECT_NAME EDGE_UPSTREAM
  compose=(docker compose -p "$COMPOSE_PROJECT_NAME" --env-file "$env_file" -f "$app_root/compose.yaml")
  if [[ -f "$app_root/compose.mail.yaml" ]] && grep -qx 'COMPOSE_PROFILES=local-mail' "$env_file"; then
    compose+=(-f "$app_root/compose.mail.yaml" --profile local-mail)
  fi
}

# Prints "first last" as integers for an IPv4 CIDR.
lms_cidr_range() {
  local ip=${1%/*} prefix=${1#*/} a b c d
  IFS=. read -r a b c d <<< "$ip"
  local start=$(( (a << 24) | (b << 16) | (c << 8) | d ))
  local size=$(( 1 << (32 - prefix) ))
  start=$(( start & ~(size - 1) & 0xFFFFFFFF ))
  printf '%s %s\n' "$start" "$(( start + size - 1 ))"
}

# Picks a free 172.30.N.0/24 for an instance's private mail network. Avoids
# every existing Docker network, every subnet another instance has claimed in
# its env file, and the default instance's legacy subnet.
lms_allocate_mail_network() {
  local -a taken=() used_ranges=()
  local subnet n candidate first last other_first other_last overlap
  mapfile -t taken < <(
    docker network ls -q | xargs -r docker network inspect \
      --format '{{range .IPAM.Config}}{{println .Subnet}}{{end}}' 2>/dev/null
    cat "$LMS_BASE_ROOT/shared/.env" "$LMS_BASE_ROOT"/instances/*/shared/.env 2>/dev/null |
      sed -n 's/^MAIL_NETWORK=//p'
    printf '%s\n' "$LMS_LEGACY_MAIL_NETWORK"
  )
  for subnet in "${taken[@]}"; do
    [[ $subnet =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}/[0-9]{1,2}$ ]] || continue
    used_ranges+=("$(lms_cidr_range "$subnet")")
  done
  for n in $(seq 26 254); do
    candidate="172.30.$n.0/24"
    read -r first last <<< "$(lms_cidr_range "$candidate")"
    overlap=false
    for subnet in "${used_ranges[@]}"; do
      read -r other_first other_last <<< "$subnet"
      if (( first <= other_last && other_first <= last )); then overlap=true; break; fi
    done
    $overlap || { printf '%s\n' "$candidate"; return 0; }
  done
  echo "No free 172.30.N.0/24 subnet is available for the mail network." >&2
  return 1
}
