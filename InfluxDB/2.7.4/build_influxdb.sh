#!/usr/bin/env bash
# © Copyright IBM Corporation 2023.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/InfluxDB/2.7.4/build_influxdb.sh
# Execute build script: bash build_influxdb.sh    (provide -h for help)

set -e -o pipefail

CURDIR="$(pwd)"
PACKAGE_NAME="InfluxDB"
PACKAGE_VERSION="2.7.4"
GO_VERSION="1.21.4"
PROTOBUF_VERSION="3.20.3"
export GOPATH=$CURDIR
FORCE="false"
TEST="false"
OVERRIDE="false"
LOG_FILE="$CURDIR/logs/${PACKAGE_NAME}-${PACKAGE_VERSION}-$(date +"%F-%T").log"

trap cleanup 0 1 2 ERR

#Check if directory exsists
if [ ! -d "$CURDIR/logs" ]; then
	mkdir -p "$CURDIR/logs"
fi

source "/etc/os-release"

function checkPrequisites() {
	printf -- "Checking Prequisites\n"

	if command -v "sudo" >/dev/null; then
		printf -- 'Sudo : Yes\n' >>"$LOG_FILE"
	else
		printf -- 'Sudo : No \n' >>"$LOG_FILE"
		printf -- 'You can install sudo from repository using apt, yum or zypper based on your distro. \n'
		exit 1
	fi
	if [[ "$FORCE" == "true" ]]; then
		printf -- 'Force attribute provided hence continuing with install without confirmation message\n' |& tee -a "$LOG_FILE"
	else
		# Ask user for prerequisite installation
		printf -- "\nAs part of the installation , dependencies would be installed/upgraded.\n"
		while true; do
			read -r -p "Do you want to continue (y/n) ? :  " yn
			case $yn in
			[Yy]*)
				printf -- 'User responded with Yes. \n' >>"$LOG_FILE"
				break
				;;
			[Nn]*) exit ;;
			*) echo "Please provide confirmation to proceed." ;;
			esac
		done
	fi
}

function cleanup() {
	if [[ ${DISTRO} == "sles-12.5" ]]; then
		sudo rm -rf ${CURDIR}/llvm-project
		sudo rm -rf ${CURDIR}/go"${GO_VERSION}".linux-s390x.tar.gz
		sudo rm -rf ${CURDIR}/cmake-3.27.8 ${CURDIR}/cmake-3.27.8.tar.gz 
	fi
	printf -- 'Cleaned up the artifacts\n' >>"$LOG_FILE"
}

