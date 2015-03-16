#!/usr/bin/env bash

export REAL_DOCKER_SOCKET=${REAL_DOCKER_SOCKET:=/var/run/docker.real.sock}
export FLOCKER_CONTROL_PORT=${FLOCKER_CONTROL_PORT:=80}
export FLOCKER_AGENT_PORT=${FLOCKER_AGENT_PORT:=4524}

export ZFS_AGENT_IMAGE=${ZFS_AGENT_IMAGE:=lmarsden/flocker-zfs-agent:latest}
export CONTROL_SERVICE_IMAGE=${CONTROL_SERVICE_IMAGE:=lmarsden/flocker-control:latest}
export POWERSTRIP_FLOCKER_IMAGE=${POWERSTRIP_FLOCKER_IMAGE:=clusterhq/powerstrip-flocker:latest}
export POWERSTRIP_WEAVE_IMAGE=${POWERSTRIP_WEAVE_IMAGE:=binocarlos/powerstrip-weave:latest}
export POWERSTRIP_IMAGE=${POWERSTRIP_IMAGE:=clusterhq/powerstrip:unix-socket}
export WEAVE_IMAGE=${WEAVE_IMAGE:=zettio/weave:latest}
export WEAVETOOLS_IMAGE=${WEAVETOOLS_IMAGE:=zettio/weavetools:latest}
export WEAVEDNS_IMAGE=${WEAVEDNS_IMAGE:=zettio/weavedns:latest}
export WAITFORWEAVE_IMAGE=${WAITFORWEAVE_IMAGE:=binocarlos/wait-for-weave:latest}

# resolve the folder this script is in
# this means we can point to the install.sh controller
pushd `dirname $0` > /dev/null
SCRIPTPATH=`pwd -P`
popd > /dev/null

# get the system ready for the installation
# this includes:
#
#   * apt-get update
#   * apt-get install deps
#
powerstrip-base-install-deps() {

  # ensure folder
  mkdir -p /etc/flocker

  # install deps
  apt-get update
  apt-get -y install \
    supervisor \
    socat
}

#
#
# DOCKER
#
#

# install docker
powerstrip-base-install-docker() {
  echo "Installing docker"
  apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys 36A1D7869245C8950F966E92D8576A8BA88D21E9
  echo deb https://get.docker.io/ubuntu docker main > /etc/apt/sources.list.d/docker.list
  apt-get update
  apt-get -y install lxc-docker
}

# Install and configure docker
# the main role is to make docker itself listen on the /var/run.docker.real.sock
# you can pass labels to the docker deamon as the arguments to this function
# e.g. powerstrip-base-configure-docker --label node=node1
#
powerstrip-base-install-configure-docker() {
  echo "Configuring docker"
  cat << EOF > /etc/default/docker
DOCKER_OPTS="-H unix://$REAL_DOCKER_SOCKET --dns 8.8.8.8 --dns 8.8.4.4 $@"
EOF
  rm -f /etc/docker/key.json
  service docker restart
  rm -f /var/run/docker.sock
}

#
#
# IMAGES
#
#

powerstrip-base-install-pullimage() {
  DOCKER_HOST="unix://$REAL_DOCKER_SOCKET" \
  docker pull $1
}

powerstrip-base-install-pullimages-master() {
  powerstrip-base-install-pullimage $CONTROL_SERVICE_IMAGE
}

powerstrip-base-install-pullimages-minion() {
  powerstrip-base-install-pullimage $ZFS_AGENT_IMAGE
  powerstrip-base-install-pullimage $POWERSTRIP_FLOCKER_IMAGE
  powerstrip-base-install-pullimage $POWERSTRIP_WEAVE_IMAGE
  powerstrip-base-install-pullimage $POWERSTRIP_IMAGE
  powerstrip-base-install-pullimage $WEAVE_IMAGE
  powerstrip-base-install-pullimage $WEAVETOOLS_IMAGE
  powerstrip-base-install-pullimage $WEAVEDNS_IMAGE
  powerstrip-base-install-pullimage $WAITFORWEAVE_IMAGE
}

