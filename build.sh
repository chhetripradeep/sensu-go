#!/usr/bin/env bash
set -o pipefail
set -e

REPO_PATH="github.com/sensu/sensu-go"
DASHBOARD_PATH="dashboard"

eval $(go env)

cmd=${1:-"all"}

# Helpers

cmd_name_map() {
    local cmd=$1

    case "$cmd" in
        backend)
            echo "sensu-backend"
            ;;
        agent)
            echo "sensu-agent"
            ;;
        cli)
            echo "sensuctl"
            ;;
    esac
}

prompt_confirm() {
    read -r -n 1 -p "${1} [y/N] " response
    case "$response" in
        [yY][eE][sS]|[yY])
            true
            ;;
        *)
            false
            ;;
    esac
}

RACE=""
set_race_flag() {
    if [ "$GOARCH" == "amd64" ]; then
        RACE="-race"
    fi
}
case "$GOOS" in
    darwin)
        set_race_flag
        ;;
    freebsd)
        set_race_flag
        ;;
    linux)
        set_race_flag
        ;;
    windows)
        set_race_flag
        ;;
esac

# Dependencies

install_deps () {
    echo "Installing deps..."
    go get github.com/axw/gocov/gocov
    go get gopkg.in/alecthomas/gometalinter.v1
    go get github.com/gordonklaus/ineffassign
    go get github.com/jgautheron/goconst/cmd/goconst
    go get github.com/kisielk/errcheck
    go get github.com/golang/lint/golint
    go get github.com/UnnoTed/fileb0x
    install_golang_dep
}

install_golang_dep() {
    go get github.com/golang/dep/cmd/dep
    echo "Running dep ensure..."
    dep ensure -v -vendor-only
}

# Build Sensu binaries

go_build () {
    local goos=$1
    local goarch=$2
    local cmd=$3
    local cmd_name=$4

    local outfile="target/${goos}-${goarch}/${cmd_name}"

    local version=$(cat version/version.txt)
    local prerelease=$(cat version/prerelease.txt)
    local build_date=$(date +"%Y-%m-%dT%H:%M:%S%z")
    local build_sha=$(git rev-parse HEAD)

    local version_pkg="github.com/sensu/sensu-go/version"
    local ldflags=" -X $version_pkg.Version=${version}"
    local ldflags+=" -X $version_pkg.PreReleaseIdentifier=${prerelease}"
    local ldflags+=" -X $version_pkg.BuildDate=${build_date}"
    local ldflags+=" -X $version_pkg.BuildSHA=${build_sha}"

    CGO_ENABLED=0 GOOS=$goos GOARCH=$goarch go build -ldflags "${ldflags}" -i -o $outfile ${REPO_PATH}/${cmd}/cmd/...

    echo $outfile
}

build_binary () {
    local cmd=$1
    local cmd_name=$(cmd_name_map $cmd)

    if [ ! -d bin/ ]; then
        mkdir -p bin/
    fi

    echo "Building $cmd for ${GOOS}-${GOARCH}"
    out=$(go_build $GOOS $GOARCH $cmd $cmd_name)
    rm -f bin/$(basename $out)
    cp ${out} bin
}

build_binaries () {
    echo "Running build..."

    for cmd in agent backend cli; do
        build_binary $cmd
    done
}

# Build tools

go_build_tool () {
    local goos=$1
    local goarch=$2
    local cmd=$3
    local subdir=$4

    local outfile="target/${goos}-${goarch}/${subdir}/${cmd}"

    GOOS=$goos GOARCH=$goarch go build -i -o $outfile ${REPO_PATH}/${subdir}/${cmd}/...

    echo $outfile
}

build_tool () {
    local cmd=$1
    local subdir=$2

    if [ ! -d bin/${subdir} ]; then
        mkdir -p bin/${subdir}
    fi

    echo "Building $subdir/$cmd for ${GOOS}-${GOARCH}"
    out=$(go_build_tool $GOOS $GOARCH $cmd $subdir)
    rm -f bin/$(basename $out)
    cp ${out} bin/${subdir}
}

build_tools () {
    echo "Running tool & plugin builds..."

    for cmd in cat false sleep true; do
        build_tool $cmd "tools"
    done

    for cmd in slack; do
        build_tool $cmd "handlers"
    done
}

# Testing

e2e_commands () {
    echo "Running e2e tests..."
    go test ${REPO_PATH}/testing/e2e $@
}

integration_test_commands () {
    echo "Running integration tests..."

    go test -timeout=180s -tags=integration $RACE $(go list ./... | egrep -v '(testing|vendor|scripts)')
    if [ $? -ne 0 ]; then
        echo "Integration testing failed..."
        exit 1
    fi

    # If the race detector was enabled, do a second pass without it
    if [ ! -z "$RACE" ]; then
        echo "Running integration tests without race detector..."

        go test -timeout=180s -tags=integration $(go list ./... | egrep -v '(testing|vendor|scripts)')
        if [ $? -ne 0 ]; then
            echo "Integration testing failed..."
            exit 1
        fi
    fi
}

linter_commands () {
    echo "Running linter..."

    gometalinter.v1 --vendor --disable-all --enable=vet --enable=golint --enable=ineffassign --enable=goconst --tests ./...
    if [ $? -ne 0 ]; then
        echo "Linting failed..."
        exit 1
    fi

    errcheck $(go list ./... | grep -v dashboardd | grep -v cli/commands/importer | grep -v agent/assetmanager | grep -v scripts)
    if [ $? -ne 0 ]; then
        echo "Linting failed..."
        exit 1
    fi
}

