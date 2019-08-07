#!/bin/bash
# © Copyright IBM Corporation 2019.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/helm/2.14.2/build_helm.sh
# Execute build script: bash build_helm.sh    (provide -h for help)
#
set -e -o pipefail

PACKAGE_NAME="helm"
PACKAGE_VERSION="2.14.2"
CURDIR="$PWD"
PATCH_URL="https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Helm/${PACKAGE_VERSION}/patch"
HELM_REPO_URL="https://github.com/kubernetes/helm.git"
LOG_FILE="$CURDIR/logs/${PACKAGE_NAME}-${PACKAGE_VERSION}-$(date +"%F-%T").log"
FORCE="false"
GO_VERSION="1.12.5"
GOPATH="${CURDIR}"
trap cleanup 0 1 2 ERR

#Check if directory exists
if [ ! -d "$CURDIR/logs/" ]; then
	mkdir -p "$CURDIR/logs/"
fi

source "/etc/os-release"

function prepare() {

	if command -v "sudo" >/dev/null; then
		printf -- 'Sudo : Yes\n' >>"$LOG_FILE"
	else
		printf -- 'Sudo : No \n' >>"$LOG_FILE"
		printf -- 'You can install sudo from repository using apt, yum or zypper based on your distro. \n'
		exit 1
	fi

	if [ $(command -v helm) ]
	then
        printf -- "helm detected skipping helm installation \n" |& tee -a "$LOG_FILE"
		exit 0
	fi

	if [[ "$FORCE" == "true" ]]; then
		printf -- 'Force attribute provided hence continuing with install without confirmation message\n' |& tee -a "$LOG_FILE"
	else
		
			printf -- 'Following packages are needed before going ahead\n' |& tee -a "$LOG_FILE"
			printf -- 'go version:GO 1.12+\n\n' |& tee -a "$LOG_FILE"
			printf -- 'Build might take some time.Sit back and relax\n' |& tee -a "$LOG_FILE"
			while true; do
				read -r -p "Do you want to continue (y/n) ? :  " yn
				case $yn in
				[Yy]*)

					break
					;;
				[Nn]*) exit ;;
				*) echo "Please provide Correct input to proceed." ;;
				esac
			done
		
	fi
}

function cleanup() {

	rm -rf "${CURDIR}/glide-v0.13.0-linux-s390x.tar.gz"
	rm -rf "${CURDIR}/src/k8s.io/helm"
	printf -- '\nCleaned up the artifacts\n' >>"$LOG_FILE"
}

function configureAndInstall() {
	printf -- '\nConfiguration and Installation started \n'
	
	#Checking if Docker is instaleld
	printf -- "\nChecking if Docker is already present on the system . . . \n" | tee -a "$LOG_FILE"
	   if [ -x "$(command -v docker)" ]; then
	    docker --version | grep "Docker version" | tee -a "$LOG_FILE"
	    echo "Docker exists !!" | tee -a "$LOG_FILE"
	    docker ps 2>&1 | tee -a "$LOG_FILE"
	   else
	    printf -- "\n Please install and run Docker first !! \n" | tee -a "$LOG_FILE"
	    exit 1
	   fi


	#Installing dependencies
	
		printf -- 'User responded with Yes. \n'
		if command -v "go" >/dev/null; then
				printf -- "Go detected\n"
		else
				printf -- 'Installing go\n'
				cd "${CURDIR}"
				wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Go/${GO_VERSION}/build_go.sh
				bash build_go.sh 
				printf -- 'go installed\n'
		fi


	

	#Setting environment variable needed for building
	export GOPATH="${CURDIR}"
	export PATH=$GOPATH/bin:$PATH

	#Install Glide
	cd $GOPATH
	wget https://github.com/Masterminds/glide/releases/download/v0.13.1/glide-v0.13.1-linux-s390x.tar.gz
	tar -xzf glide-v0.13.1-linux-s390x.tar.gz
	export PATH=$GOPATH/linux-s390x:$PATH:$GOPATH/bin
	# #Added symlink for PATH
	# sudo ln -sf $GOPATH/linux-s390x/glide /usr/bin/

  
	# Download and configure helm
	printf -- 'Downloading helm. Please wait.\n'
	mkdir -p $GOPATH/src/k8s.io
	cd $GOPATH/src/k8s.io
	git clone -b v$PACKAGE_VERSION $HELM_REPO_URL
	sleep 2

	# Add patch
	cd "${CURDIR}"
	curl -o Makefile.diff $PATCH_URL/Makefile.diff
	patch "$GOPATH/src/k8s.io/helm/Makefile" Makefile.diff 

	
	#Dowload Helm binary
	cd $GOPATH/src/k8s.io/helm/rootfs
        wget https://get.helm.sh/helm-v2.14.2-linux-s390x.tar.gz
        tar -xzvf helm-v2.14.2-linux-s390x.tar.gz
        mv linux-s390x/helm .
        mv linux-s390x/tiller .
	
	#Build helm
	printf -- 'Building helm \n'
	printf -- 'Build might take some time.Sit back and relax\n'
	cd $GOPATH/src/k8s.io/helm
	make docker-build

	#Copy binaries to /usr/bin
	sudo cp $GOPATH/src/k8s.io/helm/rootfs/helm /usr/bin
	sudo cp $GOPATH/src/k8s.io/helm/rootfs/tiller /usr/bin
	printf -- '\nCopied binaries in /usr/bin\n'

	printenv >>"$LOG_FILE"
	cleanup

}

