#!/usr/bin/env bash

# ++-----------------+
# || Variables       |
# ++-----------------+

export STEP_ASSETS="${SCENARIO_OUTPUT_FOLDER}conf/"

# ++-----------------+
# || Begin           |
# ++-----------------+

header2 "Restart downstream services for hashicups-db"

NODES_ARRAY=( "hashicups-api" )

for node in "${NODES_ARRAY[@]}"; do

  ## Checking the number of configured instances for the scenario.
  NUM="${node/-/_}""_NUMBER"

  if [ "${!NUM}" -gt 0 ]; then
    
    header3 "Regenerate config for ${node} service"
    
    log "Found ${!NUM} instances of ${node}"

    ## [ux-diff] [cloud provider] UX differs across different Cloud providers
    if [ "${SCENARIO_CLOUD_PROVIDER}" == "docker" ]; then

      ## Gernerate hashicups-api configuration
      _DB_IP=`dig hashicups-db-0 +short`

    elif [ "${SCENARIO_CLOUD_PROVIDER}" == "aws" ]; then

      ## Gernerate hashicups-api configuration
      _DB_IP=`getent hosts hashicups-db-0 | awk '{print $1}'`
    
    elif [ "${SCENARIO_CLOUD_PROVIDER}" == "azure" ]; then
    ## [ ] [test] check if still works in Azure
    
      ## Gernerate hashicups-api configuration
      _DB_IP=`getent hosts hashicups-db-0 | awk '{print $1}'`

    else 
      log_err "Cloud provider $SCENARIO_CLOUD_PROVIDER is unsupported...exiting."
      exit 245
    fi

    for i in `seq ${!NUM}`; do

      export NODE_NAME="${node}-$((i-1))"

          ## Product API
    tee ${STEP_ASSETS}${NODE_NAME}/conf.json > /dev/null << EOF
{
  "db_connection": "host=${_DB_IP} port=5432 user=hashicups password=hashicups_pwd dbname=products sslmode=disable",
  "bind_address": ":9090",
  "metrics_address": ":9103"
}
EOF

      remote_copy "${NODE_NAME}" "${STEP_ASSETS}${NODE_NAME}/conf.json" "/home/${_USER}/conf.json"

    done

  else
    log_warn "No instance found for ${node}. Leaving unconfigured."
  fi

done


NODES_ARRAY=( "hashicups-api" "hashicups-nginx" )

for node in "${NODES_ARRAY[@]}"; do

  ## Checking the number of configured instances for the scenario.
  NUM="${node/-/_}""_NUMBER"

  if [ "${!NUM}" -gt 0 ]; then
    
    header3 "Starting ${node} service"
    
    log "Found ${!NUM} instances of ${node}"

    for i in `seq ${!NUM}`; do

      export NODE_NAME="${node}-$((i-1))"

      _OUTPUT=`remote_exec ${NODE_NAME} "bash ~/start_service.sh reload 2>&1"`
      _STAT="$?"

      if [ "${_STAT}" -ne 0 ];  then
        log_warn "Service ${node} on ${NODE_NAME} failed to start."
      fi

    done

  else
    log_warn "No instance found for ${node}. Leaving unconfigured."
  fi

done



