#! /usr/bin/env bash

# This script auto-generates protobuf related files. It is intended to be run manually when either
# API types are added/modified, or server gRPC calls are added. The generated files should then
# be checked into source control.

set -x
set -o errexit
set -o nounset
set -o pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"/..
PROJECT_ROOT="$(pwd)"
PATH="${PROJECT_ROOT}/dist:${PATH}"

[ -d vendor ] || {
    echo "vendor directory not found. Create it with 'go mod vendor' or 'make mod-vendor-local'"
    exit 1
}

# output tool versions
go version
protoc --version
swagger version
jq --version

# Because of inconsistencies with `mktemp -d` on different platforms, use
# `mktemp` to create a temporary file and then replace it with a directory
# of the same name.
TMP_DIR="$(mktemp)"
trap 'rm -rf "$TMP_DIR"' EXIT
rm "$TMP_DIR"
mkdir -p "$TMP_DIR"

GO_TO_PROTOBUF_DIR="$TMP_DIR"/go-to-protobuf
mkdir -p "$GO_TO_PROTOBUF_DIR"/github.com/argoproj/argo-cd
ln -s "$PROJECT_ROOT" "$GO_TO_PROTOBUF_DIR"/github.com/argoproj/argo-cd/v2

# Generate pkg/apis/<group>/<apiversion>/(generated.proto,generated.pb.go)
# NOTE: any dependencies of our types to the k8s.io apimachinery types should be added to the
# --apimachinery-packages= option so that go-to-protobuf can locate the types, but prefixed with a
# '-' so that go-to-protobuf will not generate .proto files for it.
PACKAGES=(
    github.com/argoproj/argo-cd/v2/pkg/apis/application/v1alpha1
)
APIMACHINERY_PKGS=(
    +k8s.io/apimachinery/pkg/util/intstr
    +k8s.io/apimachinery/pkg/api/resource
    +k8s.io/apimachinery/pkg/runtime/schema
    +k8s.io/apimachinery/pkg/runtime
    k8s.io/apimachinery/pkg/apis/meta/v1
    k8s.io/api/core/v1
    k8s.io/apiextensions-apiserver/pkg/apis/apiextensions/v1
)

export GO111MODULE=on

# protoc_include is the include directory containing the .proto files distributed with protoc binary
if [ -d /dist/protoc-include ]; then
    # containerized codegen build
    protoc_include=/dist/protoc-include
else
    # local codegen build
    protoc_include=${PROJECT_ROOT}/dist/protoc-include
fi

(
  cd "$GO_TO_PROTOBUF_DIR"/github.com/argoproj/argo-cd/v2
  go-to-protobuf \
    --go-header-file="${PROJECT_ROOT}"/hack/custom-boilerplate.go.txt \
    --packages="$(IFS=, ; echo "${PACKAGES[*]}")" \
    --apimachinery-packages="$(IFS=, ; echo "${APIMACHINERY_PKGS[*]}")" \
    --proto-import="$PROJECT_ROOT"/vendor \
    --proto-import="${protoc_include}" \
    --output-base="$GO_TO_PROTOBUF_DIR"
)
rm -rf "$GO_TO_PROTOBUF_DIR"

# Either protoc-gen-go, protoc-gen-gofast, or protoc-gen-gogofast can be used to build
# server/*/<service>.pb.go from .proto files. golang/protobuf and gogo/protobuf can be used
# interchangeably. The difference in the options are:
# 1. protoc-gen-go - official golang/protobuf
#GOPROTOBINARY=go
# 2. protoc-gen-gofast - fork of golang golang/protobuf. Faster code generation
#GOPROTOBINARY=gofast
# 3. protoc-gen-gogofast - faster code generation and gogo extensions and flexibility in controlling
# the generated go code (e.g. customizing field names, nullable fields)
GOPROTOBINARY=gogofast

# Generate server/<service>/(<service>.pb.go|<service>.pb.gw.go)
PROTOC_DIR="$TMP_DIR"/protoc-imports
./hack/protoc/prep-protoc-imports.sh "$PROTOC_DIR"
PROTO_FILES="$(./hack/protoc/proto-files.sh "$PROJECT_ROOT")"

for i in ${PROTO_FILES}; do
    protoc \
        -I"${PROJECT_ROOT}" \
        -I"${protoc_include}" \
        -I"$PROTOC_DIR" \
        --${GOPROTOBINARY}_out=plugins=grpc:"$PROTOC_DIR" \
        --grpc-gateway_out=logtostderr=true:"$PROTOC_DIR" \
        --swagger_out=logtostderr=true:. \
        "$i"
done
rm -rf "$PROTOC_DIR"

# collect_swagger gathers swagger files into a subdirectory
collect_swagger() {
    SWAGGER_ROOT="$1"
    SWAGGER_OUT="${PROJECT_ROOT}/assets/swagger.json"
    PRIMARY_SWAGGER=$(mktemp)
    COMBINED_SWAGGER=$(mktemp)

    cat <<EOF > "${PRIMARY_SWAGGER}"
{
  "swagger": "2.0",
  "info": {
    "title": "Consolidate Services",
    "description": "Description of all APIs",
    "version": "version not set"
  },
  "paths": {}
}
EOF

    rm -f "${SWAGGER_OUT}"

    find "${SWAGGER_ROOT}" -name '*.swagger.json' -exec swagger mixin --ignore-conflicts "${PRIMARY_SWAGGER}" '{}' \+ > "${COMBINED_SWAGGER}"
    jq -r 'del(.definitions[].properties[]? | select(."$ref"!=null and .description!=null).description) | del(.definitions[].properties[]? | select(."$ref"!=null and .title!=null).title)' "${COMBINED_SWAGGER}" > "${SWAGGER_OUT}"

    /bin/rm "${PRIMARY_SWAGGER}" "${COMBINED_SWAGGER}"
}

# clean up generated swagger files (should come after collect_swagger)
clean_swagger() {
    SWAGGER_ROOT="$1"
    find "${SWAGGER_ROOT}" -name '*.swagger.json' -delete
}

collect_swagger server
clean_swagger server
clean_swagger reposerver
clean_swagger controller
clean_swagger cmpserver
