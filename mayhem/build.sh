#!/usr/bin/env bash
#
# gluon/mayhem/build.sh (mining layer) — builds rfc822.FuzzParseDec as a sanitized libFuzzer binary
# with go-118-fuzz-build. The harness is not in the upstream tree at this commit, so it lives in
# mayhem/harness/ and is copied into the container's rfc822 package at build time.
set -euo pipefail

# clang rejects SOURCE_DATE_EPOCH='' — must be unset or a valid integer.
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${CC:=clang}" ; : "${CXX:=clang++}" ; : "${LIB_FUZZING_ENGINE:=-fsanitize=fuzzer}"
# OSS-Fuzz Go path is ASAN-only (project.yaml sanitizers: [address]); UBSan is not part of the
# Go libFuzzer link. Keep ASan as the Go-fuzz sanitizer regardless of the base default. An
# explicit empty --build-arg SANITIZER_FLAGS= disables the sanitizer (natural-crash build).
: "${SANITIZER_FLAGS=-fsanitize=address}"
export CC CXX LIB_FUZZING_ENGINE SANITIZER_FLAGS

# Debug-info flags (SPEC §6.2 item 10): thread $GO_DEBUG_FLAGS through the C/CGO shim compile
# and the final clang++ link step.
: "${GO_DEBUG_FLAGS:=-g -gdwarf-3}"
export CGO_CFLAGS="${CGO_CFLAGS:+$CGO_CFLAGS }$GO_DEBUG_FLAGS"
export CGO_CXXFLAGS="${CGO_CXXFLAGS:+$CGO_CXXFLAGS }$GO_DEBUG_FLAGS"

# Air-gapped contract (SPEC §6.5): the PATCH tier re-runs build.sh OFFLINE.
# $(go env GOMODCACHE) reads the pinned ENV under /opt/toolchains (set in the Dockerfile),
# so the file proxy path is correct regardless of $HOME.
export GOFLAGS="${GOFLAGS:--mod=mod}"
export GOPROXY="${GOPROXY:-file://$(go env GOMODCACHE)/cache/download,https://proxy.golang.org,direct}"
export GOTOOLCHAIN="${GOTOOLCHAIN:-local}"

cd "$SRC"
go version

# go-118-fuzz-build harnesses need the AdamKorcz testing shim registered as an import in each
# fuzzed package (mirrors OSS-Fuzz's own build.sh pattern, e.g. gopsutil/go-cmp/go-ole: a small
# `register.go` blank-importing the shim, so `go mod tidy` doesn't prune the module before the
# builder's codegen references it). Written into the CONTAINER's copy of the tree only (never
# committed — our git layer stays confined to mayhem/ + .github/workflows/).
for pkg in rfc822; do
  printf 'package %s\n\nimport _ "github.com/AdamKorcz/go-118-fuzz-build/testing"\n' "$pkg" \
    > "$SRC/$pkg/mayhem_register.go"
done

# Add the module deps WITHOUT a trailing `go mod tidy` after `go get` (tidy would prune the
# shim if nothing else imports it yet). Order matters: tidy first, then `go get` the shim.
go mod tidy 2>&1 | tail -5 || true
go get github.com/AdamKorcz/go-118-fuzz-build/testing@latest 2>&1 | tail -5 || true

mkdir -p "$SRC/mayhem-build"

build_target() {
  local fuzzer="$1" func="$2" pkgdir="$3"
  echo "=== building $fuzzer ($func, go-118-fuzz-build) ==="
  go-118-fuzz-build -o "$SRC/mayhem-build/$fuzzer.a" -func "$func" "$pkgdir"
  # Link: DWARF3 via $GO_DEBUG_FLAGS ensures the C-shim CU (first in the binary) is at DWARF3.
  $CXX $GO_DEBUG_FLAGS $SANITIZER_FLAGS $LIB_FUZZING_ENGINE "$SRC/mayhem-build/$fuzzer.a" -o "/mayhem/$fuzzer"
  echo "built /mayhem/$fuzzer"
}

cp "$SRC/mayhem/harness/parse_dec_fuzz_test.go" "$SRC/rfc822/mayhem_parse_dec_fuzz_test.go"
build_target fuzz_parse_dec FuzzParseDec "$SRC/rfc822"

ls -la /mayhem/fuzz_parse_dec

# the Mayhemfile references the dictionary under /mayhem/mayhem/ (copied with the tree); also place it at /mayhem/
find "$SRC/mayhem" -name "*.dict" -exec cp {} /mayhem/ \; 2>/dev/null || true
