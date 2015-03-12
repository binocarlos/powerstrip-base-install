#!/usr/bin/env bash

export DEBIAN_FRONTEND=noninteractive

# Make sure only root can run our script
if [ "$(id -u)" != "0" ]; then
   echo "This script must be run as root" 1>&2
   exit 1
fi

# resolve the folder this script is in so it can include the lib
# no matter where the script is called from
pushd `dirname $0` > /dev/null
SCRIPTPATH=`pwd -P`
popd > /dev/null

. $SCRIPTPATH/lib.sh

usage() {
cat <<EOF
Usage:
install.sh setup
install.sh help
EOF
  exit 1
}

main() {
  case "$1" in
  setup)                    shift; powerstrip-base-install-setup $@;;
  service)                  shift; powerstrip-base-install-write-service $@;;
  flocker-control)          shift; powerstrip-base-install-run-flocker-control $@;;
  flocker-zfs-agent)        shift; powerstrip-base-install-run-flocker-zfs-agent $@;;
  powerstrip-config)        shift; powerstrip-base-install-powerstrip-config $@;;
  powerstrip-flocker)       shift; powerstrip-base-install-run-powerstrip-flocker $@;;
  powerstrip-weave)         shift; powerstrip-base-install-run-powerstrip-weave $@;;
  powerstrip)               shift; powerstrip-base-install-run-powerstrip $@;;
  weave)                    shift; powerstrip-base-install-weave $@;;
  shutdown)                 shift; powerstrip-base-install-shutdown $@;;
  pullimages)               shift; powerstrip-base-install-pullimages $@;;
  *)                        usage $@;;
  esac
}

main "$@"