#!/bin/sh
set -eu

if [ "$#" -ne 2 ]; then
  echo "Usage: $0 <application-short-sha> <dev|prod>" >&2
  exit 2
fi

tag=$1
environment=$2

case "$tag" in
  *[!0-9a-f]*|"")
    echo "Image tag must be a lowercase hexadecimal Git SHA." >&2
    exit 2
    ;;
esac

if [ "${#tag}" -lt 8 ] || [ "${#tag}" -gt 40 ]; then
  echo "Image tag must contain 8 to 40 hexadecimal characters." >&2
  exit 2
fi

case "$environment" in
  dev|prod) ;;
  *)
    echo "Environment must be dev or prod." >&2
    exit 2
    ;;
esac

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
file="$repo_dir/apps/counter/overlays/$environment/kustomization.yaml"
temporary_file=$(mktemp)
trap 'rm -f "$temporary_file"' EXIT HUP INT TERM

sed -E "s/(newTag: )[0-9a-f]{8,40}/\\1$tag/g" "$file" > "$temporary_file"

if cmp -s "$file" "$temporary_file"; then
  echo "$environment already uses image tag $tag."
  exit 0
fi

mv "$temporary_file" "$file"
trap - EXIT HUP INT TERM
echo "Updated $environment web and API images to $tag."
