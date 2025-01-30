#!/bin/bash
# ©  Copyright IBM Corporation 2022.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Logstash/8.5.2/build_logstash.sh
# Execute build script: bash build_logstash.sh    (provide -h for help)
#

set -e -o pipefail

PACKAGE_NAME="logstash"
PACKAGE_VERSION="8.5.2"
FORCE=false
CURDIR="$(pwd)"
LOG_FILE="${CURDIR}/logs/${PACKAGE_NAME}-${PACKAGE_VERSION}-$(date +"%F-%T").log"
NON_ROOT_USER="$(whoami)"
JAVA_PROVIDED="OpenJDK11"
BUILD_ENV="$HOME/setenv.sh"

trap cleanup 1 2 ERR

#Check if directory exists
if [ ! -d "$CURDIR/logs/" ]; then
        mkdir -p "$CURDIR/logs/"
fi

if [ -f "/etc/os-release" ]; then
        source "/etc/os-release"
fi

function prepare() {
        if command -v "sudo" >/dev/null; then
                printf -- 'Sudo : Yes\n'
        else
                printf -- 'Sudo : No \n'
                printf -- 'Install sudo from repository using apt, yum or zypper based on your distro. \n'
                exit 1
        fi

        if [[ "$JAVA_PROVIDED" != "Semeru17" && "$JAVA_PROVIDED" != "Temurin11" && "$JAVA_PROVIDED" != "OpenJDK11" ]]; then
                printf "$JAVA_PROVIDED is not supported, Please use valid java from {Semeru17, Temurin11, OpenJDK11} only"
                exit 1
        fi

        if [[ "$FORCE" == "true" ]]; then
                printf -- 'Force attribute provided hence continuing with install without confirmation message\n' |& tee -a "${LOG_FILE}"
        else
                # Ask user for prerequisite installation
                printf -- "\nAs part of the installation, dependencies would be installed/upgraded. \n"
                while true; do
                        read -r -p "Do you want to continue (y/n) ? :  " yn
                        case $yn in
                        [Yy]*)
                                printf -- 'User responded with Yes. \n' |& tee -a "${LOG_FILE}"
                                break
                                ;;
                        [Nn]*) exit ;;
                        *) echo "Please provide confirmation to proceed." ;;
                        esac
                done
        fi

        # zero out
        true > "$BUILD_ENV"
}

function cleanup() {
        sudo rm -rf "${CURDIR}/logstash-oss-${PACKAGE_VERSION}-linux-aarch64.tar.gz" "${CURDIR}/ibm-semeru-open-jdk_s390x_linux_17.0.4.1_1_openj9-0.33.1.tar.gz" "${CURDIR}/OpenJDK11U-jdk_s390x_linux_hotspot_11.0.16.1_1.tar.gz"
        printf -- 'Cleaned up the artifacts\n' >>"${LOG_FILE}"
}

