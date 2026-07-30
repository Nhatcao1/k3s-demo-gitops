#!/bin/sh
set -eu

if [ "$#" -ne 1 ]; then
  echo "Usage: $0 <he-source-sha>" >&2
  exit 2
fi

tag=$1
case "$tag" in
  *[!0-9a-f]*|"")
    echo "HE image tag must be a lowercase hexadecimal Git SHA." >&2
    exit 2
    ;;
esac

if [ "${#tag}" -lt 8 ] || [ "${#tag}" -gt 40 ]; then
  echo "HE image tag must contain 8 to 40 hexadecimal characters." >&2
  exit 2
fi

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
file="$repo_dir/apps/he/overlays/dev/kustomization.yaml"
temporary_file=$(mktemp)
trap 'rm -f "$temporary_file"' EXIT HUP INT TERM

sed -E "s/(newTag: ).*/\\1$tag/" \
  "$file" > "$temporary_file"

if cmp -s "$file" "$temporary_file"; then
  echo "HE development already uses image tag $tag."
  exit 0
fi

mv "$temporary_file" "$file"
trap - EXIT HUP INT TERM
echo "Updated HE development image to $tag."
