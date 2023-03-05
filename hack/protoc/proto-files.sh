#! /usr/bin/env bash
#/ Usage: proto-files.sh <source-dir>
#/
#/ Prints a list of .proto files that `make protogen` uses for generation.

set -e

if [ "$#" -ne 1 ]; then
  grep '^#/' <"$0" | cut -c4-
  exit 1
fi

SOURCE_DIR="$1"

# all .proto files in server, cmpserver, and reposerver directories
find "$SOURCE_DIR"/{server,cmpserver,reposerver} -name "*.proto" | sort
