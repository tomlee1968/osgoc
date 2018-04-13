# == Class: ssh_userkeys
#
# Allows you to define SSH public user keys that should be synched to various
# servers using Hiera or class parameters.
#
# === Parameters
#
# $ssh_userkeys::keys: A hash of hashes; the key for each record is the SSH
# key's ID string, and the value is a hash.  The keys of that hash are the
# following:
#   * type: The type of the key ('ssh-rsa', 'ssh-dsa', etc.)
#   * key: The key itself, in base-64 format
#   * ensure (optional): 'present' or 'absent' ('present' is the default);
# tells Puppet whether to add the key or delete it
#
# Note that a key listed in $ssh_userkeys::keys will have no effect unless
# referenced in the 'keys' array in a user's hash in $ssh_userkeys::users (see
# below).
#
# $ssh_userkeys::users: A hash of hashes; the key for each record is the Unix
# username of the user in question, and the value is a hash.  The keys of that
# hash are the following:
#   * home: The user's home directory.  If a user's home directory doesn't
# exist, it will be created.
#   * group: The group the user's home directory should be owned by.  Default
# is 'goc'.
#   * keys: An array consisting of the ID strings of that user's SSH keys.
# Each ID string should be defined in $ssh_userkeys::keys, or there will be an
# error.
#
# $ssh_userkeys::users_exclude: An array of Unix usernames of users to exclude.
# This is most useful in the case where a number of users are defined globally
# but you want to exclude one or more of them on one host, or one group of
# hosts.  Note that putting a username in this array will not result in their
# key(s) being deleted; it will only result in the user's key(s) being removed
# from Puppet control -- keys that don't exist will continue not existing,
# while keys that exist will stay where they are.  To remove a key, change its
# 'ensure' value to 'absent'.
#
# === Variables
#
# There are no dependencies on global variables.
#
# === Examples
#
# ssh_userkeys::keys:
#   example.user@example.com:
#     type: ssh-rsa
#     key: AAA...<key here>...==
#
# ssh_userkeys::users:
#   example.user:
#     home: /home/example.user
#     keys:
#       - example.user@example.com
#
# === Authors
#
# Tom Lee <thomlee@iu.edu>, though partly based on sidorenko-sshkeys by Artem
# Sidorenko, to whom I give credit for showing me the way
#
# === Copyright
#
# Copyright 2015 Your name here, unless otherwise noted.

define homedir(
  $path = undef,
  $group = 'goc',               # Site-specific -- I don't like this
) {
  # Makes sure the given user's home directory exists (if it isn't
  # /home/$title, use the 'path' parameter to set it explicitly).  If the
  # directory is defined elsewhere, this doesn't cause an error; it just does
  # nothing.  Whether the directory exists or not, any files in /etc/skel that
  # aren't already in the directory are copied there, but any files that
  # already exist in it won't be touched.
  if $path {
    $dir = $path
  } else {
    $dir = "/home/$title"
  }
  unless defined(File[$dir]) {
    file {$dir:
      ensure => 'directory',
      owner => $title,
      group => $group,
      recurse => 'remote',
      replace => 'no',
      source => '/etc/skel',
    }
  }
}

define ssh_key(
  # $title will be "username::separator::keyname"
  $user = undef,
  $home = undef,
  $keys_hash = hiera_hash('ssh_userkeys::keys', {}),
) {
  unless $user {
    fail('The user must be defined')
  }
  $split = split($title, '::separator::')
  $kludge = $split[0]
  $keyname = $split[1]
  unless $keys_hash and $keys_hash[$keyname] and $keys_hash[$keyname]['key'] and $keys_hash[$keyname]['type'] {
    fail("Cannot find key '$keyname'")
  }
  if $keys_hash[$keyname]['ensure'] == 'absent' {
    $ensure = 'absent'
  } else {
    $ensure = 'present'
  }
  if $home {
    $home_final = $home
  } else {
    $home_final = "/home/$user"
  }
  if $kludge {
    $id = sprintf('%s::%s', $kludge, $keyname)
  } else {
    $id = $keyname
  }
  ssh_authorized_key { $id:
    ensure => $ensure,
    key => $keys_hash[$keyname]['key'],
    type => $keys_hash[$keyname]['type'],
    options => $keys_hash[$keyname]['options'],
    user => $user,
    require => [
                File['/tmp'],
                File[$home_final],
                ],
  }
}

define ssh_user(
  # $title will be each username.
  $users_hash = hiera_hash('ssh_userkeys::users', {}),
  $keys_hash = hiera_hash('ssh_userkeys::keys', {}),
) {
  unless $users_hash[$title] {
    fail('Cannot find the user')
  }
  homedir {$title:
    path => $users_hash[$title]['home'],
    group => $users_hash[$title]['group'],
  }
  # This produces an array of the key names for the given user ($title),
  # prefixed with the user; that is, if ssh_userkeys::keys defined keys "foo",
  # "bar", and "baz", and ssh_userkeys::users defined "foo" and "bar" for user
  # "theuser", then $prefixed_keys would contain ["theuser::foo",
  # "theuser::bar"].
  $prefixed_keys = prefix($users_hash[$title]['keys'], sprintf("%s::separator::", $users_hash[$title]['kludge']))
  # In this iteration, we're calling ssh_key for each value of $prefixed_keys.
  ssh_key {$prefixed_keys:
    user => $title,
    home => $users_hash[$title]['home'],
    keys_hash => $keys_hash,
  }
}

class ssh_userkeys {
  unless defined(File['/tmp']) {
    file {'/tmp':
      ensure => 'directory',
      mode => '1777',
      owner => 'root',
      group => 'root',
    }
  }
  $keys_hash = hiera_hash('ssh_userkeys::keys', {})
  $users_hash = hiera_hash('ssh_userkeys::users', {})
  $users = keys($users_hash)
  $users_exclude = hiera_array('ssh_userkeys::users_exclude', [])
  $users_final = delete($users, $users_exclude)
  # In this old-style iteration, needed because we don't have Puppet 4.x yet,
  # we're calling a resource with an array in its title, resulting in this case
  # in calling the ssh_user define with each member of $users_final as a
  # $title.
  ssh_user { $users_final:
    users_hash => $users_hash,
    keys_hash => $keys_hash,
  }
}
