#!/usr/bin/env bash

set -euo pipefail

team_id="${1:-5WZ4CQNT6A}"
bundle_id="${2:-com.bi8syn.fmoassistant}"
downloads_dir="${3:-${HOME}/Downloads}"
timestamp="$(date '+%Y%m%d-%H%M%S')"
output_dir="${downloads_dir}/FMO-Assistant-ICP-Signing-${timestamp}"
temporary_dir="$(mktemp -d /tmp/fmoc-icp-signing.XXXXXX)"

cleanup() {
    find "${temporary_dir}" -type f -delete
    rmdir "${temporary_dir}"
}
trap cleanup EXIT

mkdir -p "${output_dir}"

security find-certificate -a -c "Apple Distribution" -p | awk -v directory="${temporary_dir}" '
    /-----BEGIN CERTIFICATE-----/ {
        certificate_index++
        certificate_file = sprintf("%s/certificate-%03d.pem", directory, certificate_index)
    }
    certificate_index > 0 {
        print > certificate_file
    }
'

valid_identities="$(security find-identity -v -p codesigning)"
selected_certificate=""
selected_expiration_epoch=0

for certificate in "${temporary_dir}"/certificate-*.pem; do
    [[ -f "${certificate}" ]] || continue

    subject="$(openssl x509 -in "${certificate}" -noout -subject)"
    [[ "${subject}" == *"UID=${team_id}"* ]] || continue
    openssl x509 -in "${certificate}" -checkend 0 -noout >/dev/null || continue

    fingerprint="$(openssl x509 -in "${certificate}" -noout -fingerprint -sha1 | cut -d= -f2 | tr -d ':')"
    [[ "${valid_identities}" == *"${fingerprint}"* ]] || continue

    expiration="$(openssl x509 -in "${certificate}" -noout -enddate | cut -d= -f2-)"
    expiration_epoch="$(date -j -f '%b %e %T %Y %Z' "${expiration}" '+%s')"

    if (( expiration_epoch > selected_expiration_epoch )); then
        selected_certificate="${certificate}"
        selected_expiration_epoch="${expiration_epoch}"
    fi
done

if [[ -z "${selected_certificate}" ]]; then
    printf '未找到 Team %s 下同时有效且包含本机私钥的 Apple Distribution 证书。\n' "${team_id}" >&2
    exit 1
fi

certificate_path="${output_dir}/apple-distribution-certificate.cer"
public_key_pem_path="${output_dir}/platform-public-key.pem"
public_key_hex_path="${output_dir}/platform-public-key-hex.txt"
sha1_path="${output_dir}/certificate-sha1.txt"
summary_path="${output_dir}/signing-info.txt"

openssl x509 -in "${selected_certificate}" -outform DER -out "${certificate_path}"
openssl x509 -in "${selected_certificate}" -pubkey -noout -out "${public_key_pem_path}"
openssl x509 -in "${selected_certificate}" -pubkey -noout \
    | openssl rsa -pubin -RSAPublicKey_out -outform DER 2>/dev/null \
    | xxd -p -c 10000 \
    | tr '[:lower:]' '[:upper:]' \
    > "${public_key_hex_path}"
openssl x509 -in "${selected_certificate}" -noout -fingerprint -sha1 \
    | cut -d= -f2 \
    | tr -d ':' \
    > "${sha1_path}"

{
    printf 'Bundle ID: %s\n' "${bundle_id}"
    printf 'Team ID: %s\n' "${team_id}"
    openssl x509 -in "${selected_certificate}" -noout -subject -serial -dates -fingerprint -sha1
    printf '\n备案填写文件：\n'
    printf '平台公钥（连续十六进制）：%s\n' "$(basename "${public_key_hex_path}")"
    printf '证书 SHA-1（无冒号）：%s\n' "$(basename "${sha1_path}")"
    printf '\n核验命令：\n'
    printf "openssl x509 -inform DER -in '%s' -noout -subject -serial -dates -fingerprint -sha1\n" "$(basename "${certificate_path}")"
} > "${summary_path}"

printf '%s\n' "${output_dir}"
