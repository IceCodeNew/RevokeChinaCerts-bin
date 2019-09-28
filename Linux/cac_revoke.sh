#!/bin/sh

set -e

ed_conf() {
  local regex="$1"
  sed --in-place --regexp-extended "$regex" "$Config"
}

comment() {
  ed_conf "s%^$1%!\0%g"
}

uncomment() {
  ed_conf "s%^!($1)%\1%g"
}

readonly blacklisted_base_certs="mozilla/CNNIC_ROOT.crt
mozilla/China_Internet_Network_Information_Center_EV_Certificates_Root.crt"
readonly blacklisted_extended_certs="mozilla/CFCA_EV_ROOT.crt
mozilla/WoSign_China.crt
mozilla/GDCA_TrustAUTH_R5_ROOT.crt
mozilla/WoSign.crt
mozilla/CA_WoSign_ECC_Root.crt
mozilla/Certification_Authority_of_WoSign_G2.crt"
readonly blacklisted_all_certs="mozilla/Hongkong_Post_Root_CA_1.crt
mozilla/ePKI_Root_Certification_Authority.crt
mozilla/Taiwan_GRCA.crt
mozilla/TWCA_Root_Certification_Authority.crt
mozilla/TWCA_Global_Root_CA.crt"

readonly blacklisted_certs='../'

readonly blacklist_dir='/etc/ca-certificates/trust-source/blacklist' # arch
readonly local_cert='/usr/local/share/ca-certificates'
readonly hooks='/etc/ca-certificates/update.d'

Config=/etc/ca-certificates.conf
debug=

update_certs() {
  if [ ! -z "$debug" ]; then
    echo 'echo (fake) update-ca-certificates'
  else
    # In /etc/ca-certificates.conf, each line gives a pathname of a CA
    # certificate under /usr/share/ca-certificates  that should be trusted.
    # Lines that begin with "!" are deselected, causing the deactivation
    # of the CA certificate. If a CA certificate under /usr/share/ca-certificates
    # does not have a corresponding line in /etc/ca-certificates.conf,
    # then the CA certificate will be linked into /etc/ssl/certs/name.pem,
    # but will not be include in `/etc/ssl/certs/ca-certificates.crt`.
    # Thus an OpenSSL based application will still use it (unless this
    # application only checks for `/etc/ssl/certs/ca-certificates.crt`).
    # With the option `--fresh`, the CA certificate will not be linked.
        update-ca-certificates --fresh
  fi

  if [ -n "$(ls $hooks)" ]; then
    echo "Warn! We have found hooks in $hooks"
    echo "We recommend that you manually check them."
    echo
  fi
}

checksum_audit() {
  if [ -n "$(ls $local_cert)" ]; then
    local local_certsum_sorted="$(mktemp)"
    sha1 $(find $local_cert -type f -or -type l) | sort > $local_certsum_sorted
    if [ -n "$(join -j 2 $local_certsum_sorted certsum_$1_sorted.txt)" ]; then
      echo "Files under $local_cert will be implicitly trusted."
      echo "We have found questionable certificates there."
      echo "We recommend that you manually check which program installed them."
      echo
    fi
  fi
  local pemsum_sorted="$(mktemp)"
  sha1 /etc/ssl/certs/*.pem | sort > $pemsum_sorted
  if [ -n "$(join -j 2 $pemsum_sorted certsum_$1_sorted.txt)" ]; then
    echo 'Warn! Questionable certificates still exist on your system.'
    echo
    echo 'Please report a bug at:'
    echo 'https://github.com/chengr28/RevokeChinaCerts/issues'
    echo
    echo 'Please attach the following output:'
    echo
    join -j 2 $pemsum_sorted certsum_$1_sorted.txt
    echo
  fi
}

sha1() {
  for cert in "$@"; do
    echo $(openssl x509 -sha1 -in $cert -noout -fingerprint) $cert
  done
}

generate_cert_filenames() {
  cat certsum_$1_sorted.txt | cut -f 3
}

copy_blacklisted_certs() {
  for cert in $(generate_cert_filenames $1); do
    cp $blacklisted_certs/$cert $blacklist_dir
  done
}

revoke_arch() {
  copy_blacklisted_certs $1
  trust extract-compat
}

restore_arch() {
  for cert in $(generate_cert_filenames $1); do
    path="$blacklist_dir/$certs"
    if [ -f "$path" ]; then
      rm "$path"
    fi
  done
  trust extract-compat
}

revoke_base() {
  for cert in $blacklisted_base_certs; do
    comment $cert
  done
  update_certs
  checksum_audit 'base'
}

revoke_extended() {
  for cert in $blacklisted_base_certs $blacklisted_extended_certs; do
    comment $cert
  done
  update_certs
  checksum_audit 'extended'
}

revoke_all() {
  for cert in $blacklisted_base_certs $blacklisted_extended_certs $blacklisted_all_certs; do
    comment $cert
  done
  update_certs
  checksum_audit 'all'
}

restore() {
  for cert in $blacklisted_base_certs $blacklisted_extended_certs $blacklisted_all_certs; do
    uncomment $cert
  done
  update_certs
}

help() {
  echo 'Usage: [sudo] cac_revoke base|extended|all|restore'
}

main() {
  # Debug.
  if [ "$2" ]; then
    if [ "$2" = '--debug' ]; then
      debug='fixtures/ca-certificates.conf'
      Config=${debug:-'/etc/ca-certificates.conf'}
    else
      help
      exit 1
    fi
  fi

  # From 2014-12-11, Arch uses a different mechanism.
  if [ -f '/etc/arch-release' ]; then
    case $1 in
      base) revoke_arch base;;
      extended) revoke_arch extended;;
      all) revoke_arch all;;
      restore) restore_arch;;
      *) help; exit 1;;
    esac
  else
    case $1 in
      base) revoke_base;;
      extended) revoke_extended;;
      all) revoke_all;;
      restore) restore;;
      *) help; exit 1;;
    esac
  fi
}


main "$@"