powerstrip-base-install-pullimages() {
  case "$1" in
  master)                   shift; powerstrip-base-install-pullimages-master $@;;
  minion)                   shift; powerstrip-base-install-pullimages-minion $@;;
  esac
}

#
#
# UTILS
#
#

# generic tool to stop a docker container
powerstrip-base-install-stop-container() {
  DOCKER_HOST="unix://$REAL_DOCKER_SOCKET" \
  docker rm -f $1
}

# system config for powerstrip
powerstrip-base-install-sysconfig() {
  # nerf the ARP cache so the delay is minimal between assigning an IP to another container
  echo 5000 > /proc/sys/net/ipv4/neigh/default/base_reachable_time_ms
}

# extract the current zfs-agent uuid from the volume.json - sed sed sed!
powerstrip-base-install-get-flocker-uuid() {
  if [[ ! -f /etc/flocker/volume.json ]]; then
    >&2 echo "/etc/flocker/volume.json NOT FOUND";
    exit 1;
  fi
  # XXX should use actual json parser!
  cat /etc/flocker/volume.json | sed 's/.*"uuid": "//' | sed 's/"}//'
}

# wait until the named file exists
powerstrip-base-install-wait-for-file() {
  while [[ ! -f $1 ]]
  do
    echo "wait for file $1" && sleep 1
  done
}

powerstrip-base-install-wait-for-container() {
  while [[ ! `DOCKER_HOST=unix://$REAL_DOCKER_SOCKET docker inspect -f {{.State.Running}} $1` ]];
  do
    echo "wait for container $1" && sleep 1
  done
}

# check a file exists and if not exit with an error
powerstrip-base-install-ensure-file() {
  if [[ ! -f "$1" ]]; then
    >&2 echo "file: $1 not found"
    exit 1
  fi
}

# run a standalone weave command
powerstrip-base-install-weave() {
  DOCKER_HOST="unix://$REAL_DOCKER_SOCKET" \
  docker run -ti --rm \
    -e DOCKER_SOCKET="$REAL_DOCKER_SOCKET" \
    -v $REAL_DOCKER_SOCKET:/var/run/docker.sock \
    $POWERSTRIP_WEAVE_IMAGE $@
}


#
#
# FLOCKER CONTAINERS
#
#

# run the zfs agent in a container
powerstrip-base-install-run-flocker-zfs-agent() {

  powerstrip-base-install-ensure-file /etc/flocker/my_address
  powerstrip-base-install-ensure-file /etc/flocker/master_address

  # configure from files - it is up to the vagrant installation to write these
  local IP=`cat /etc/flocker/my_address`
  local CONTROLIP=`cat /etc/flocker/master_address`


  # stop container if running
  powerstrip-base-install-stop-container flocker-zfs-agent

  # run zfs agent
  DOCKER_HOST="unix://$REAL_DOCKER_SOCKET" \
  docker run --rm --name flocker-zfs-agent --privileged \
    -v /etc/flocker:/etc/flocker \
    -v /var/run/docker.real.sock:/var/run/docker.sock \
    -v /root/.ssh:/root/.ssh \
    $ZFS_AGENT_IMAGE \
    flocker-zfs-agent $IP $CONTROLIP
}

# run the control service in a container
powerstrip-base-install-run-flocker-control() {

  # stop container if running
  powerstrip-base-install-stop-container flocker-control

  # run control service
  DOCKER_HOST="unix://$REAL_DOCKER_SOCKET" \
  docker run --rm --name flocker-control \
    -p $FLOCKER_CONTROL_PORT:$FLOCKER_CONTROL_PORT \
    -p $FLOCKER_AGENT_PORT:$FLOCKER_AGENT_PORT \
    $CONTROL_SERVICE_IMAGE \
    flocker-control -p $FLOCKER_CONTROL_PORT
}

#
#
# POWERSTRIP CONTAINERS
#
#

