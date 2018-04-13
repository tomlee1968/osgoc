# == Class: hiera
#
# Creates Puppet resources based on Hiera data.  This Hiera data is assumed to
# exist in more than one Hiera data file and probably results from a deeper
# merge, so it cannot be read in from Puppet parameters; it requires Hiera.
#
# === Parameters
#
# Except where mentioned otherwise, these parameters are hashes/mappings; each
# record's key is just the title of the corresponding Puppet resource type, and
# the value is just another hash/mapping of the resource's attributes.  See the
# examples.
#
# hiera::augeas: Creates Augeas resources.
#
# hiera::certificate: Creates File resources for certificates and their private
# keys.  The key of each record is an ID string that isn't actually used
# anywhere outside of Puppet; it would help if it were descriptive, so perhaps
# you should set it to the CN of the certificate.  The value is just another
# hash that has keys 'cert' and 'key', and the values of those hashes are
# merely the attributes of the File resources for the files containing the
# certificate and key.  It's safe to use 'source' for the certificate.  For the
# key, you may want to use the 'content' attribute and hiera-eyaml, so the key
# can be encrypted within the Hiera YAML file.
#
# hiera::cron: Creates Cron resources.
#
# hiera::exec: Creates Exec resources.
#
# hiera::file: Creates File resources.  Note that you can't use templates in
# the 'content' attribute, as the Puppet 'create_resources' function doesn't
# evaluate function calls in Hiera data, including the 'template' function
# call.  Use hiera::template_file if you need to use a template.
#
# hiera::file_exclude: Excludes File resources from creation.
#
# hiera::template_file: Creates File resources, but consults the 'template'
# attribute and looks for a template with the given path.  After filling out
# the template, assigns the results to the new File resource's 'content'
# attribute.
#
# hiera::mailalias: Creates Mailalias resources.
#
# hiera::package: Creates Package resources.
#
# hiera::package_exclude: Requires an array; allows you to specify packages to
# exclude.  This way, you can exclude a package in a host-specific .yaml file
# that was included in global.yaml, for example.
#
# hiera::service: Creates Service resources.
#
# hiera::service_exclude: Requires an array; allows you to specify services to
# exclude.
#
# hiera::tidy: Requires an array; allows you to create tidy resources to remove
# files.
#
# hiera::var: Variables to be passed into the module, usually for use in file
# templates.
#
# === Variables
#
# Here you should define a list of variables that this module would require.
#
# This class references no global variables.
#
# === Examples
#
## hiera.yaml:
# :backends:
#   - eyaml
#   - yaml
# :hierarchy:
#   - defaults
#   - "clientcert/%{::clientcert}"
#   - "host/%{::hostname}"
#   - "osfamily/%{::osfamily}"
#   - globals
# :yaml:
#   :datadir: "/etc/puppet/env/%{::environment}/hiera"
# :eyaml:
#   :datadir: "/etc/puppet/env/%{::environment}/hiera"
#   :pkcs7_private_key: /etc/path/to/private_key.pkcs7.pem
#   :pkcs7_public_key: /etc/path/to/public_key.pkcs7.pem
#   :extension: 'yaml'
# :merge_behavior: deeper
#
## global.yaml:
# hiera::augeas:
#   logwatch_mailto:
#     context: /files/etc/logwatch/conf/logwatch.conf
#     changes:
#       - set MailTo 'sysadmin'
#
# hiera::certificate:
#   'help@opensciencegrid.org':
#     cert:
#       source: puppet:///modules/hiera/help_opensciencegrid.org-usercert.pem
#       path: /etc/grid-security/user/cert.pem
#       owner: root
#       group: root
#       mode: 0644
#       replace: true
#     key:
#       content: |
#         ENC[PKCS7,MIII...=]
#       path: /etc/grid-security/user/key.pem
#       owner: root
#       group: root
#       mode: 0640
#       replace: true
#
# hiera::exec:
#   newaliases:
#     command: newaliases
#     refreshonly: true
#
# hiera::file:
#   /etc/dnsmasq.conf:
#     source: puppet:///modules/hiera/dnsmasq.conf
#     ensure: present
#     replace: true
#     owner: root
#     group: root
#     mode: 0644
#     require:
#       - Package[dnsmasq]
#     notify:
#       - Service[dnsmasq]
#   /etc/sudoers.d:
#     ensure: directory
#     owner: root
#     group: root
#     mode: 0755
#
# hiera::template_file:
#   /etc/sudoers.d/goc:
#     template: hiera/sudoers_goc.erb
#     ensure: present
#     replace: true
#     owner: root
#     group: root
#     mode: 0440
#     require:
#       - File[/etc/sudoers.d]
#
# hiera::mailalias:
#   sysadmin:
#     ensure: present
#     recipient: thomlee@iu.edu
#     notify:
#       - Exec[newaliases]
#
# hiera::package:
#   dnsmasq:
#     ensure: present
#     before:
#       - Service[dnsmasq]
#
# hiera::service:
#   dnsmasq:
#     ensure: running
#     enable: true
#     hasrestart: true
#     hasstatus: true
#
# hiera::tidy:
#   cleanup_tmp_txt:
#     path: /tmp
#     matches:
#       - *.txt
#
# === Authors
#
# Thomas Lee <thomlee@iu.edu>
#
# === Copyright
#
# Copyright 2015 Thomas Lee for Indiana University