function logDetails() {
	printf -- 'SYSTEM DETAILS\n' >"$LOG_FILE"
	if [ -f "/etc/os-release" ]; then
		cat "/etc/os-release" >>"$LOG_FILE"
	fi

	cat /proc/version >>"$LOG_FILE"
	printf -- "\nDetected %s \n" "$PRETTY_NAME"
	printf -- "Request details : PACKAGE NAME= %s , VERSION= %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" |& tee -a "$LOG_FILE"
}

# Print the usage message
function printHelp() {
	echo
	echo "Usage: "
	echo "  build_helm.sh  [-d debug] [-y install-without-confirmation]"
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
	esac
done

function printSummary() {
	printf -- '\n********************************************************************************************************\n'
	printf -- "\n* Getting Started * \n"
	printf -- "\n*All relevant binaries are created and placed in /usr/bin \n"
	printf -- '\n\nRefer step No. 4 from the build instructions ( https://github.com/linux-on-ibm-z/docs/wiki/Building-Helm ) for Helm verification.'
	printf -- '\n\n**********************************************************************************************************\n'

}

logDetails
prepare

DISTRO="$ID-$VERSION_ID"
case "$DISTRO" in
"ubuntu-16.04" | "ubuntu-18.04" | "ubuntu-19.04")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	printf -- "Installing dependencies... it may take some time.\n"
	sudo apt-get update
	sudo apt-get install -y wget tar git make patch gcc
	configureAndInstall |& tee -a "$LOG_FILE"
	;;

"rhel-7.5" | "rhel-7.6")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	printf -- "Installing dependencies... it may take some time.\n"
	sudo yum install -y wget tar git make iptables-devel.s390x iptables-utils.s390x iptables.s390x patch socat
	configureAndInstall |& tee -a "$LOG_FILE"
	;;
	
"rhel-8.0")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	printf -- "Installing dependencies... it may take some time.\n"
	sudo yum install --nobest -y wget tar git make iptables-devel.s390x iptables-utils.s390x patch socat
	configureAndInstall |& tee -a "$LOG_FILE"
	;;	

"sles-12.4" | "sles-15" | "sles-15.1")
	printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
	printf -- "Installing dependencies... it may take some time.\n"
	sudo zypper install -y  wget tar git iptables patch curl device-mapper-devel bison make which socat gzip
	configureAndInstall |& tee -a "$LOG_FILE"
	;;

*)
	printf -- "%s not supported \n" "$DISTRO" |& tee -a "$LOG_FILE"
	exit 1
	;;
esac

printSummary |& tee -a "$LOG_FILE"
