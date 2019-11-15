#!/usr/bin/env bash

set -euo pipefail

apk add --no-cache -U git bash openssh
source $(dirname $0)/../lib.sh
cd $(dirname $0)/../../..
git fetch --tags

# we only synchronize charts for tags
if ! git tag -l | grep -q "^$PULL_BASE_REF\$"; then
  echo "Base ref $PULL_BASE_REF is not a tag! Exitting..."
  exit 1
fi

# find out which kubermatic-installer branch to synchronize to
if grep -qE '^v[0-9]+\.[0-9]+\.[0-9]+.*' <<< "$PULL_BASE_REF"; then
  # e.g. 'release/v2.12'
  INSTALLER_BRANCH="release/$(grep -o -E '^v[0-9]+\.[0-9]+' <<< "$PULL_BASE_REF")"
elif grep -E '^weekly-[0-9]{4}-.*' <<< "$PULL_BASE_REF"; then
  INSTALLER_BRANCH="weekly"
else
  echo "I don't know to which installer branch the tag '$PULL_BASE_REF' belongs to. Exitting..."
  exit 1
fi

# The dashboard tag should match the Kubermatic tag
sed -i "s/__KUBERMATIC_TAG__/$PULL_BASE_REF/g" config/*/*.yaml
sed -i "s/__DASHBOARD_TAG__/$PULL_BASE_REF/g" config/*/*.yaml

git config --global user.email "dev@loodse.com"
git config --global user.name "Prow CI Robot"
git config --global core.sshCommand 'ssh -o CheckHostIP=no -i /ssh/id_rsa'
ensure_github_host_pubkey

export CHARTS='kubermatic cert-manager certs nginx-ingress-controller nodeport-proxy oauth minio iap s3-exporter'
export MONITORING_CHARTS='alertmanager blackbox-exporter grafana kube-state-metrics node-exporter prometheus'
export LOGGING_CHARTS='elasticsearch kibana fluentbit'
export BACKUP_CHARTS='velero'
export CHARTS_DIR=$(pwd)/config
export TARGET_DIR='sync_target'
export TARGET_VALUES_FILE=${TARGET_DIR}/values.example.yaml
export TARGET_VALUES_SEED_FILE=${TARGET_DIR}/values.seed.example.yaml
COMMIT=${3:-}

if [ ! -z "${COMMIT}" ]; then
  COMMIT="local folder"
fi

# create fresh clone of the installer repository
rm -rf ${TARGET_DIR}
mkdir ${TARGET_DIR}
git clone git@github.com:kubermatic/kubermatic-installer.git ${TARGET_DIR}
cd ${TARGET_DIR}
git checkout ${INSTALLER_BRANCH} || git checkout -b ${INSTALLER_BRANCH}
cd ..

# re-assemble example values.yaml
rm -f ${TARGET_DIR}/values.yaml

for VALUE_FILE in ${TARGET_VALUES_FILE} ${TARGET_VALUES_SEED_FILE}; do
  rm -f ${VALUE_FILE}
  echo "# THIS FILE IS GENERATED BY https://github.com/kubermatic/kubermatic/blob/master/api/hack/ci/ci-sync-charts.sh" > ${VALUE_FILE}
done

cat "${CHARTS_DIR}/kubermatic/values.yaml" >> ${TARGET_VALUES_SEED_FILE}

# ensure that charts we don't know yet (from a future version)
# also get cleaned up
rm -rf ${TARGET_DIR}/charts
mkdir ${TARGET_DIR}/charts

# sync base charts
for CHART in ${CHARTS}; do
  echo "syncing ${CHART}..."
  cp -r ${CHARTS_DIR}/${CHART} ${TARGET_DIR}/charts/${CHART}

  echo "# ====== ${CHART} ======" >> ${TARGET_VALUES_FILE}
  cat "${CHARTS_DIR}/${CHART}/values.yaml" >> ${TARGET_VALUES_FILE}
  echo "" >> ${TARGET_VALUES_FILE}
