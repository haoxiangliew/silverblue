#!/usr/bin/bash

set -euo pipefail

: "${FEDORA_VERSION:?}"
: "${ARCHITECTURE:?}"
: "${GITHUB_OUTPUT:?}"
: "${GITHUB_STEP_SUMMARY:?}"
: "${HOME:?}"

[[ "${ARCHITECTURE}" == "amd64" || "${ARCHITECTURE}" == "arm64" ]]

fedora_tag="quay.io/fedora/fedora-silverblue:${FEDORA_VERSION}"
brew_tag="ghcr.io/ublue-os/brew:latest"
resolver_tag="quay.io/fedora/fedora:${FEDORA_VERSION}"
resolver_cache="${HOME}/.cache/silverblue-dnf"

manifest_digest() {
  local manifest="$1"
  local digest

  digest="sha256:$(printf '%s' "${manifest}" | sha256sum | cut -d ' ' -f 1)"
  [[ "${digest}" =~ ^sha256:[0-9a-f]{64}$ ]]
  printf '%s\n' "${digest}"
}

platform_digest() {
  local manifest="$1"
  local architecture="$2"
  local -a digests

  mapfile -t digests < <(
    jq -er --arg architecture "${architecture}" '
      .manifests[] |
      select(.platform.os == "linux" and .platform.architecture == $architecture) |
      .digest
    ' <<< "${manifest}"
  )
  if ((${#digests[@]} != 1)) || [[ ! "${digests[0]}" =~ ^sha256:[0-9a-f]{64}$ ]]; then
    echo "Expected one linux/${architecture} Fedora manifest digest" >&2
    return 1
  fi
  printf '%s\n' "${digests[0]}"
}

containerfile_packages() {
  local architecture="$1"
  local transaction="$2"
  local group line value
  local pattern='^ARG[[:space:]]+DNF_PACKAGES_([A-Z0-9_]+)="([^"]*)"$'
  local -a packages parsed

  while IFS= read -r line; do
    if [[ "${line}" =~ ${pattern} ]]; then
      group="${BASH_REMATCH[1]}"
      value="${BASH_REMATCH[2]}"

      if [[ "${group}" == "MULTIMEDIA_OVERRIDES" ]]; then
        [[ "${transaction}" == "overrides" ]] || continue
      elif [[ "${transaction}" == "overrides" ]]; then
        continue
      fi

      case "${group}" in
        REMOVE|NVIDIA_KERNEL)
          continue
          ;;
        AMD64)
          [[ "${architecture}" == "amd64" ]] || continue
          ;;
      esac

      read -r -a parsed <<< "${value}"
      packages+=("${parsed[@]}")
    fi
  done < Containerfile

  printf '%s\n' "${packages[@]}" | LC_ALL=C sort -u
}

resolve_transaction() {
  local architecture="$1"
  local -a overrides packages

  mapfile -t overrides < <(containerfile_packages "${architecture}" overrides)
  mapfile -t packages < <(containerfile_packages "${architecture}" install)
  ((${#overrides[@]} > 0))
  ((${#packages[@]} > 0))
  packages+=("${overrides[@]}")
  echo "Resolving ${architecture} package metadata with ${resolver_image}" >&2

  docker run --rm --platform "linux/${architecture}" \
    --env "FEDORA_VERSION=${FEDORA_VERSION}" \
    --mount "type=bind,source=${resolver_cache},target=/var/cache" \
    --entrypoint /bin/bash "${resolver_image}" -ceu '
      dnf config-manager setopt fedora-multimedia.enabled=1 2>/dev/null ||
        dnf config-manager addrepo --from-repofile=https://negativo17.org/repos/fedora-multimedia.repo >&2
      dnf config-manager setopt fedora-multimedia.priority=90 >&2
      dnf -y copr enable scottames/ghostty >&2
      dnf -y copr enable imput/helium >&2
      mkdir -p /tmp/resolve
      mkdir -p /tmp/resolve-root
      cd /tmp/resolve

      resolve() {
        rm -rf debugdata
        set +e
        dnf --installroot=/tmp/resolve-root \
          --use-host-config \
          --releasever="${FEDORA_VERSION}" \
          --quiet --refresh --debugsolver --assumeno \
          "$@" >solver.log 2>&1
        status=$?
        set -e

        if [[ "${status}" -ne 1 || ! -s debugdata/packages/solver.result ]]; then
          cat solver.log >&2
          return 1
        fi
        sed -E "s/@[^[:space:]]+$//" debugdata/packages/solver.result |
          LC_ALL=C sort -u
      }

      resolve install --allowerasing --skip-unavailable "$@" |
        sed "s/^/install=/"
    ' resolve "${packages[@]}"
}

fedora_manifest="$(docker buildx imagetools inspect --raw "${fedora_tag}")"
brew_manifest="$(docker buildx imagetools inspect --raw "${brew_tag}")"
resolver_manifest="$(docker buildx imagetools inspect --raw "${resolver_tag}")"
fedora_digest="$(manifest_digest "${fedora_manifest}")"
brew_digest="$(manifest_digest "${brew_manifest}")"
resolver_image="${resolver_tag}@$(platform_digest "${resolver_manifest}" "${ARCHITECTURE}")"
mkdir -p "${resolver_cache}"
transaction="$(resolve_transaction "${ARCHITECTURE}")"
[[ -n "${transaction}" ]]
package_inventory="$(LC_ALL=C sed -n '/^ARG DNF_PACKAGES_/p' Containerfile | sort)"
fingerprint_input="$(
  printf 'declaration=%s\n' "${package_inventory}"
  printf '%s\n' "${transaction}" | sed "s/^/${ARCHITECTURE}=/"
  )"
transaction_fingerprint="$(printf '%s\n' "${fingerprint_input}" | sha256sum | cut -d ' ' -f 1)"

{
  echo "fedora_digest=${fedora_digest}"
  echo "brew_digest=${brew_digest}"
  echo "transaction_fingerprint=${transaction_fingerprint}"
} >> "${GITHUB_OUTPUT}"

{
  echo "### Resolved ${ARCHITECTURE} inputs"
  echo
  echo "- Fedora: \`${fedora_digest}\`"
  echo "- Homebrew: \`${brew_digest}\`"
  echo "- DNF transaction: \`${transaction_fingerprint}\`"
} >> "${GITHUB_STEP_SUMMARY}"
