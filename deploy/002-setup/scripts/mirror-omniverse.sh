#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: mirror-omniverse.sh --acr-name NAME --app-version VERSION \
  [--ngc-token TOKEN] [--target-repo PATH] [--charts-file FILE] \
  [--work-dir DIR] [--dry-run] \
  [--image-import-mode tag|digest] [--values-dir DIR] [--verbose]

Bootstrap NVIDIA Omniverse Kit App Streaming charts and images into
Azure Container Registry (ACR) using Helm OCI workflows.

Required arguments:
  --acr-name NAME          Azure Container Registry name (no fqdn)
  --app-version VERSION    Default chart version applied when a chart
                           entry omits an explicit override
  --ngc-token TOKEN        NGC API token (defaults to $NGC_API_TOKEN)

Optional arguments:
  --target-repo PATH       Target OCI repository namespace inside ACR
                           (default: helm/omniverse)
  --charts-file FILE       File containing chart list overrides. Each
                           non-empty line may be:
                             repo/chart
                             repo/chart VERSION
                             repo/chart@VERSION
                           Lines beginning with # are ignored.
  --work-dir DIR           Reuse an existing workspace directory
  --dry-run                Skip push and import operations
  --image-import-mode MODE Import images by tag (default) or digest
  --values-dir DIR         Directory with optional Helm values overrides
                           searched per chart (chart.yaml, *.yaml)
  --verbose                Print detailed progress information
  --help                   Show this message

Prerequisites:
  * az CLI >= 2.0.55 with acr module
  * helm >= 3.8 with OCI support enabled
  * skopeo (optional, required for digest imports)
  * az acr login --name <acr> executed before running this script
EOF
}

log() {
  printf '%s\n' "$1" >&2
}

verbose_log() {
  if [[ "$VERBOSE" == "true" ]]; then
    log "$1"
  fi
}

fail() {
  log "ERROR: $1"
  exit 1
}

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    fail "Missing required command: $1"
  fi
}

