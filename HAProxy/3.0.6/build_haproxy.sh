#!/bin/bash
# © Copyright IBM Corporation 2024.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/HAProxy/3.0.6/build_haproxy.sh
# Execute build script: bash build_haproxy.sh    (provide -h for help)


set -e -o pipefail

PACKAGE_NAME="haproxy"
PACKAGE_VERSION="3.0.6"
CURDIR="$(pwd)"
FORCE="false"
TESTS='false'
LOG_FILE="$CURDIR/logs/${PACKAGE_NAME}-${PACKAGE_VERSION}-$(date +"%F-%T").log"

OPENSSL_VERSION='openssl-1.1.1w'
OPENSSL_URL="https://www.openssl.org/source/${OPENSSL_VERSION}.tar.gz"
PYTHON_VERSION='3.10.13'
PYTHON_URL="https://www.python.org/ftp/python/${PYTHON_VERSION}/Python-${PYTHON_VERSION}.tgz"

trap cleanup 0 1 2 ERR

#Check if directory exists
if [ ! -d "$CURDIR/logs/" ]; then
   mkdir -p "$CURDIR/logs/"
fi

source "/etc/os-release"

function prepare() {
    if  command -v "sudo" > /dev/null ;
    then
        printf -- 'Sudo : Yes\n' >> "$LOG_FILE"
    else
        printf -- 'Sudo : No \n' >> "$LOG_FILE"
        printf -- 'Install sudo from repository using apt, yum or zypper based on your distro. \n';
    exit 1;
    fi;

    if [[ "$FORCE" == "true" ]] ;
    then
        printf -- 'Force attribute provided hence continuing with install without confirmation message\n' |& tee -a "$LOG_FILE"
    else
        # Ask user for prerequisite installation
        printf -- "\nAs part of the installation , dependencies would be installed/upgraded.\n";
        while true; do
		    read -r -p "Do you want to continue (y/n) ? :  " yn
		    case $yn in
  	 		    [Yy]* ) printf -- 'User responded with Yes. \n' >> "$LOG_FILE";
	                    break;;
    		    [Nn]* ) exit;;
    		    *) 	echo "Please provide confirmation to proceed.";;
	 	    esac
        done
    fi
}


function cleanup() {
    # Remove artifacts
    if [ -f "$CURDIR/haproxy-${PACKAGE_VERSION}.tar.gz" ]; then
      rm -rf "$CURDIR/haproxy-"*".tar.gz"*
    fi
    if [ -d "$CURDIR/haproxy-${PACKAGE_VERSION}" ]; then
      rm -rf "haproxy-"*
    fi
    if [ -f "$CURDIR/lua-${PACKAGE_VERSION}.tar.gz" ]; then
      rm -rf "$CURDIR/lua-"*".tar.gz"*
    fi
    if [ -d "$CURDIR/lua-${PACKAGE_VERSION}" ]; then
      rm -rf "lua-"*
    fi
    if [ -d "$CURDIR/vtest" ]; then
      rm -rf "$CURDIR/vtest"
    fi
    printf -- "Cleaned up the artifacts\n" >> "$LOG_FILE"
}

function buildAndInstallPython3() {

  cd $SOURCE_ROOT
  wget $PYTHON_URL
  tar -xzf "Python-${PYTHON_VERSION}.tgz"
  cd "Python-${PYTHON_VERSION}"
  ./configure
  make && sudo make install
  python3 -V
}

function buildAndInstallOpenSSL() {

  cd $SOURCE_ROOT
  wget --no-check-certificate $OPENSSL_URL
  tar -xzf "${OPENSSL_VERSION}.tar.gz"
  cd $OPENSSL_VERSION
  ./config --prefix=/usr --openssldir=/usr
  make
  sudo make install
}