unit_test_commands () {
    echo "Running unit tests..."

    go test -timeout=60s $RACE $(go list ./... | egrep -v '(testing|vendor|scripts)')
    if [ $? -ne 0 ]; then
        echo "Unit testing failed..."
        exit 1
    fi
}

# Dashboard

build_dashboard() {
    pushd "${DASHBOARD_PATH}"
    yarn install
    yarn precompile
    yarn build
    popd
}

bundle_static_assets() {
    fileb0x ./.b0x.yaml
}

check_for_presence_of_yarn() {
    if hash yarn 2>/dev/null; then
        echo "Yarn is installed, continuing."
    else
        echo "Please install yarn to build dashboard."
        exit 1
    fi
}

install_yarn() {
    npm install --global yarn
}

install_dashboard_deps() {
    go get github.com/UnnoTed/fileb0x
    check_for_presence_of_yarn
    pushd "${DASHBOARD_PATH}"
    yarn install
    yarn precompile
    popd
}

test_dashboard() {
    pushd "${DASHBOARD_PATH}"
    yarn lint
    yarn test --coverage
    popd
}

# Deployment

deploy() {
    echo "Deploying..."

    # Authenticate to Google Cloud and deploy binaries
    openssl aes-256-cbc -K $encrypted_d9a31ecd7e9c_key -iv $encrypted_d9a31ecd7e9c_iv -in gcs-service-account.json.enc -out gcs-service-account.json -d
    gcloud auth activate-service-account --key-file=gcs-service-account.json
    ./build-gcs-release.sh

    # Deploy system packages to PackageCloud
    gem install package_cloud
    make clean
    docker_hub_login
    docker pull sensuapp/sensu-go-build
    docker run -it -v `pwd`:/go/src/github.com/sensu/sensu-go sensuapp/sensu-go-build
    docker run -it -v `pwd`:/go/src/github.com/sensu/sensu-go -e PACKAGECLOUD_TOKEN="$PACKAGECLOUD_TOKEN" sensuapp/sensu-go-build publish_travis

    # Deploy Docker images to the Docker Hub
    docker_commands push versioned
}

# Docker Images

docker_build () {
    local build_sha=$(git rev-parse HEAD)

    # Build Sensu binaries and tools
    build_binaries
    build_tools

    # Build the image using the "master" tag
    docker build --label build.sha=${build_sha} -t sensuapp/sensu-go:master .
}

docker_hub_login() {
    docker login -u="$DOCKER_USERNAME" -p="$DOCKER_PASSWORD"
}

docker_hub_push () {
    # Type of release (master or versioned)
    local release=$1

    docker_hub_login

    if [ "$release" == "master" ]; then
        # push master - tags and pushes latest master docker build only
        docker push sensuapp/sensu-go:master
    elif [ "$release" == "versioned" ]; then
        # push versioned - tags and pushes with version pulled from
        # version/prerelease/iteration files
        local version_alpha=$(echo sensuapp/sensu-go:$(cat version/version.txt)-alpha)
        local version_alpha_iteration=$(echo sensuapp/sensu-go:$(cat version/version.txt)-$(cat version/prerelease.txt).$(cat version/iteration.txt))
        docker tag sensuapp/sensu-go:master sensuapp/sensu-go:latest
        docker push sensuapp/sensu-go:latest
        docker tag sensuapp/sensu-go:master $version_alpha_iteration
        docker push $version_alpha_iteration
        docker tag $version_alpha_iteration $version_alpha
        docker push $version_alpha
    else
        echo "No type of Docker release specified"
    fi
}

deploy_docker () {
    docker_build
    docker_hub_push "${@:2}"
}

if [ "$cmd" == "build" ]; then
    build_binaries
elif [ "$cmd" == "build_agent" ]; then
    build_binary agent
elif [ "$cmd" == "build_backend" ]; then
    build_binary backend
elif [ "$cmd" == "build_cli" ]; then
    build_binary cli
elif [ "$cmd" == "build_dashboard" ]; then
    install_dashboard_deps
    build_dashboard
    bundle_static_assets
elif [ "$cmd" == "build_tools" ]; then
    build_tools
elif [ "$cmd" == "dashboard" ]; then
    install_dashboard_deps
    test_dashboard
elif [ "$cmd" == "dashboard-ci" ]; then
    install_yarn
    install_dashboard_deps
    test_dashboard
    ./codecov.sh -t $CODECOV_TOKEN -cF javascript -s dashboard
elif [ "$cmd" == "deploy" ]; then
    if [[ -z "${TRAVIS}" || "${TRAVIS}" != true ]]; then
        prompt_confirm "You are trying to deploy outside of Travis. Are you sure?" || exit 0
    fi
    deploy
elif [ "$cmd" == "deploy_docker" ]; then
    deploy_docker "${@:2}"
elif [ "$cmd" == "deps" ]; then
    install_deps
elif [ "$cmd" == "e2e" ]; then
    # Accepts specific test name. E.g.: ./build.sh e2e -run TestAgentKeepalives
    build_binaries
    e2e_commands "${@:2}"
elif [ "$cmd" == "lint" ]; then
    linter_commands
elif [ "$cmd" == "none" ]; then
    echo "noop"
elif [ "$cmd" == "quality" ]; then
    linter_commands
    unit_test_commands
elif [ "$cmd" == "unit" ]; then
    unit_test_commands
elif [ "$cmd" == "integration" ]; then
    integration_test_commands
else
    install_deps
    linter_commands
    build_tools
    unit_test_commands
    integration_test_commands
    build_binaries
    e2e_commands
fi