log_command() {
  local prefix="$1"
  shift
  if [[ -z "$prefix" ]]; then
    return
  fi
  printf '%s' "$prefix" >&2
  while (($#)); do
    printf ' %q' "$1" >&2
    shift
  done
  printf '\n' >&2
}

run_command() {
  local -a cmd=("$@")
  if [[ "$DRY_RUN" == "true" ]]; then
    log_command "[dry-run]" "${cmd[@]}"
    return 0
  fi
  if [[ "$VERBOSE" == "true" ]]; then
    log_command "[exec]" "${cmd[@]}"
  fi
  "${cmd[@]}"
}

login_acr_helm_registry() {
  local registry token
  registry="${ACR_NAME}.azurecr.io"

  if [[ "$DRY_RUN" == "true" ]]; then
    log_command "[dry-run]" helm registry login "$registry"
    return
  fi

  helm registry logout "$registry" >/dev/null 2>&1 || true

  token=$(az acr login --name "$ACR_NAME" --expose-token \
    --output tsv --query accessToken) \
    || fail "Unable to obtain ACR access token"

  helm registry login "$registry" \
    --username "00000000-0000-0000-0000-000000000000" \
    --password "$token" >/dev/null \
    || fail "Helm registry login failed for ${registry}"
}

parse_charts_file() {
  local line trimmed ref version remainder
  while IFS= read -r line || [[ -n "$line" ]]; do
    trimmed="${line%%#*}"
    trimmed="${trimmed%$'\r'}"
    trimmed="${trimmed#"${trimmed%%[![:space:]]*}"}"
    trimmed="${trimmed%"${trimmed##*[![:space:]]}"}"

    if [[ -z "$trimmed" ]]; then
      continue
    fi

    if [[ "$trimmed" == *"@"* ]]; then
      ref="${trimmed%%@*}"
      version="${trimmed#*@}"
    else
      ref="${trimmed%%[[:space:]]*}"
      remainder="${trimmed#"${ref}"}"
      remainder="${remainder#"${remainder%%[![:space:]]*}"}"
      version="${remainder%%[[:space:]]*}"
      if [[ "$version" == "$remainder" ]]; then
        version=""
      fi
    fi

    ref="${ref#"${ref%%[![:space:]]*}"}"
    ref="${ref%"${ref##*[![:space:]]}"}"

    if [[ -z "$ref" ]]; then
      continue
    fi

    CHART_MATRIX+=("${ref}|${version}")
  done <"$CHARTS_FILE"
}

collect_images() {
  if [[ "$USE_YQ_FOR_IMAGES" == "true" ]]; then
    yq eval '.. | select(has("image")) | .image' -
    return
  fi

  grep -E '^[[:space:]]*image:' \
    | sed -E 's/^[[:space:]]*image:[[:space:]]*("*)([^"[:space:]]+).*$/\2/'
}

is_ncr_image() {
  local ref="$1"
  if [[ "$ref" == nvcr.io/* ]]; then
    return 0
  fi
  if [[ "$ref" == *.nvcr.io/* ]]; then
    return 0
  fi
  if [[ "$ref" == *.ngc.nvidia.com/* ]]; then
    return 0
  fi
  return 1
}

resolve_values_flags() {
  local chart_name="$1" values_path
  VALUES_FLAGS=()

  if [[ -z "$VALUES_DIR" || ! -d "$VALUES_DIR" ]]; then
    return
  fi

  values_path="${VALUES_DIR}/${chart_name}.yaml"
  if [[ -f "$values_path" ]]; then
    VALUES_FLAGS+=("--values" "$values_path")
  fi

  values_path="${VALUES_DIR}/${chart_name}.yml"
  if [[ -f "$values_path" ]]; then
    VALUES_FLAGS+=("--values" "$values_path")
  fi

  if [[ -d "${VALUES_DIR}/${chart_name}" ]]; then
    while IFS= read -r values_path; do
      VALUES_FLAGS+=("--values" "$values_path")
    done < <(find "${VALUES_DIR}/${chart_name}" -maxdepth 1 -type f \
      \( -name '*.yaml' -o -name '*.yml' \) -print | sort)
  fi
}

ACR_NAME=""
APP_VERSION=""
NGC_TOKEN="${NGC_API_TOKEN:-}"
TARGET_REPO="helm/omniverse"
CHARTS_FILE=""
WORK_DIR=""
DRY_RUN="false"
IMAGE_IMPORT_MODE="tag"
VALUES_DIR=""
VERBOSE="false"
USE_YQ_FOR_IMAGES="false"

while (($#)); do
  case "$1" in
    --acr-name)
      ACR_NAME="$2"
      shift 2
      ;;
    --app-version)
      APP_VERSION="$2"
      shift 2
      ;;
    --ngc-token)
      NGC_TOKEN="$2"
      shift 2
      ;;
    --target-repo)
      TARGET_REPO="$2"
      shift 2
      ;;
    --charts-file)
      CHARTS_FILE="$2"
      shift 2
      ;;
    --work-dir)
      WORK_DIR="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN="true"
      shift 1
      ;;
    --image-import-mode)
      IMAGE_IMPORT_MODE="$2"
      shift 2
      ;;
    --values-dir)
      VALUES_DIR="$2"
      shift 2
      ;;
    --verbose)
      VERBOSE="true"
      shift 1
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      usage
      exit 1
      ;;
  esac
done

: "${ACR_NAME:?--acr-name is required}"
: "${APP_VERSION:?--app-version is required}"
: "${NGC_TOKEN:?Provide --ngc-token or export NGC_API_TOKEN}"

if [[ "$IMAGE_IMPORT_MODE" != "tag" && "$IMAGE_IMPORT_MODE" != "digest" ]]; then
  fail "--image-import-mode must be tag or digest"
fi

require_command az
require_command helm

if command -v yq >/dev/null 2>&1; then
  if printf 'image: test\n' | yq eval '.. | select(has("image")) | .image' - >/dev/null 2>&1; then
    USE_YQ_FOR_IMAGES="true"
  fi
fi

if [[ "$IMAGE_IMPORT_MODE" == "digest" ]]; then
  if ! command -v skopeo >/dev/null 2>&1; then
    log "WARN: skopeo not found, falling back to tag imports"
    IMAGE_IMPORT_MODE="tag"
  fi
fi

OUT_DIR="${PWD}/out"
mkdir -p "$OUT_DIR"

if [[ -n "$WORK_DIR" ]]; then
  mkdir -p "$WORK_DIR"
  WORK_DIR="$(cd "$WORK_DIR" && pwd)"
else
  WORK_DIR="${OUT_DIR}/mirror-omniverse"
  mkdir -p "$WORK_DIR"
fi

if [[ -n "$VALUES_DIR" ]]; then
  if [[ -d "$VALUES_DIR" ]]; then
    VALUES_DIR="$(cd "$VALUES_DIR" && pwd)"
  else
    fail "Values directory not found: ${VALUES_DIR}"
  fi
fi

TARGET_REPO="${TARGET_REPO#/}"
TARGET_REPO="${TARGET_REPO%/}"
if [[ -z "$TARGET_REPO" ]]; then
  fail "--target-repo cannot be empty"
fi

login_acr_helm_registry

CHARTS_DIR="${WORK_DIR}/charts"
PACKAGES_DIR="${WORK_DIR}/packages"
REPORTS_DIR="${WORK_DIR}/reports"
mkdir -p "$CHARTS_DIR" "$PACKAGES_DIR" "$REPORTS_DIR"

log "Workspace: ${WORK_DIR}"

declare -a CHART_MATRIX=()
if [[ -n "$CHARTS_FILE" ]]; then
  if [[ ! -f "$CHARTS_FILE" ]]; then
    fail "Charts file not found: ${CHARTS_FILE}"
  fi
  parse_charts_file
else
  declare -a DEFAULT_CHARTS=(
    "omniverse/kit-appstreaming-rmcp"
    "omniverse/kit-appstreaming-manager"
    "omniverse/kit-appstreaming-session"
    "omniverse/kit-appstreaming-applications"
  )

  for chart in "${DEFAULT_CHARTS[@]}"; do
    CHART_MATRIX+=("${chart}|")
  done
fi

if [[ ${#CHART_MATRIX[@]} -eq 0 ]]; then
  fail "No charts selected for mirroring"
fi

log "Adding Helm repositories"

# Avoid echoing the NGC token when verbose
if [[ "$VERBOSE" == "true" ]]; then
  log "[exec] helm repo add omniverse https://helm.ngc.nvidia.com/nvidia/omniverse --username \$oauthtoken --password ***** --force-update"
fi
if ! helm repo add omniverse \
  https://helm.ngc.nvidia.com/nvidia/omniverse \
  --username "\$oauthtoken" \
  --password "$NGC_TOKEN" \
  --force-update; then
  fail "Unable to add NVIDIA Omniverse Helm repository"
fi

if [[ "$VERBOSE" == "true" ]]; then
  log_command "[exec]" helm repo add fluxcd-community \
    https://fluxcd-community.github.io/helm-charts \
    --force-update
fi
helm repo add fluxcd-community \
  https://fluxcd-community.github.io/helm-charts \
  --force-update >/dev/null

if [[ "$VERBOSE" == "true" ]]; then
  log_command "[exec]" helm repo add prometheus-community \
    https://prometheus-community.github.io/helm-charts \
    --force-update
fi
helm repo add prometheus-community \
  https://prometheus-community.github.io/helm-charts \
  --force-update >/dev/null

if [[ "$VERBOSE" == "true" ]]; then
  log_command "[exec]" helm repo update
fi
helm repo update >/dev/null

log "Processing charts"

declare -a MIRRORED_CHARTS=()
IMAGES_TEMP_FILE="${REPORTS_DIR}/images.raw"
: >"$IMAGES_TEMP_FILE"

declare -a VALUES_FLAGS=()

for entry in "${CHART_MATRIX[@]}"; do
  chart_ref="${entry%%|*}"
  chart_version="${entry#*|}"
  if [[ -z "$chart_version" || "$chart_version" == "$entry" ]]; then
    chart_version="$APP_VERSION"
  fi

  chart_name="${chart_ref##*/}"
  chart_dir="${CHARTS_DIR}/${chart_name}"

  log "Pulling ${chart_ref}"

  rm -rf "$chart_dir"

  if [[ "$VERBOSE" == "true" ]]; then
    if [[ -n "$chart_version" ]]; then
      log_command "[exec]" helm pull "$chart_ref" --version "$chart_version" \
        --untar --untardir "$CHARTS_DIR"
    else
      log_command "[exec]" helm pull "$chart_ref" --untar --untardir "$CHARTS_DIR"
    fi
  fi

  if [[ -n "$chart_version" ]]; then
    helm pull "$chart_ref" --version "$chart_version" \
      --untar --untardir "$CHARTS_DIR"
  else
    helm pull "$chart_ref" --untar --untardir "$CHARTS_DIR"
  fi

  verbose_log "Updating dependencies for ${chart_dir}"
  if ! helm dependency update "$chart_dir" >/dev/null; then
    verbose_log "dependency update failed, attempting build"
    helm dependency build "$chart_dir" >/dev/null || true
  fi

  pkg_output=$(helm package "$chart_dir" --destination "$PACKAGES_DIR")
  pkg_path="${pkg_output##* }"
  target="oci://${ACR_NAME}.azurecr.io/${TARGET_REPO}"

  run_command helm push "$pkg_path" "$target"

  resolve_values_flags "$chart_name"
  manifest_path="${REPORTS_DIR}/${chart_name}-manifest.yaml"

  helm template "$chart_name" "$chart_dir" "${VALUES_FLAGS[@]}" \
    | tee "$manifest_path" \
    | collect_images >>"$IMAGES_TEMP_FILE"

  MIRRORED_CHARTS+=("$chart_name")
done

sort -u "$IMAGES_TEMP_FILE" | sed '/^$/d' >"${REPORTS_DIR}/images.txt"
log "Image report: ${REPORTS_DIR}/images.txt"
IMAGE_DEST_PREFIX="$TARGET_REPO"

while IFS= read -r image; do
  [[ -z "$image" ]] && continue

  if [[ "$image" != *"/"* ]]; then
    log "Skipping malformed image reference: ${image}"
    continue
  fi

  if ! is_ncr_image "$image"; then
    log "Leaving upstream image in place: ${image}"
    continue
  fi

  source_ref="$image"
  repo_path="${image#*/}"
  dest_image="${IMAGE_DEST_PREFIX}/${repo_path}"

  if [[ "$IMAGE_IMPORT_MODE" == "digest" && "$image" != *"@"* ]]; then
    if digest=$(skopeo inspect "docker://${source_ref}" \
      --format '{{.Digest}}' 2>/dev/null); then
      source_base="${source_ref%%[:@]*}"
      repo_base="${repo_path%%[:@]*}"
      source_ref="${source_base}@${digest}"
      dest_image="${IMAGE_DEST_PREFIX}/${repo_base}@${digest}"
    else
      log "WARN: digest lookup failed for ${image}; using tag"
    fi
  fi

  log "Importing ${source_ref} -> ${dest_image}"
  run_command az acr import --name "$ACR_NAME" --source "$source_ref" \
    --image "$dest_image"
done <"${REPORTS_DIR}/images.txt"

if [[ "$DRY_RUN" == "false" ]]; then
  for chart_name in "${MIRRORED_CHARTS[@]}"; do
    repo_path="${TARGET_REPO}/${chart_name}"
    run_command az acr repository show --name "$ACR_NAME" --repository "$repo_path"
    if [[ "$VERBOSE" == "true" ]]; then
      run_command az acr manifest list-metadata --registry "$ACR_NAME" \
        --name "$repo_path" --query "[0:5]" --output table || true
    fi
  done

  log "Charts mirrored to ${TARGET_REPO}"
fi

log "Mirroring completed"