define cert_key_pair(
  $pairs = hiera_hash('hiera::certificate', {}),
) {
  $pair = $pairs["$title"]
  $cert = $pair['cert']
  $certpath = $cert['path']
  $key = $pair['key']
  $keypath = $key['path']
  create_resources('file', {
    "$certpath" => $cert,
    "$keypath" => $key,
    })
}

define template_file(
  $files = hiera_hash('hiera::template_file', {}),
  $var = hiera_hash('hiera::var', {}),
) {
  $file = $files[$title]
  if $file['template'] {
    $content = template($file['template'])
  } else {
    $content = ''
  }
  $new_file = delete($file, 'template')
  $new_file['content'] = $content
  create_resources('file', { "$title" => $new_file })
}

class hiera() {
  # variables
  $var = hiera_hash('hiera::var', {})
#  $var_keys_str = join(sort(keys($var)), ", ")
#  notify { "DEBUG: var keys = $var_keys_str": }
  # augeas resources
  $augeas_hash = hiera_hash('hiera::augeas', {})
  create_resources('augeas', $augeas_hash)
  # certificates (really just two related file resources)
  $pairs_hash = hiera_hash('hiera::certificate', {})
  $pairs_exclude_array = hiera_array('hiera::certificate_exclude', [])
  $pairs_final = delete($pairs_hash, $pairs_exclude_array)
  $pairs_keys = keys($pairs_final)
  cert_key_pair { $pairs_keys:
    pairs => $pairs_final,
  }
  # cron resources
  $cron_hash = hiera_hash('hiera::cron', {})
  create_resources('cron', $cron_hash)
  # exec resources
  $exec_hash = hiera_hash('hiera::exec', {})
  create_resources('exec', $exec_hash)
  # file resources
  $file_hash = hiera_hash('hiera::file', {})
  $file_exclude_array = hiera_array('hiera::file_exclude', [])
  $file_final = delete($file_hash, $file_exclude_array)
  create_resources('file', $file_final)
  # file resources with template, because create_resources doesn't resolve
  # template() function calls (or any function calls, for that matter)
  $template_file_hash = hiera_hash('hiera::template_file', {})
  $template_final = delete($template_file_hash, $file_exclude_array)
  $template_final_keys = keys($template_final)
  template_file { $template_final_keys:
    files => $template_final,
    var => $var,
  }
  # group resources
  $group_hash = hiera_hash('hiera::group', {})
  create_resources('group', $group_hash)
  # mailalias resources
  $mailalias_hash = hiera_hash('hiera::mailalias', {})
  $mailalias_exclude_array = hiera_array('hiera::mailalias_exclude', [])
  $mailalias_final = delete($mailalias_hash, $mailalias_exclude_array)
  create_resources('mailalias', $mailalias_final)
  # package resources
  $package_hash = hiera_hash('hiera::package', {})
  $package_exclude_array = hiera_array('hiera::package_exclude', [])
#  $package_ex_str = join(sort($package_exclude_array), ", ")
#  notify { "DEBUG: my service = $::goc_service": }
#  notify { "DEBUG: packages to exclude = $package_ex_str": }
  $package_final = delete($package_hash, $package_exclude_array)
#  $package_str = join(sort(keys($package_final)), ", ")
#  notify { "DEBUG: packages = $package_str": }
  create_resources('package', $package_final)
  # service resources
  $service_hash = hiera_hash('hiera::service', {})
  $service_exclude_array = hiera_array('hiera::service_exclude', {})
  create_resources('service', delete($service_hash, $service_exclude_array))
  # tidy resources
  $tidy_hash = hiera_hash('hiera::tidy', {})
  create_resources('tidy', $tidy_hash)
  # user resources
  $user_hash = hiera_hash('hiera::user', {})
  create_resources('user', $user_hash)
}
