#!/bin/bash

set -euxf -o pipefail

usage() {
  echo $"Usage: $0 <elasticsearch|opensearch> <version>"
  exit 1
}

check_arg() {
  if [ ! $# -eq 2 ]; then
    echo "ERROR: need exactly two arguments, <elasticsearch|opensearch> <image>"
    usage
  fi
}

setup_es() {
  local tag=$1
  local image=docker.elastic.co/elasticsearch/elasticsearch
  local params=(
    --rm
    --detach
    --publish 9200:9200
    --env "http.host=0.0.0.0"
    --env "transport.host=127.0.0.1"
    --env "xpack.security.enabled=false"
    --env "xpack.monitoring.enabled=false"
  )
  local cid=$(docker run ${params[@]} ${image}:${tag})
  echo ${cid}
}

setup_opensearch() {
  local image=opensearchproject/opensearch
  local tag=$1
  local params=(
    --rm
    --detach
    --publish 9200:9200
    --env "http.host=0.0.0.0"
    --env "transport.host=127.0.0.1"
    --env "plugins.security.disabled=true"
  )
  local cid=$(docker run ${params[@]} ${image}:${tag})
  echo ${cid}
}

setup_query() {
  local arch=$(go env GOARCH)
  local params=(
    --es.tls.enabled=false
    --es.version=7
    --es.server-urls=http://127.0.0.1:9200
    --query.bearer-token-propagation=true
  )
  SPAN_STORAGE_TYPE=elasticsearch ./cmd/query/query-linux-${arch} ${params[@]}
}

teardown_es() {
  local cid=$1
  docker kill ${cid}
}

teardown_query() {
  local pid=$1
  kill -9 ${pid}
}

build_query() {
  make build-crossdock-ui-placeholder
  GOOS=linux make build-query
}

run_integration_test() {
  local distro=$1
  local version=$2
  local cid
  if [ ${distro} = "elasticsearch" ]; then
    cid=$(setup_es ${version})
  elif [ ${distro} == "opensearch" ]; then
      cid=$(setup_opensearch ${version})
  else
    echo "Unknown distribution $distro. Valid options are opensearch or elasticsearch"
    usage
  fi
  STORAGE=elasticsearch make storage-integration-test
  make index-cleaner-integration-test
  make index-rollover-integration-test
  teardown_es ${cid}
}

run_token_propagation_test() {
  build_query
  make test-compile-es-scripts
  setup_query &
  local pid=$!
  make token-propagation-integration-test
  teardown_query ${pid}
}

main() {
  check_arg "$@"

  echo "Executing integration test for $1 $2"
  run_integration_test "$1" "$2"
  echo "Executing token propagation test"
  run_token_propagation_test
}

main "$@"
