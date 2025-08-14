#!/usr/bin/env bash
# controller-init.sh
# Initializes the KERI AID for the my-keystore controller to be used in the Docker version of the did:webs example scripts.
# This includes did:webs asset generation for the did.json and keri.cesr files.
# Note: this script requires witnesses to be running on the host "witnesses" at port 5642.
#
# This includes the following:
#   - set up the controller AID in the keystore
#   - create a designated aliases registry and credential
#   - generate the did:webs DID for the controller AID
#   - generate the did.json and keri.cesr files in the web directory

# env vars for the rest of the script
CONFIG_DIR="/dws/config"
SCRIPTS_DIR="/dws/scripts"
WEB_DIR="/dws/web"
ARTIFACT_PATH="dws"
source "${SCRIPTS_DIR}"/color-printing.sh

METADATA_TRUE=$1
print_yellow "METADATA_TRUE: ${METADATA_TRUE}"

CWD="${PWD##*/}"
if [ "${CWD}" != "dws" ]; then
    echo "This script must be run from the root dws directory. It was run from the directory: ${CWD}"
    exit 1
fi

# Binary Dependencies
command -v kli >/dev/null 2>&1 || { print_red "kli is not installed or not available on the PATH. Aborting."; exit 1; }
command -v dws >/dev/null 2>&1 || { print_red "dws is not installed or not available on the PATH. Aborting."; exit 1; }

# need to run witness network
DOMAIN=dws-static-service
DID_PORT=7679
print_dark_gray "Assumes witnesses started and running..."
WAN_PRE=BBilc4-L3tFUnfM_wJr4S4OJanAv_VmF_dJNN6vkf2Ha
WIT_HOST=http://witnesses:5642
WIT_OOBI="${WIT_HOST}/oobi/${WAN_PRE}"

function check_witnesses() {
  curl $WIT_OOBI >/dev/null 2>&1
  status=$?
  if [ $status -ne 0 ]; then
      print_red "Witness server not running at ${WIT_HOST}"
      exit 1
  else
      print_dark_gray "Witness server is running at ${WIT_OOBI}\n"
  fi
}
check_witnesses

# Set up identifying information for the controller AID and the did:webs DID
CTLR_KEYSTORE="my-keystore"
CTLR_ALIAS="my-controller"
DESG_ALIASES_REG="did:webs_designated_aliases"
DESG_ALIASES_SCHEMA="EN6Oh5XSD5_q2Hgu-aqpdfbVepdpYpFlgz6zvJL5b_r5"

# init environment for controller AID
print_dark_gray "Creating did:webs controller AID ${CTLR_ALIAS} in keystore ${CTLR_KEYSTORE} resolvable on domain ${DOMAIN}"
function create_aid() {
  # Create keystore, AID, verify witness accessibility, and resolve the designated aliases schema
  kli init \
    --name "${CTLR_KEYSTORE}" \
    --salt 0ADpd6pkFN7yAkINS1jJwr_X \
    --nopasscode \
    --config-dir "${CONFIG_DIR}/controller" \
    --config-file "${CTLR_KEYSTORE}"
  # inception for controller AID
  kli incept \
    --name "${CTLR_KEYSTORE}" \
    --alias "${CTLR_ALIAS}" \
    --file "${CONFIG_DIR}/controller/incept-with-wan-wit.json"

  # check witness oobi for our AID
  CTLR_OOBI="${WIT_HOST}/oobi/${CTLR_AID}/witness/${WAN_PRE}"
  curl "${CTLR_OOBI}" >/dev/null 2>&1
  status=$?
  if [ $status -ne 0 ]; then
      print_red "Controller ${CTLR_ALIAS} with AID ${CTLR_AID} not found at ${CTLR_OOBI}"
      exit 1
  else
      print_green "Controller ${CTLR_ALIAS} with AID ${CTLR_AID} setup complete."
  fi
}

function set_up_aid() {
  exists=$(kli aid --name "${CTLR_KEYSTORE}" --alias "${CTLR_ALIAS}" 2>/dev/null)
  if [[ "${exists}" =~ ^E  || ! "${exists}" =~ Keystore* ]] ; then
    print_dark_gray "${CTLR_ALIAS} already exists in ${CTLR_KEYSTORE}, reusing..."
  else
    print_dark_gray "does not exist, creating..."
    create_aid
    kli oobi resolve --name "${CTLR_KEYSTORE}" \
      --oobi-alias "schema-designated-alias-public" \
      --oobi "https://weboftrust.github.io/oobi/${DESG_ALIASES_SCHEMA}"
  fi
}
set_up_aid