function configureAndInstall() {

        printf -- 'Configuration and Installation started \n'

	if [[ "$JAVA_PROVIDED" == "Semeru17" ]]; then
		# Install Semeru17
		printf -- "\nInstalling Semeru17 . . . \n"
		cd $SOURCE_ROOT
		wget https://github.com/ibmruntimes/semeru17-binaries/releases/download/jdk-17.0.5%2B8_openj9-0.35.0/ibm-semeru-open-jdk_s390x_linux_17.0.5_8_openj9-0.35.0.tar.gz
		tar -xzf ibm-semeru-open-jdk_s390x_linux_17.0.5_8_openj9-0.35.0.tar.gz
		export LS_JAVA_HOME=$PWD/jdk-17.0.5+8
		printf -- "export LS_JAVA_HOME=$PWD/jdk-17.0.5+8\n" >> "$BUILD_ENV"
		printf -- "Installation of Semeru17 is successful\n" >> "$LOG_FILE"

	elif [[ "$JAVA_PROVIDED" == "Temurin11" ]]; then
	        # Install Temurin11
		printf -- "\nInstalling Temurin11 . . . \n"
		cd $SOURCE_ROOT
		wget https://github.com/adoptium/temurin11-binaries/releases/download/jdk-11.0.17%2B8/OpenJDK11U-jdk_s390x_linux_hotspot_11.0.17_8.tar.gz
		tar -xzf OpenJDK11U-jdk_s390x_linux_hotspot_11.0.17_8.tar.gz
		export LS_JAVA_HOME=$PWD/jdk-11.0.17+8
		printf -- "export LS_JAVA_HOME=$PWD/jdk-11.0.17+8\n" >> "$BUILD_ENV"
		printf -- "Installation of Temurin11 is successful\n" >> "$LOG_FILE"

	elif [[ "$JAVA_PROVIDED" == "OpenJDK11" ]]; then
		if [[ "${ID}" == "ubuntu" ]]; then
                        sudo DEBIAN_FRONTEND=noninteractive apt-get install -y openjdk-11-jdk
                        export LS_JAVA_HOME=/usr/lib/jvm/java-11-openjdk-s390x
                        printf -- "export LS_JAVA_HOME=/usr/lib/jvm/java-11-openjdk-s390x\n" >> "$BUILD_ENV"
		elif [[ "${ID}" == "rhel" ]]; then
                        sudo yum install -y java-11-openjdk-devel
                        export LS_JAVA_HOME=/usr/lib/jvm/java-11-openjdk
                        printf -- "export LS_JAVA_HOME=/usr/lib/jvm/java-11-openjdk\n" >> "$BUILD_ENV"
		elif [[ "${ID}" == "sles" ]]; then
                        sudo zypper install -y java-11-openjdk java-11-openjdk-devel
                        export LS_JAVA_HOME=/usr/lib64/jvm/java-11-openjdk
                        printf -- "export LS_JAVA_HOME=/usr/lib64/jvm/java-11-openjdk\n" >> "$BUILD_ENV"
		fi
           printf -- "Installation of OpenJDK 11 is successful\n" >> "$LOG_FILE"
        else
                printf "$JAVA_PROVIDED is not supported, Please use valid java from {Semeru17, Temurin11, OpenJDK11} only"
                exit 1
        fi
        export PATH=$LS_JAVA_HOME/bin:$PATH
        printf -- "export PATH=$LS_JAVA_HOME/bin:$PATH\n" >> "$BUILD_ENV"
        java -version |& tee -a "$LOG_FILE"

        # Downloading and installing Logstash
        printf -- 'Downloading and installing Logstash.\n'
        cd "${CURDIR}"
        wget https://artifacts.elastic.co/downloads/logstash/logstash-oss-"$PACKAGE_VERSION"-linux-aarch64.tar.gz
        sudo mkdir -p /usr/share/logstash
        sudo tar -xzf logstash-oss-"$PACKAGE_VERSION"-linux-aarch64.tar.gz -C /usr/share/logstash --strip-components 1
        sudo ln -sf /usr/share/logstash/bin/* /usr/bin
        
	if ([[ -z "$(cut -d: -f1 /etc/group | grep elastic)" ]]); then
                printf -- '\nCreating group elastic.\n'
                sudo /usr/sbin/groupadd elastic # If group is not already created
        fi
	
        sudo chown "$NON_ROOT_USER:elastic" -R /usr/share/logstash
        
	# Cleanup
        cleanup
        
	# Verifying Logstash installation
        if command -v "$PACKAGE_NAME" >/dev/null; then
                printf -- "%s installation completed. Please check the Usage to start the service.\n" "$PACKAGE_NAME"
        else
                printf -- "Error while installing %s, exiting with 127 \n" "$PACKAGE_NAME"
                exit 127
        fi
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
        echo "  bash build_logstash.sh  [-d debug] [-y install-without-confirmation] [-j Java to use from {Semeru17, Temurin11, OpenJDK11}]"
        echo "  default: If no -j specified, openjdk-11 will be installed"
        echo
}

while getopts "h?dyj:" opt; do
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
        j)
                JAVA_PROVIDED="$OPTARG"
                ;;
        esac
done

function gettingStarted() {
        printf -- '\n********************************************************************************************************\n'
        printf -- "\n* Getting Started * \n"
        printf -- "Note: Environmental Variables needed have been added to $HOME/setenv.sh\n"
        printf -- "Note: To set the Environmental Variables needed for Logstash, please run: source $HOME/setenv.sh \n"
        printf -- "Run Logstash: \n"
        printf -- "    logstash -V \n\n"
        printf -- "Visit https://www.elastic.co/support/matrix#matrix_jvm for more information.\n\n"
        printf -- '********************************************************************************************************\n'
}

###############################################################################################################

logDetails
prepare

DISTRO="$ID-$VERSION_ID"
case "$DISTRO" in
"ubuntu-18.04" | "ubuntu-20.04" | "ubuntu-22.04")
        printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "${LOG_FILE}"
        sudo apt-get update
        sudo apt-get install -y make tar wget gzip curl |& tee -a "${LOG_FILE}"
        configureAndInstall |& tee -a "${LOG_FILE}"
        ;;

"rhel-7.8" | "rhel-7.9" | "rhel-8.4" | "rhel-8.6" | "rhel-8.7" | "rhel-9.0" | "rhel-9.1")
        printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "${LOG_FILE}"
        sudo yum install -y gcc make tar wget |& tee -a "${LOG_FILE}"
        configureAndInstall |& tee -a "${LOG_FILE}"
        ;;

"sles-12.5" | "sles-15.3" | "sles-15.4")
        printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "${LOG_FILE}"
        sudo zypper install -y gawk gcc gzip make tar wget |& tee -a "${LOG_FILE}"
        configureAndInstall |& tee -a "${LOG_FILE}"
        ;;

*)
        printf -- "%s not supported \n" "$DISTRO" |& tee -a "${LOG_FILE}"
        exit 1

        ;;
esac

gettingStarted |& tee -a "${LOG_FILE}"