done

# sync monitoring charts
echo "" >> ${TARGET_VALUES_FILE}
echo "# ========================" >> ${TARGET_VALUES_FILE}
echo "# ====== Monitoring ======" >> ${TARGET_VALUES_FILE}
echo "# ========================" >> ${TARGET_VALUES_FILE}
echo "" >> ${TARGET_VALUES_FILE}
mkdir -p "${TARGET_DIR}/charts/monitoring"
for CHART in ${MONITORING_CHARTS}; do
  echo "syncing ${CHART}..."
  cp -r ${CHARTS_DIR}/monitoring/${CHART} ${TARGET_DIR}/charts/monitoring/${CHART}

  echo "# ====== ${CHART} ======" >> ${TARGET_VALUES_FILE}
  cat "${CHARTS_DIR}/monitoring/${CHART}/values.yaml" >> ${TARGET_VALUES_FILE}
  echo "" >> ${TARGET_VALUES_FILE}
done

# sync logging charts
echo "" >> ${TARGET_VALUES_FILE}
echo "# =======================" >> ${TARGET_VALUES_FILE}
echo "# ======= Logging =======" >> ${TARGET_VALUES_FILE}
echo "# =======================" >> ${TARGET_VALUES_FILE}
echo "" >> ${TARGET_VALUES_FILE}
mkdir -p "${TARGET_DIR}/charts/logging"
for CHART in ${LOGGING_CHARTS}; do
  echo "syncing ${CHART}..."
  cp -r ${CHARTS_DIR}/logging/${CHART} ${TARGET_DIR}/charts/logging/${CHART}

  echo "# ====== ${CHART} ======" >> ${TARGET_VALUES_FILE}
  cat "${CHARTS_DIR}/logging/${CHART}/values.yaml" >> ${TARGET_VALUES_FILE}
  echo "" >> ${TARGET_VALUES_FILE}
done

# sync backup charts
echo "" >> ${TARGET_VALUES_FILE}
echo "# =======================" >> ${TARGET_VALUES_FILE}
echo "# ======= Backups =======" >> ${TARGET_VALUES_FILE}
echo "# =======================" >> ${TARGET_VALUES_FILE}
echo "" >> ${TARGET_VALUES_FILE}
mkdir -p "${TARGET_DIR}/charts/backup"
for CHART in ${BACKUP_CHARTS}; do
  echo "syncing ${CHART}..."
  cp -r ${CHARTS_DIR}/backup/${CHART} ${TARGET_DIR}/charts/backup/${CHART}

  echo "# ====== ${CHART} ======" >> ${TARGET_VALUES_FILE}
  cat "${CHARTS_DIR}/backup/${CHART}/values.yaml" >> ${TARGET_VALUES_FILE}
  echo "" >> ${TARGET_VALUES_FILE}
done

# merge duplicate top-level keys
KNOWN_KEYS=()

while IFS= read LINE; do
  MATCH=$(echo "${LINE}" | grep -oE "^[a-zA-Z0-9]+" || true)

  if [ -z "${MATCH}" ]; then
    echo "${LINE}"
  else
    if ! [[ " ${KNOWN_KEYS[@]} " =~ " ${MATCH} " ]]; then
      KNOWN_KEYS+=("${MATCH}")
      echo "${LINE}"
    fi
  fi
done < ${TARGET_VALUES_FILE} > ${TARGET_DIR}/values.example.tmp.yaml

mv ${TARGET_DIR}/values.example.{tmp.,}yaml

# commit and push
cd ${TARGET_DIR}
git add .
if ! git status|grep 'nothing to commit'; then
  git commit -m "Syncing charts from release ${PULL_BASE_REF}"
  # $PULL_BASE_REF must be a tag, but we've verified it earlier
  git tag $PULL_BASE_REF
  git push --tags origin ${INSTALLER_BRANCH}
fi

cd ..
rm -rf ${TARGET_DIR}