CTLR_AID=$(kli aid --name "${CTLR_KEYSTORE}" --alias "${CTLR_ALIAS}")
DESIG_ALIASES_FILE="${SCRIPTS_DIR}/designated_aliases.json"

function create_designated_aliases_json() {
  timestamp=$(kli time | tr -d '[:space:]')
    read -r -d '' DESIG_ALIASES_JSON << EOM
{
  "d": "",
  "dt": "${timestamp}",
  "ids": [
    "did:web:${DOMAIN}%3a${DID_PORT}:${CTLR_AID}",
    "did:webs:${DOMAIN}%3a${DID_PORT}:${CTLR_AID}",
    "did:web:example.com:${CTLR_AID}",
    "did:web:foo.com:${CTLR_AID}",
    "did:webs:foo.com:${CTLR_AID}"
  ]
}
EOM
    print_lcyan "building designated aliases JSON: ${DESIG_ALIASES_FILE}"
    echo "$DESIG_ALIASES_JSON" > "${DESIG_ALIASES_FILE}"
    kli saidify --file "${DESIG_ALIASES_FILE}"
    ALIASES=$(< "${DESIG_ALIASES_FILE}" jq)
    print_lcyan "${ALIASES}"
}

function create_desg_aliases_registry() {
  kli vc registry incept \
    --name "${CTLR_KEYSTORE}" \
    --alias "${CTLR_ALIAS}" \
    --registry-name "${DESG_ALIASES_REG}"
  print_green "Created designated aliases registry ${CTLR_KEYSTORE}/${CTLR_ALIAS} with AID ${CTLR_AID}"
}

function create_desg_aliases_cred() {
  kli vc create \
    --name "${CTLR_KEYSTORE}" \
    --alias "${CTLR_ALIAS}" \
    --registry-name "${DESG_ALIASES_REG}" \
    --schema "${DESG_ALIASES_SCHEMA}" \
    --data @"${DESIG_ALIASES_FILE}" \
    --rules @"${SCRIPTS_DIR}/schema/rules/desig-aliases-public-schema-rules.json"
  print_green "Created designated aliases credential for ${CTLR_KEYSTORE}/${CTLR_ALIAS} with AID ${CTLR_AID}"
}

function prep_aliases(){
  REGISTRY=$(kli vc registry list --name "${CTLR_KEYSTORE}" | awk '{print $1}') # Get the first column which is the registry name
  if [ -n "${REGISTRY}" ]; then
      print_dark_gray "Designated Aliases attestation registry already created"
  else
    create_desg_aliases_registry
  fi
  # Add self-attested DIDs for the controller AID
  SAID=$(kli vc list --name "${CTLR_KEYSTORE}" --alias "${CTLR_ALIAS}" --issued --said \
        --schema "${DESG_ALIASES_SCHEMA}")
    if [ -n "${SAID}" ]; then
        print_dark_gray "Designated aliases credential already created"
    else
      create_designated_aliases_json
      create_desg_aliases_cred
    fi
}
prep_aliases

# View issued designated aliases VC
echo
kli vc list --name "${CTLR_KEYSTORE}" --alias "${CTLR_ALIAS}" --issued \
  --schema "${DESG_ALIASES_SCHEMA}"
echo

# generate controller did:webs for DOMAIN
# example: did:webs:127.0.0.1%3A7677:dws:EBFn5ge82EQwxp9eeje-UMEXF-v-3dlfbdVMX_PNjSft
MY_DID="did:webs:${DOMAIN}%3A${DID_PORT}:${ARTIFACT_PATH}:${CTLR_AID}"
print_yellow "Generating did:webs DID for ${CTLR_KEYSTORE} on ${DOMAIN} with AID ${CTLR_AID} in ${WEB_DIR}/${ARTIFACT_PATH}"
print_yellow "       of: ${MY_DID}"

if [[ "${METADATA_TRUE}" = true ]] ; then
  print_yellow "Using metadata for generation"
  dws did webs generate \
  --name "${CTLR_KEYSTORE}" \
  --output-dir "${WEB_DIR}/${ARTIFACT_PATH}" \
  --did "${MY_DID}" \
  --meta # include DID generation metadata as envelope of DID document in did.json
else
  print_yellow "Not using metadata for generation"
  dws did webs generate \
  --name "${CTLR_KEYSTORE}" \
  --output-dir "${WEB_DIR}/${ARTIFACT_PATH}" \
  --did "${MY_DID}"
fi

print_green "DID document generated at ${WEB_DIR}/${ARTIFACT_PATH}/did.json"
print_green "keri.cesr CESR stream generated at ${WEB_DIR}/${ARTIFACT_PATH}/keri.cesr"
