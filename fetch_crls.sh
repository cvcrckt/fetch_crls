#!/bin/bash

###########################################
# Manage CRLs for HAProxy whent it's configured for client X.509 authentication.
# Suitable to be run as a cron job.
###########################################
readonly base_dir="/opt/haproxy"
# $crl_dist_list is a file with CRL distribution points (HTTP), one per line:
readonly crl_dist_list="${base_dir}/etc/pki/client/crl/crl_dist_list"
readonly crl_dir="${base_dir}/etc/pki/client/crl"
readonly crls=${crl_dir}/crl.pem
readonly service_restart_command="/sbin/service haproxy restart"
readonly script_name=$(basename $0)
readonly debugging="true"
readonly log_file="${base_dir}/var/log/${script_name}.log"

function log() {
  if [[ $debugging == "true" ]]; then
    echo "$(date +'%b %d %T') $script_name: $1" >> $log_file
  fi
}

[[ $debugging == "true" ]] && exec 2>>$log_file

pushd . > /dev/null
cd $crl_dir
cat /dev/null > fresh_crls

for crl_url in $(cat $crl_dist_list); do
  crl_file=${crl_url##*/}
  [[ -s $crl_file ]] && {
    log "$crl_file exists and is > 0 bytes. I will only download another copy if it is newer."
    curl_if_newer_opt="-z $crl_file"
  }
  # Only download a CRL if it is newer than what we already have:
  curl --silent --show-error --retry 5 -o $crl_file $curl_if_newer_opt $crl_url
  openssl crl -inform der -in $crl_file -outform pem >> fresh_crls
done

new_crls_md5=$(md5sum fresh_crls | cut -d" " -f1)
existing_crls_md5=$(
  [[ -e $crls ]] && {
    md5sum $crls | cut -d" " -f1
  } || echo ""
)

log "fresh_crls MD5: $new_crls_md5"
log "$(basename $crls) MD5: $existing_crls_md5"
# If any CRLs have changed, move new consolidated list into place
# and restart the service that depends on them:
if [[ $new_crls_md5 != $existing_crls_md5 ]]; then
  log "Freshening $crls and running ${service_restart_command}"
  mv fresh_crls $crls
  $service_restart_command
else
  rm fresh_crls
fi

popd > /dev/null