function configureAndInstall() {
	printf -- 'Configuration and Installation started \n'

    # Install cmake and clang for SLES 12 sp5
    if [[ ${DISTRO} == "sles-12.5" ]]; then
	    # install CMake
	    printf -- 'Installing cmake...\n'
	    cd $CURDIR
	    wget https://github.com/Kitware/CMake/releases/download/v3.27.8/cmake-3.27.8.tar.gz
	    tar -xzf cmake-3.27.8.tar.gz
	    cd cmake-3.27.8
	    ./bootstrap
	    make
	    sudo make install
	    hash -r

	    # install Clang
	    printf -- 'Installing clang...\n'
	    cd $CURDIR
	    git clone https://github.com/llvm/llvm-project.git
	    cd llvm-project
	    git checkout llvmorg-11.1.0
	    mkdir build
	    cd build
	    cmake -DLLVM_ENABLE_PROJECTS=clang -DCMAKE_BUILD_TYPE=Release -G "Unix Makefiles" ../llvm
	    make -j4
	    sudo make install
	    clang -v
    fi

    # Install NodeJS for and RHEL 7.x
    if [[ ${DISTRO} =~ rhel-7\.* ]]; then
	    printf -- 'Installing node...\n'
	    cd $CURDIR
	    NODE_VERSION="v17.5.0"
	    NODE_DISTRO=linux-s390x
	    wget https://nodejs.org/download/release/${NODE_VERSION}/node-${NODE_VERSION}-linux-s390x.tar.xz
	    sudo mkdir -p /usr/local/lib/nodejs
	    sudo tar -xJf node-$NODE_VERSION-$NODE_DISTRO.tar.xz -C /usr/local/lib/nodejs
	    export PATH=/usr/local/lib/nodejs/node-$NODE_VERSION-$NODE_DISTRO/bin:$PATH
    fi

    # Install protobuf 3.x for RHEL 7.x & SLES-12.5
    if [[ ${DISTRO} =~ rhel-7\.*  || ${DISTRO} == "sles-12.5" ]]; then
	    printf -- 'Installing node...\n'
	    cd $CURDIR
	    if [ -d "$CURDIR/protobuf" ]; then
		    sudo rm -rf "$CURDIR/protobuf"
	    fi
      git clone -b v"${PROTOBUF_VERSION}" https://github.com/protocolbuffers/protobuf.git
	    cd protobuf
	    git submodule update --init --recursive
	    ./autogen.sh
	    ./configure
	    make
	    sudo make install
	    sudo ldconfig
	    printf -- 'Build protobuf success \n'
    fi

    # Install yarn
    printf -- 'Installing yarn...\n'
    cd $CURDIR
    curl -o- -L https://yarnpkg.com/install.sh | bash
    export PATH="$HOME/.yarn/bin:$HOME/.config/yarn/global/node_modules/.bin:$PATH"

    # Install Rust
    printf -- 'Installing rust...\n'
    cd $CURDIR
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    source $HOME/.cargo/env

    # Install Go
    printf -- 'Configuration and Installation started \n'
    if [[ "${OVERRIDE}" == "true" ]]
    then
      printf -- 'Go exists on the system. Override flag is set to true hence updating the same\n ' |& tee -a "$LOG_FILE"
    fi

    # Install Go
    printf -- 'Downloading go binaries \n'
		cd $GOPATH
    wget -q https://storage.googleapis.com/golang/go"${GO_VERSION}".linux-s390x.tar.gz |& tee -a  "$LOG_FILE"
    chmod ugo+r go"${GO_VERSION}".linux-s390x.tar.gz
    sudo rm -rf /usr/local/go /usr/bin/go
    sudo tar -C /usr/local -xzf go"${GO_VERSION}".linux-s390x.tar.gz
    sudo ln -sf /usr/local/go/bin/go /usr/bin/ 
    sudo ln -sf /usr/local/go/bin/gofmt /usr/bin/
    printf -- 'Extracted the tar in /usr/local and created symlink\n'
    if [[ "${ID}" != "ubuntu" ]]
    then
      sudo ln -sf /usr/bin/gcc /usr/bin/s390x-linux-gnu-gcc 
      printf -- 'Symlink done for gcc \n' 
    fi
    #Clean up the downloaded zip
    cleanup
    #Verify if go is configured correctly
    if go version | grep -q "$GO_VERSION"
    then
      printf -- "Installed %s successfully \n" "$GO_VERSION"
    else
      printf -- "Error while installing Go, exiting with 127 \n";
      exit 127;
    fi
    go version
    export PATH=$PATH:$GOPATH/bin
    printf -- "Install Go success\n"

    # Install pkg-config
    cd $CURDIR
    export GO111MODULE=on
    go install github.com/influxdata/pkg-config@v0.2.13
    which -a pkg-config

    # Download and configure InfluxDB
    printf -- 'Downloading InfluxDB. Please wait.\n'
    cd $CURDIR
    git clone https://github.com/influxdata/influxdb.git
    cd influxdb
    git checkout v${PACKAGE_VERSION}

    #Build InfluxDB
    printf -- 'Building InfluxDB \n'
    printf -- 'Build might take some time. Sit back and relax\n'
    export NODE_OPTIONS=--max_old_space_size=4096
    make
    sudo cp ./bin/linux/* /usr/bin
    printf -- 'Successfully installed InfluxDB. \n'

    #Run Test
    runTests

    cleanup
}

function runTests() {
	set +e
	if [[ "$TESTS" == "true" ]]; then
		printf -- "TEST Flag is set, continue with running test \n"  >> "$LOG_FILE"

		cd ${CURDIR}/influxdb
		make test
	fi
	set -e
}

function logDetails() {
	printf -- '**************************** SYSTEM DETAILS *************************************************************\n' >"$LOG_FILE"

	if [ -f "/etc/os-release" ]; then
		cat "/etc/os-release" >>"$LOG_FILE"
	fi

	cat /proc/version >>"$LOG_FILE"
	printf -- '*********************************************************************************************************\n' >>"$LOG_FILE"

	printf -- "Detected %s \n" "$PRETTY_NAME"
	printf -- "Request details : PACKAGE NAME= %s , VERSION= %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" |& tee -a "$LOG_FILE"

}

# Print the usage message
function printHelp() {
	echo
	echo "Usage: "
	echo "  bash build_influxdb.sh [-y install-without-confirmation -t run-test-cases]"
	echo
}

while getopts "h?dyt" opt; do
	case "$opt" in
	h | \?)
		printHelp
		exit 0
		;;
	d)
		set -x
		;;
	y)
		FORCE="true"
		;;
	t)
		TESTS="true"
		;;

	esac
done

function gettingStarted() {
    export PATH=$PATH:/usr/local/go/bin
    GOPATH=$(go env GOPATH)
    printf -- '\n********************************************************************************************************\n'
    printf -- "\n* Getting Started * \n"
    printf -- "\nAll relevant binaries are installed in /usr/bin. Be sure to set the PATH as follows:\n"
    printf -- "\n     	export PATH=/usr/local/go/bin:\$PATH\n"
    printf -- "\nMore information can be found here: https://docs.influxdata.com/influxdb/v2.7/get-started\n"
    printf -- '\n\n**********************************************************************************************************\n'
}

###############################################################################################################

logDetails
DISTRO="$ID-$VERSION_ID"
checkPrequisites #Check Prequisites

case "$DISTRO" in
"ubuntu-20.04" | "ubuntu-22.04" | "ubuntu-23.04" | "ubuntu-23.10")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	printf -- "Installing the dependencies for $PACKAGE_NAME from repository \n" |& tee -a "$LOG_FILE"
	sudo apt-get update >/dev/null
	sudo apt-get install -y clang git gcc g++ wget bzr protobuf-compiler libprotobuf-dev curl pkg-config make nodejs |& tee -a "$LOG_FILE"
	configureAndInstall |& tee -a "$LOG_FILE"
	;;

"sles-12.5")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	printf -- "Installing the dependencies for $PACKAGE_NAME from repository \n" |& tee -a "$LOG_FILE"
	sudo zypper install -y git gcc7 gcc7-c++ wget which bzr tar gzip curl unzip patch pkg-config nodejs14 make bzip2 cmake libarchive13 libopenssl-devel unzip zip libnghttp2-devel autoconf automake gzip libtool zlib-devel |& tee -a "$LOG_FILE"
	sudo update-alternatives --install /usr/bin/cc cc /usr/bin/gcc-7 40
	sudo update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-7 40
	sudo update-alternatives --install /usr/bin/g++ g++ /usr/bin/g++-7 40
	sudo update-alternatives --install /usr/bin/c++ c++ /usr/bin/g++-7 40
	sudo /sbin/ldconfig
	configureAndInstall |& tee -a "$LOG_FILE"
	;;

"sles-15.4" )
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	printf -- "Installing the dependencies for $PACKAGE_NAME from repository \n" |& tee -a "$LOG_FILE"
	sudo zypper install -y git gcc gcc-c++ wget which protobuf-devel tar gzip curl patch pkg-config nodejs16 make clang7  |& tee -a "$LOG_FILE"
	wget https://launchpad.net/bzr/2.7/2.7.0/+download/bzr-2.7.0.tar.gz
	tar zxf bzr-2.7.0.tar.gz
	export PATH=$PATH:$HOME/bzr-2.7.0
	configureAndInstall |& tee -a "$LOG_FILE"
	;;

"sles-15.5" )
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	printf -- "Installing the dependencies for $PACKAGE_NAME from repository \n" |& tee -a "$LOG_FILE"
	sudo zypper install -y git gcc gcc-c++ wget which protobuf-devel tar gzip curl patch pkg-config nodejs18 make clang7  |& tee -a "$LOG_FILE"
	wget https://launchpad.net/bzr/2.7/2.7.0/+download/bzr-2.7.0.tar.gz
	tar zxf bzr-2.7.0.tar.gz
	export PATH=$PATH:$HOME/bzr-2.7.0
	configureAndInstall |& tee -a "$LOG_FILE"
	;;

"rhel-7.8" | "rhel-7.9")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	printf -- "Installing the dependencies for $PACKAGE_NAME from repository \n" |& tee -a "$LOG_FILE"
	sudo subscription-manager repos --enable rhel-7-server-for-system-z-devtools-rpms |& tee -a "$LOG_FILE"
	sudo yum install -y git gcc gcc-c++ wget unzip bzr tar curl patch pkgconfig make llvm-toolset-7 autoconf automake gzip libtool zlib-devel |& tee -a "$LOG_FILE"
	source /opt/rh/llvm-toolset-7/enable
	export LIBCLANG_PATH=/opt/rh/llvm-toolset-7/root/usr/lib64
	clang --version |& tee -a "$LOG_FILE"
	configureAndInstall |& tee -a "$LOG_FILE"
	;;

"rhel-8.6" | "rhel-8.8" | "rhel-8.9")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	printf -- "Installing the dependencies for $PACKAGE_NAME from repository \n" |& tee -a "$LOG_FILE"
	sudo yum install -y clang git gcc gcc-c++ wget protobuf protobuf-devel tar curl patch pkg-config make nodejs python38  |& tee -a "$LOG_FILE"
	sudo ln -sf /usr/bin/python3 /usr/bin/python
	wget https://launchpad.net/bzr/2.7/2.7.0/+download/bzr-2.7.0.tar.gz
	tar zxf bzr-2.7.0.tar.gz
	export PATH=$PATH:$HOME/bzr-2.7.0
	configureAndInstall |& tee -a "$LOG_FILE"
	;;

"rhel-9.0" | "rhel-9.2" | "rhel-9.3")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	printf -- "Installing the dependencies for $PACKAGE_NAME from repository \n" |& tee -a "$LOG_FILE"
	sudo yum install -y clang git gcc gcc-c++ wget protobuf protobuf-devel tar curl patch pkg-config make nodejs python3  |& tee -a "$LOG_FILE"
	sudo ln -sf /usr/bin/python3 /usr/bin/python
	wget https://launchpad.net/bzr/2.7/2.7.0/+download/bzr-2.7.0.tar.gz
	tar zxf bzr-2.7.0.tar.gz
	export PATH=$PATH:$HOME/bzr-2.7.0
	configureAndInstall |& tee -a "$LOG_FILE"
	;;

*)
	printf -- "%s not supported \n" "$DISTRO" |& tee -a "$LOG_FILE"
	exit 1
	;;
esac

gettingStarted |& tee -a "$LOG_FILE"
