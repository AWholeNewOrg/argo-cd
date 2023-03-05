#! /usr/bin/env bash
#/ Usage: prep-protoc-imports.sh <output-dir>
#/
#/ Prepares a directory containing all the necessary imports for protoc to run.
#/ Any existing content in output-dir will be removed. The path to argo-cd
#/ source code can be set with the PROJECT_ROOT environment variable. Defaults
#/ to this script's grandparent directory.

set -e

if [ "$#" -ne 1 ]; then
  grep '^#/' <"$0" | cut -c4-
  exit 1
fi

PROJECT_ROOT="${PROJECT_ROOT:-"$(cd $(dirname "$0")/../..; pwd)"}"
OUTPUT_DIR="$1"
mkdir -p "$OUTPUT_DIR"
rm -rf "${OUTPUT_DIR:?}"/*

go mod download -C "$PROJECT_ROOT"

link_modcache_dir() {
  local module_name="$1"
  local rel_package="$2"
  local rel_dest="${3:-$module_name}"
  local mod_cache_dir="$(go list -C "$PROJECT_ROOT" -mod readonly -m -f '{{.Dir}}' "$module_name")"
  mkdir -p "$(dirname "$OUTPUT_DIR"/"$rel_dest")"
  ln -s "$mod_cache_dir"/"$rel_package" "$OUTPUT_DIR"/"$rel_dest"
}

mkdir -p "$OUTPUT_DIR"/github.com/argoproj/argo-cd
ln -s "$PROJECT_ROOT" "$OUTPUT_DIR"/github.com/argoproj/argo-cd/v2

link_modcache_dir "k8s.io/api"
link_modcache_dir "k8s.io/apimachinery"
link_modcache_dir "k8s.io/apiextensions-apiserver"
link_modcache_dir "github.com/grpc-ecosystem/grpc-gateway" "third_party/googleapis/google" "google"
link_modcache_dir "github.com/gogo/protobuf" "gogoproto" "gogoproto"
link_modcache_dir "github.com/gogo/protobuf"
