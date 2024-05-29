#!/usr/bin/env bash

# ++-----------------+
# || Variables       |
# ++-----------------+

export STEP_ASSETS="${SCENARIO_OUTPUT_FOLDER}conf/"

# ++-----------------+
# || Begin           |
# ++-----------------+

header2 "Remove un-necessary configuration"

## For this scenario we need a hashicups-api node that has no Consul configuration
## and no Consul agent running

NODES_NAMES=( "hashicups-db-0" "hashicups-db-1" )

for node in "${NODES_NAMES[@]}"; do

  NODE_NAME="${node}"

  log "Remove configuration for ${NODE_NAME}"

  _agent_token=`cat ${STEP_ASSETS}secrets/acl-token-bootstrap.json | jq -r ".SecretID"`

  remote_exec ${NODE_NAME} "killall consul"
  remote_exec ${NODE_NAME} "rm -rf /etc/consul.d/*"
  remote_exec ${NODE_NAME} "rm -rf /opt/consul/*"

  consul force-leave -prune ${NODE_NAME}

  ## Remove local configuration

  # rm -rf ${STEP_ASSETS}/conf/${NODE_NAME}

  _remove_token=`cat ${STEP_ASSETS}secrets/acl-token-node-${NODE_NAME}.json | jq -r ".AccessorID"`

  consul acl token delete -id=${_remove_token}

  rm -rf ${STEP_ASSETS}secrets/acl-token-node-${NODE_NAME}.json
  rm -rf ${STEP_ASSETS}/${NODE_NAME}/agent-acl-tokens.hcl

  ## [ux-diff] [cloud provider] UX differs across different Cloud providers
  if [ "${SCENARIO_CLOUD_PROVIDER}" == "docker" ]; then

    log_debug "DNS left unaltered."

  elif [ "${SCENARIO_CLOUD_PROVIDER}" == "aws" ]; then

    log_debug "Cleaning DNS_config."

    DNS_CHANGE_COMMAND="sudo systemctl stop systemd-resolved && \
    sudo rm -f /etc/resolv.conf && \
    sudo mv /tmp/resolv.conf.old /etc/resolv.conf"

    remote_exec -o ${NODE_NAME} "${DNS_CHANGE_COMMAND}"

    elif [ "${SCENARIO_CLOUD_PROVIDER}" == "azure" ]; then
    ## [ ] [test] check if still works in azure

    log_debug "Cleaning DNS_config."

    DNS_CHANGE_COMMAND="sudo systemctl stop systemd-resolved && \
    sudo rm -f /etc/resolv.conf && \
    sudo mv /tmp/resolv.conf.old /etc/resolv.conf"

    remote_exec -o ${NODE_NAME} "${DNS_CHANGE_COMMAND}"


  else 
    log_err "Cloud provider $SCENARIO_CLOUD_PROVIDER is unsupported...exiting."
    exit 245
  fi

done