function buildAndInstallLua() {
  printf -- 'Building lua\n'
  cd $SOURCE_ROOT
  wget --no-check-certificate https://www.lua.org/ftp/lua-5.4.0.tar.gz
  tar zxf lua-5.4.0.tar.gz
  cd lua-5.4.0
  sed -i '61 i \\t$(CC) -shared -ldl -Wl,-soname,liblua$R.so -o liblua$R.so $? -lm $(MYLDFLAGS)\n' src/Makefile
  make clean
  make linux "MYCFLAGS=-fPIC" "R=5.4"
  sudo make install
  
  if [[ "$DISTRO" == "ubuntu-20.04" ]]; then
     sudo cp src/liblua5.4.so /usr/lib/
     sudo cp /usr/local/bin/lua* /usr/bin/
     sudo rm -f /usr/lib/liblua.so
     sudo ln -s /usr/lib/liblua5.4.so /usr/lib/liblua.so
     lua -v
  else
     sudo cp src/liblua5.4.so /usr/lib64/
     sudo cp /usr/local/bin/lua* /usr/bin/
     sudo rm -f /usr/lib64/liblua.so
     sudo ln -s /usr/lib64/liblua5.4.so /usr/lib64/liblua.so
     lua -v
  fi
  printf -- 'lua installed successfully\n'
}

function installAdditionalDependencies() {
  case "$DISTRO" in
  "rhel-8.8" | "rhel-8.10")
    printf -- "Installing additional dependencies for %s %s on %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO"
    sudo yum install -y socat curl python2 python38
    ;;

  "rhel-9.2" | "rhel-9.4")
    printf -- "Installing additional dependencies for %s %s on %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO"
    sudo yum install -y --allowerasing socat curl python3
    ;;

  "sles-15.5" | "sles-15.6")
    printf -- "Installing additional dependencies for %s %s on %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO"
    sudo zypper install -y ninja socat python curl
    ;;

   "ubuntu-20.04")
    printf -- "Installing additional dependencies for %s %s on %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO"
    sudo apt-get update
    sudo apt-get install -y ninja-build socat curl python python3.8
    ;;

  "ubuntu-22.04")
    printf -- "Installing additional dependencies for %s %s on %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO"
    sudo apt-get update
    sudo apt-get install -y ninja-build socat curl python2 python3
    ;;

  "ubuntu-24.04" | "ubuntu-24.10")
    printf -- "Installing additional dependencies for %s %s on %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO"
    sudo apt-get update
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y tzdata ninja-build socat curl python3
    ;;

  *)
    printf -- "%s not supported \n" "$DISTRO" |& tee -a "${LOG_FILE}"
    exit 1
    ;;
  esac
}

function runRegressionTests() {

  cd "$CURDIR"
  cd "haproxy-${PACKAGE_VERSION}"

  scripts/build-vtest.sh

  make -C addons/wurfl/dummy

  make -j$(nproc) all \
      ERR=1 \
      TARGET=linux-glibc \
      CC=gcc \
      DEBUG="-DDEBUG_STRICT -DDEBUG_MEMORY_POOLS -DDEBUG_POOL_INTEGRITY" \
      USE_ZLIB=1 USE_PCRE2=1 USE_PCRE2_JIT=1 USE_LUA=1 USE_OPENSSL=1 USE_SYSTEMD=1 USE_WURFL=1 WURFL_INC=addons/wurfl/dummy WURFL_LIB=addons/wurfl/dummy USE_DEVICEATLAS=1 DEVICEATLAS_SRC=addons/deviceatlas/dummy USE_PROMEX=1 USE_51DEGREES=1 51DEGREES_SRC=addons/51degrees/dummy/pattern \
      ADDLIB="-Wl,-rpath,/usr/local/lib/ -Wl,-rpath,$HOME/opt/lib/"

  sudo make install
  make reg-tests VTEST_PROGRAM=../vtest/vtest REGTESTS_TYPES=default,bug,devel
}

function configureAndInstall() {
    printf -- "Configuration and Installation started \n"

    # Download HAProxy
    cd "$CURDIR"
    wget "https://www.haproxy.org/download/3.0/src/haproxy-${PACKAGE_VERSION}.tar.gz"
    tar xzf "haproxy-${PACKAGE_VERSION}.tar.gz"
    cd "haproxy-${PACKAGE_VERSION}"
    printf -- "Downloaded HAProxy.\n" >> "$LOG_FILE"

    # Build and install HAProxy
    make all TARGET=linux-glibc USE_ZLIB=1 USE_PCRE2=1 USE_PCRE2_JIT=1 USE_LUA=1 USE_OPENSSL=1 USE_SYSTEMD=1
    sudo make install
    printf -- "Successfully built and installed HAProxy.\n" >> "$LOG_FILE"

    # Add haproxy to /usr/bin
    sudo ln -sf /usr/local/sbin/haproxy /usr/sbin/

    # Run tests if -t
    if [[ "$TESTS" == "true" ]]; then
      installAdditionalDependencies
      runRegressionTests
    fi

    # Cleanup
    cleanup

    # Verify haproxy installation
    if command -v /usr/local/sbin/haproxy > /dev/null; then
        printf -- "%s installation verified.\n" "$PACKAGE_NAME"
    else
        printf -- "Error while installing %s, exiting with 127 \n" "$PACKAGE_NAME";
        exit 127;
    fi
}


