# powerstrip-base-install

Install powerstrip, powerstrip-flocker and powerstrip-weave etc on Ubuntu.

It uses supervisord to manage the various docker containers.

IMPORTANT: this repo assumes that [flocker zfs has been installed](https://github.com/binocarlos/flocker-base-install)

## usage

There are 2 options:

 * source lib.sh and call functions manually
 * use the install.sh controller

## config

In order to configure the nodes - the following files are used:

 * /etc/flocker/my_address - the address of the node itself
 * /etc/flocker/master_address - the address of the flocker control server
 * /etc/flocker/peer_address - the address of the weave peer to connect to

## install.sh

All nodes will want to run:

```bash
$ install.sh setup
```

This will:

 * install deps
 * configure docker

## write services

To enable the various services - we use supervisord.