# run powerstrip flocker
powerstrip-base-install-run-powerstrip-flocker() {

  powerstrip-base-install-ensure-file /etc/flocker/my_address
  powerstrip-base-install-ensure-file /etc/flocker/master_address

  # wait for the flocker-zfs-agent to have started
  powerstrip-base-install-wait-for-file /etc/flocker/volume.json
  powerstrip-base-install-wait-for-container flocker-zfs-agent

  # configure from files - it is up to the vagrant installation to write these
  local IP=`cat /etc/flocker/my_address`
  local CONTROLIP=`cat /etc/flocker/master_address`
  local HOSTID=$(powerstrip-base-install-get-flocker-uuid)

  # this is needed in order to allow us to write data to the flocker ZFS
  zfs set readonly=off flocker

  powerstrip-base-install-stop-container powerstrip-flocker
  
  DOCKER_HOST="unix://$REAL_DOCKER_SOCKET" \
  docker run --name powerstrip-flocker \
    --expose 80 \
    -e "MY_NETWORK_IDENTITY=$IP" \
    -e "FLOCKER_CONTROL_SERVICE_BASE_URL=http://$CONTROLIP:80/v1" \
    -e "MY_HOST_UUID=$HOSTID" \
    $POWERSTRIP_FLOCKER_IMAGE
}

# run powerstrip weave
powerstrip-base-install-run-powerstrip-weave() {

  local PEERIP=`cat /etc/flocker/peer_address`

  powerstrip-base-install-stop-container powerstrip-weave
  powerstrip-base-install-stop-container weavewait
  powerstrip-base-install-stop-container weave

  DOCKER_HOST="unix://$REAL_DOCKER_SOCKET" \
  docker run --name powerstrip-weave \
    --expose 80 \
    -e DOCKER_SOCKET="$REAL_DOCKER_SOCKET" \
    -v $REAL_DOCKER_SOCKET:/var/run/docker.sock \
    $POWERSTRIP_WEAVE_IMAGE \
    launch $PEERIP
}

# run powerstrip itself
powerstrip-base-install-run-powerstrip() {
  rm -f /var/run/docker.sock
  powerstrip-base-install-stop-container powerstrip

  powerstrip-base-install-wait-for-container powerstrip-flocker
  powerstrip-base-install-wait-for-container powerstrip-weave

  DOCKER_HOST="unix://$REAL_DOCKER_SOCKET" \
  docker run --name powerstrip \
    -v /var/run:/host-var-run \
    -v /etc/powerstrip-demo/adapters.yml:/etc/powerstrip/adapters.yml \
    --link powerstrip-flocker:flocker \
    --link powerstrip-weave:weave \
    $POWERSTRIP_IMAGE
}

#
#
# POWERSTRIP CONFIG
#
#

# write adapters.yml for weave + flocker
powerstrip-base-install-powerstrip-config() {
  mkdir -p /etc/powerstrip-demo
  cat << EOF > /etc/powerstrip-demo/adapters.yml
version: 1
endpoints:
  "POST /*/containers/create":
    pre: [flocker,weave]
  "POST /*/containers/*/start":
    post: [weave]
adapters:
  flocker: http://flocker/flocker-adapter
  weave: http://weave/weave-adapter
EOF
}

#
#
# SUPERVISOR CONFIG
#
#

# write a supervisor service - servivename -> function in install.sh
powerstrip-base-install-write-service() {
  local service="$1";

  cat << EOF > /etc/supervisor/conf.d/$service.conf
[program:$service]
command=bash $SCRIPTPATH/install.sh $service
EOF
}

#
#
# SHUTDOWN
#
#

powerstrip-base-install-shutdown-service() {
  supervisorctl stop $1
  powerstrip-base-install-stop-container $1
}

powerstrip-base-install-shutdown() {
  powerstrip-base-install-shutdown-service powerstrip-weave
  powerstrip-base-install-stop-container weave
  powerstrip-base-install-stop-container weavewait
  powerstrip-base-install-shutdown-service powerstrip-flocker
  powerstrip-base-install-shutdown-service powerstrip
  powerstrip-base-install-shutdown-service flocker-zf-agent
  powerstrip-base-install-shutdown-service flocker-control
}

powerstrip-base-install-setup() {
  powerstrip-base-install-deps
  powerstrip-base-install-docker
  powerstrip-base-install-configure-docker
  powerstrip-base-install-sysconfig
  sleep 5
  echo "powerstrip base setup done"
}