function logDetails() {
    printf -- '**************************** SYSTEM DETAILS *************************************************************\n' >"$LOG_FILE"
    if [ -f "/etc/os-release" ]; then
        cat "/etc/os-release" >> "$LOG_FILE"
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
    echo " bash build_haproxy.sh  [-d debug] [-y install-without-confirmation] [-t install and run tests]"
    echo
}


while getopts "h?dty" opt; do
    case "$opt" in
    h | \?)
        printHelp
        exit 0
        ;;
    d)
        set -x
        ;;
    t)
        TESTS="true"
        ;;
    y)
        FORCE="true"
        ;;
    esac
done


function gettingStarted() {
    printf -- '\n********************************************************************************************************\n'
    printf -- "\n* Getting Started * \n"
    printf -- "Running HAProxy: \n"
    printf -- "     haproxy [-f <cfgfile|cfgdir>]\n"
    printf -- "\nNote: Use sudo for users other than root \n\n"
    printf -- '********************************************************************************************************\n'
}

logDetails
prepare #Check Prequisites
DISTRO="$ID-$VERSION_ID"

case "$DISTRO" in
    "rhel-8.8" | "rhel-8.10")
        printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
        printf -- "Installing dependencies... it may take some time.\n"
        sudo yum install -y gcc gcc-c++ gzip make tar wget xz zlib-devel pcre2 pcre2-devel systemd-devel openssl-devel diffutils |& tee -a "$LOG_FILE"
	      buildAndInstallLua |& tee -a "$LOG_FILE"
        configureAndInstall |& tee -a "$LOG_FILE"
        ;;
    "rhel-9.2" | "rhel-9.4" )
        printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
        printf -- "Installing dependencies... it may take some time.\n"
        sudo yum install -y gcc gcc-c++ gzip make tar wget xz zlib-devel lua-devel pcre2 pcre2-devel systemd-devel compat-openssl11 openssl-devel diffutils perl |& tee -a "$LOG_FILE"
        buildAndInstallOpenSSL |& tee -a "$LOG_FILE"
        configureAndInstall |& tee -a "$LOG_FILE"
        ;;
    "sles-15.5" | "sles-15.6")
        printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
        printf -- "Installing dependencies... it may take some time.\n"
        sudo zypper install -y awk gcc gcc-c++ gzip make tar wget xz zlib-devel libopenssl-devel lua54-devel pcre2-devel \
          systemd-devel |& tee -a "$LOG_FILE"
        configureAndInstall |& tee -a "$LOG_FILE"
        ;;
    "ubuntu-20.04" | "ubuntu-22.04" | "ubuntu-24.04" | "ubuntu-24.10")
        printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
        printf -- "Installing dependencies... it may take some time.\n"
        sudo apt-get update
	      if [[ "$DISTRO" == "ubuntu-20.04" ]] ; then	
		        sudo apt-get install -y gcc g++ gzip make tar wget curl xz-utils zlib1g-dev libpcre2-dev libsystemd-dev libssl-dev |& tee -a "$LOG_FILE"
		        buildAndInstallLua |& tee -a "$LOG_FILE"
	      else
		        sudo apt-get install -y gcc g++ gzip make tar wget curl xz-utils zlib1g-dev liblua5.4-dev libpcre2-dev libsystemd-dev libssl-dev |& tee -a "$LOG_FILE"
      	fi
        configureAndInstall |& tee -a "$LOG_FILE"
        ;;    
    *)
        printf -- "%s not supported \n" "$DISTRO" |& tee -a "$LOG_FILE"
        exit 1
        ;;
esac


gettingStarted |& tee -a "$LOG_FILE"
