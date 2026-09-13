#!/bin/sh
set -eu

generated_config="/tmp/ledgerly-alertmanager.yml"
/bin/sh /etc/alertmanager/generate-config.sh "$generated_config"

exec /bin/alertmanager \
  --config.file="$generated_config" \
  --storage.path=/alertmanager \
  --web.listen-address=:9093 \
  --cluster.listen-address=
