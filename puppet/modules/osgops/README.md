# osgops

#### Table of Contents

1. [Overview](#overview)
2. [Module Description - What the module does and why it is useful](#module-description)
3. [Setup - The basics of getting started with osgops](#setup)
    * [What osgops affects](#what-osgops-affects)
    * [Setup requirements](#setup-requirements)
    * [Beginning with osgops](#beginning-with-osgops)
4. [Usage - Configuration options and additional functionality](#usage)
5. [Reference - An under-the-hood peek at what the module is doing and how](#reference)
5. [Limitations - OS compatibility, etc.](#limitations)
6. [Development - Guide for contributing to the module](#development)

## Overview

This module contains all site-specific Puppet rules for the OSG Operations
Center.  Anything not site-specific has been moved elsewhere.

## Module Description

Currently the only thing this module does is add some OSG Operations-specific
custom facts:

'goc_accesshost': The 'accesshost' value for use in LDAP group names such as
shell-X and sudo-X.  For example, you can require membership in the LDAP group
'shell-$goc_accesshost' in order to login or the group 'sudo-$goc_accesshost'
to sudo, and on repo1 these would become 'shell-repo' and 'sudo-repo',
respectively.

'is_goc_vmhost': 'true' if we can determine that 'libvirtd' is running and
'false' otherwise.  This is so we can have rules that are contingent on whether
the machine is a VM host or not.  If we add more types of VM host, we would
obviously need to change this code.

'goc_service': A label defining the name of the running service, so you can
write rules that affect all instances of a given service.  For example, this
would be 'repo' on hosts 'repo1', 'repo2', and 'repo-itb'.

'goc_intf_pub': The name of the network interface attached to the public
subnet.

'goc_intf_priv': The name of the network interface attached to the private
subnet.

'goc_ipv4_pub': The machine's public IPv4 address.

'goc_ipv6_pub': The machine's public IPv6 address.

'goc_ipv4_priv': The machine's private IPv4 address.

'goc_ipv6_priv': The machine's private IPv6 address.

## Setup

### What osgops affects

* Adds various facts to Facter.

### Setup Requirements **OPTIONAL**


### Beginning with osgops

Lets you refer to $is_goc_vmhost in Puppet rules and Hiera files.

## Usage

Simply use the $is_goc_vmhost variable.

## Reference


## Limitations


## Development


## Release Notes/Contributors/Etc **Optional**
