#!/usr/bin/env bash

# ++-----------------+
# || Functions       |
# ++-----------------+

# ++-----------------+
# || Variables       |
# ++-----------------+

username=${username:-$(whoami)}

export STEP_ASSETS="${SCENARIO_OUTPUT_FOLDER}conf/"

export MD_RUNBOOK_FILE=/home/${username}/solve_runbook.md

# ++-----------------+
# || Begin           |
# ++-----------------+

header1 "Introduce external service in your datacenter with Consul ESM"

# H1 ===========================================================================
md_log "
# Introduce external service in your datacenter with Consul ESM"
# ==============================================================================

md_log "
This is a solution runbook for the scenario deployed.
"

##  H2 -------------------------------------------------------------------------
md_log "
## Prerequisites"
# ------------------------------------------------------------------------------

md_log "
Login to the Bastion Host"

## [ux-diff] [cloud provider] UX differs across different Cloud providers 
if [ "${SCENARIO_CLOUD_PROVIDER}" == "docker" ]; then

  md_log_cmd 'ssh -i images/base/certs/id_rsa '${username}'@localhost -p 2222`
#...
'${username}'@bastion:~$'

elif [ "${SCENARIO_CLOUD_PROVIDER}" == "aws" ]; then
  
  md_log_cmd 'ssh -i certs/id_rsa.pem '${username}'@`terraform output -raw ip_bastion`
#...
'${username}'@bastion:~$'

elif [ "${SCENARIO_CLOUD_PROVIDER}" == "azure" ]; then
  
  md_log_cmd 'ssh -i certs/id_rsa.pem '${username}'@`terraform output -raw ip_bastion`
#...
'${username}'@bastion:~$'

else

  log_err "Cloud provider $SCENARIO_CLOUD_PROVIDER is unsupported...exiting."

  exit 245
fi

### H3 .........................................................................
md_log "
### Configure CLI to interact with Consul" 
# ..............................................................................

md_log "
Configure your bastion host to communicate with your Consul environment using the two dynamically generated environment variable files."

_RUN_CMD 'source "'${ASSETS}'scenario/env-scenario.env" && \
  source "'${ASSETS}'scenario/env-consul.env"'

_STAT="$?"

if [ "${_STAT}" -ne 0 ];  then
  log_err "Error reading variables"
  exit 254
fi

## Running the source command locally for variable visibility reasons
source "${ASSETS}scenario/env-scenario.env" && \
source "${ASSETS}scenario/env-consul.env"

md_log "
After loading the needed variables, verify you can connect to your Consul 
datacenter."

_RUN_CMD 'consul members'    

_STAT="$?"

if [ "${_STAT}" -ne 0 ];  then
  log_err "Error connecting to Consul."
  exit 254
fi

### H3 .........................................................................
md_log "
### Verify downstream service configuration" 
# ..............................................................................

md_log "
The \`hashicups-db\` service instances are not part of Consul catalog. 
This means the upstream services that need to connect to them need to use their IP address."

_CONNECT_TO hashicups-api-0

# remote_exec hashicups-api-0 "cat ~/conf.json"

_RUN_CMD -r hashicups-api-0 -o json "cat ~/conf.json"

_EXIT_FROM hashicups-api-0


##  H2 -------------------------------------------------------------------------
md_log "
## Register external services"
# ------------------------------------------------------------------------------

md_log "
Crete the folder that will contain the external service definition."

_RUN_CMD 'mkdir -p ~/assets/scenario/conf/external-services'

md_log "
Crete the configuration for \`hashicups-db-0\` node with relative service and health checks."

_RUN_CMD 'tee ~/assets/scenario/conf/external-services/hashicups-db-0.json > /dev/null << EOF
{
  "Datacenter": "$CONSUL_DATACENTER",
  "Node": "hashicups-db-0-ext",
  "ID": "`cat /proc/sys/kernel/random/uuid`",
  "Address": "`dig hashicups-db-0 +short`",
  "NodeMeta": {
    "external-node": "true",
    "external-probe": "true"
  },
  "Service": {
    "ID": "hashicups-db-0",
    "Service": "hashicups-db",
    "Tags": [
      "external",
      "inst_0"
    ],
    "Address": "`dig hashicups-db-0 +short`",
    "Port": 5432
  },
  "Checks": [{
    "CheckID": "hashicups-db-0-check",
    "Name": "hashicups-db check",
    "Status": "passing",
    "ServiceID": "hashicups-db-0",
    "Definition": {
      "TCP": "`dig hashicups-db-0 +short`:5432",
      "Interval": "5s",
      "Timeout": "1s",
      "DeregisterCriticalServiceAfter": "30s"
     }
  }]
}
EOF
'

md_log "
Crete the configuration for \`hashicups-db-1\` node with relative service and health checks."

_RUN_CMD 'tee ~/assets/scenario/conf/external-services/hashicups-db-1.json > /dev/null << EOF
{
  "Datacenter": "$CONSUL_DATACENTER",
  "Node": "hashicups-db-1-ext",
  "ID": "`cat /proc/sys/kernel/random/uuid`",
  "Address": "`dig hashicups-db-1 +short`",
  "NodeMeta": {
    "external-node": "true",
    "external-probe": "true"
  },
  "Service": {
    "ID": "hashicups-db-1",
    "Service": "hashicups-db",
    "Tags": [
      "external",
      "inst_1"
    ],
    "Address": "`dig hashicups-db-1 +short`",
    "Port": 5432
  },
  "Checks": [{
    "CheckID": "hashicups-db-1-check",
    "Name": "hashicups-db check",
    "Status": "passing",
    "ServiceID": "hashicups-db-1",
    "Definition": {
      "TCP": "`dig hashicups-db-1 +short`:5432",
      "Interval": "5s",
      "Timeout": "1s",
      "DeregisterCriticalServiceAfter": "30s"
     }
  }]
}
EOF
'

md_log "
Register the nodes in Consul catalog using the \`/v1/catalog/register\` endpoint."

for i in `find ~/assets/scenario/conf/external-services/*.json`; do

  _RUN_CMD 'curl --silent \
    --header "X-Consul-Token: $CONSUL_HTTP_TOKEN" \
    --connect-to server.${CONSUL_DATACENTER}.${CONSUL_DOMAIN}:8443:consul-server-0:8443 \
    --cacert ${CONSUL_CACERT} \
    --data @'$i' \
    --request PUT \
    https://server.${CONSUL_DATACENTER}.${CONSUL_DOMAIN}:8443/v1/catalog/register'

done

##  H2 -------------------------------------------------------------------------
md_log "
## Verify domain name resolution and load-balancing"
# ------------------------------------------------------------------------------

_CONNECT_TO hashicups-api-0

md_log "
Verify that you can resolve all instances of \`hashicups-db\` services using Consul."

# remote_exec hashicups-api-0 "dig hashicups-db.service.dc1.consul"

_RUN_CMD -r hashicups-api-0 "dig hashicups-db.service.dc1.consul"

md_log "
Notice the \`dig\` command returns two IPs. Consul will load balance requests across all available instances of the service."

md_log "
Verify that you can resolve \`hashicups-db-0-ext\` node using Consul."

# remote_exec hashicups-api-0 "dig hashicups-db-0-ext.node.dc1.consul"

_RUN_CMD -r hashicups-api-0 "dig hashicups-db-0-ext.node.dc1.consul"

md_log "
Verify you can connect to the first instance of \`hashicups-db\` service."

# remote_exec hashicups-api-0 'psql -d products -U hashicups -h inst_0.hashicups-db.service.dc1.consul -c "select * from coffees;"'

_RUN_CMD -r hashicups-api-0 'psql -d products -U hashicups -h inst_0.hashicups-db.service.dc1.consul -c "select * from coffees;"'

_EXIT_FROM hashicups-api-0

# for i in `seq 1 100` ; do dig @consul-server-0 '${_DNS_PORT}' hashicups-db.service.dc1.consul +short | head -1; done | sort | uniq -c

_CONNECT_TO hashicups-db-0

md_log "
Stop the first instance of \`hashicups-db\` service instance."

# remote_exec hashicups-db-0 "./start_service.sh stop"

_RUN_CMD -r hashicups-db-0 "./start_service.sh stop"

_EXIT_FROM hashicups-db-0

_CONNECT_TO hashicups-api-0

md_log "
Verify available instances of \`hashicups-db\` services using Consul."

# remote_exec hashicups-api-0 "dig hashicups-db.service.dc1.consul"

_RUN_CMD -r hashicups-api-0 "dig hashicups-db.service.dc1.consul"

md_log "
Notice the \`dig\` command still returns two IPs. This is because health checks are not performed periodically."

md_log "
Verify connection to \`hashicups-db-0-ext\` db instance."

# remote_exec hashicups-api-0 'psql -d products -U hashicups -h inst_0.hashicups-db.service.dc1.consul -c "select * from coffees;"'

_RUN_CMD -r hashicups-api-0 'psql -d products -U hashicups -h inst_0.hashicups-db.service.dc1.consul -c "select * from coffees;"'

_EXIT_FROM hashicups-api-0

##  H2 -------------------------------------------------------------------------
md_log "
## Create ACL token for consul-esm"
# ------------------------------------------------------------------------------

### H3 .........................................................................
md_log "
### Permissive ACL rules" 
# ..............................................................................

_RUN_CMD 'tee ~/assets/scenario/conf/acl-policy-consul-esm-permissive.hcl > /dev/null << EOF
# To check version compatibility and calculating network coordinates
agent_prefix "" {
  policy = "read"
}

# To store assigned checks
key_prefix "consul-esm/" {
  policy = "write"
}

# To update the status of each node that consul-esm monitors
node_prefix "" {
  policy = "write"
}

# To register consul-esm service
service_prefix "" {
  policy = "write"
}

# To acquire consul-esm cluster leader lock when used in HA mode
session_prefix "" {
   policy = "write"
}
EOF
'

_RUN_CMD "consul acl policy create -name 'acl-policy-consul-esm-permissive' -description 'Policy for consul-esm' -rules @/home/${_USER}/assets/scenario/conf/acl-policy-consul-esm-permissive.hcl  > /dev/null 2>&1"

_RUN_CMD "consul acl token create -description 'consul-esm token' -policy-name acl-policy-consul-esm-permissive --format json > /home/${_USER}/assets/scenario/conf/secrets/acl-token-consul-esm.json 2> /dev/null"

### H3 .........................................................................
md_log "
### Strict ACL rules" 
# ..............................................................................

_RUN_CMD 'tee ~/assets/scenario/conf/acl-policy-consul-esm-strict.hcl > /dev/null << EOF

# To check version compatibility and calculating network coordinates
# Requires at least read for the agent API for the Consul node 
# where consul-esm is registered
agent "consul-esm-0" {
  policy = "read"
}

# To store assigned checks
key_prefix "consul-esm/" {
  policy = "write"
}

# To update the status of each node monitored by consul-esm
# Requires one acl block per node
node_prefix "hashicups-db" {
  policy = "write"
}

# To retrieve nodes that need to be monitored
node_prefix "" {
  policy = "read"
}

# To register consul-esm service
service_prefix "consul-esm" {
  policy = "write"
}

# To update health status for external service hashicups-db
service "hashicups-db" {
  policy = "write"
}

# To acquire consul-esm cluster leader lock when used in HA mode
session "consul-esm-0" {
   policy = "write"
}
EOF
'

_RUN_CMD "consul acl policy create -name 'acl-policy-consul-esm-strict' -description 'Policy for consul-esm' -rules @/home/${_USER}/assets/scenario/conf/acl-policy-consul-esm-strict.hcl  > /dev/null 2>&1"

_RUN_CMD "consul acl token create -description 'consul-esm token' -policy-name acl-policy-consul-esm-strict --format json > /home/${_USER}/assets/scenario/conf/secrets/acl-token-consul-esm.json 2> /dev/null"

CONSUL_ESM_TOK=`cat /home/${_USER}/assets/scenario/conf/secrets/acl-token-consul-esm.json  | jq -r ".SecretID"` 

##  H2 -------------------------------------------------------------------------
md_log "
## Configure consul-esm"
# ------------------------------------------------------------------------------

_RUN_CMD 'tee ~/assets/scenario/conf/consul-esm-0/consul-esm-config.hcl > /dev/null << EOF
// The log level to use.
log_level = "DEBUG"

// Whether to log in json format
log_json = false

// The unique id for this agent to use when registering itself with Consul.
// If unconfigured, a UUID will be generated for the instance id.
// Note: do not reuse the same instance id value for other agents. This id
// must be unique to disambiguate different instances on the same host.
// Failure to maintain uniqueness will result in an already-exists error.
instance_id = "`cat /proc/sys/kernel/random/uuid`"

// The service name for this agent to use when registering itself with Consul.
consul_service = "consul-esm"

// The directory in the Consul KV store to use for storing runtime data.
consul_kv_path = "consul-esm/"

// The node metadata values used for the ESM to qualify a node in the catalog
// as an "external node".
external_node_meta {
    "external-node" = "true"
}

// The length of time to wait before reaping an external node due to failed
// pings.
node_reconnect_timeout = "72h"

// The interval to ping and update coordinates for external nodes that have
// 'external-probe' set to true. By default, ESM will attempt to ping and
// update the coordinates for all nodes it is watching every 10 seconds.
node_probe_interval = "10s"

// Controls whether or not to disable calculating and updating node coordinates
// when doing the node probe. Defaults to false i.e. coordinate updates
// are enabled.
disable_coordinate_updates = false

// The address of the local Consul agent. Can also be provided through the
// CONSUL_HTTP_ADDR environment variable.
http_addr = "localhost:8500"

// The ACL token to use when communicating with the local Consul agent. Can
// also be provided through the CONSUL_HTTP_TOKEN environment variable.
token = "${CONSUL_ESM_TOK}"

// The Consul datacenter to use.
datacenter = "${CONSUL_DATACENTER}"

// Client address to expose API endpoints. Required in order to expose /metrics endpoint for Prometheus.
client_address = "127.0.0.1:8080"

// The method to use for pinging external nodes. Defaults to "udp" but can
// also be set to "socket" to use ICMP (which requires root privileges).
ping_type = "udp"

// The number of additional successful checks needed to trigger a status update to
// passing. Defaults to 0, meaning the status will update to passing on the
// first successful check.
passing_threshold = 0

// The number of additional failed checks needed to trigger a status update to
// critical. Defaults to 0, meaning the status will update to critical on the
// first failed check.
critical_threshold = 0
EOF
'

md_log '
Copy the configuration file on the `consul-esm-0` node.'

_RUN_CMD 'scp -r -i '${SSH_CERT}' /home/'${_USER}'/assets/scenario/conf/consul-esm-0/consul-esm-config.hcl '${_USER}'@consul-esm-0:/home/'${_USER}'/consul-esm-config.hcl'

_STAT="$?"

if [ "${_STAT}" -ne 0 ];  then
  log_err "Error copying configuration file to the remote node."
  exit 254
fi

##  H2 -------------------------------------------------------------------------
md_log "
## Start consul-esm"
# ------------------------------------------------------------------------------

_CONNECT_TO consul-esm-0

md_log "
Verify the configuration file for consul-esm got correctly copied on the node."

_RUN_CMD -r consul-esm-0 -o hcl "cat /home/${_USER}/consul-esm-config.hcl"

_STAT="$?"

if [ "${_STAT}" -ne 0 ];  then
  log_err "Error. Configuration file not found on the remote node."
  exit 254
fi

md_log "
Once you tested the configuration, start consul-esm to run as a long lived process.
"

_RUN_CMD -r consul-esm-0 -o log "consul-esm -config-file=consul-esm-config.hcl > /tmp/consul-esm.log  2>&1 &"

_STAT="$?"

if [ "${_STAT}" -ne 0 ];  then
  log_err "Error. consul-esm start error."
  exit 254
fi

md_log "
The process is started in the background, you can check the logs for the process using the log file specified in the configuration.
"

_RUN_CMD -r consul-esm-0 -o log "cat /tmp/consul-esm*.log"

_STAT="$?"

if [ "${_STAT}" -ne 0 ];  then
  log_err "Error. consul-template log file not found."
  exit 254
fi

_EXIT_FROM consul-esm-0

##  H2 -------------------------------------------------------------------------
md_log "
## Verify load-balancing"
# ------------------------------------------------------------------------------

sleep 5

_RUN_CMD 'for i in `seq 1 100` ; do dig @consul-server-0 '${_DNS_PORT}' hashicups-db.service.dc1.consul +short | head -1; done | sort | uniq -c'

_CONNECT_TO hashicups-db-0

# remote_exec hashicups-db-0 "./start_service.sh start --consul"

_RUN_CMD -r hashicups-db-0 "./start_service.sh start --consul"

_EXIT_FROM hashicups-db-0

sleep 5

_CONNECT_TO hashicups-api-0

# for i in `seq 1 100` ; do dig @consul-server-0 '${_DNS_PORT}' hashicups-db.service.dc1.consul +short | head -1; done | sort | uniq -c

md_log "
Verify that you can resolve all instances of \`hashicups-db\` services using Consul."

# remote_exec hashicups-api-0 "dig hashicups-db.service.dc1.consul"

_RUN_CMD -r hashicups-api-0 "dig hashicups-db.service.dc1.consul"

md_log "
Notice the \`dig\` command returns two IPs. Consul will load balance requests across all available instances of the service."

md_log "
Now that consul-esm takes care of the health monitoring for the external services, 
you can use Consul service discovery to configure your downstream services."

# remote_exec hashicups-api-0 "./start_service.sh start --consul"

_RUN_CMD -r hashicups-api-0 "./start_service.sh start --consul"

md_log "
The command updates the configuration to use Consul domain names and restarts the service."

# remote_exec hashicups-api-0 "cat ~/conf.json"

_RUN_CMD -r hashicups-api-0 "cat ~/conf.json"

_EXIT_FROM hashicups-api-0

##  H2 -------------------------------------------------------------------------
md_log "
## Monitor an HTTP endpoint with consul-esm"
# ------------------------------------------------------------------------------

md_log "
Sometimes, for your application deployment you rely on external HTTP endpoints to retrieve deploy information.
These endpoints are usually not managed inside Consul datacenter and are also not monitored. 
This leaves room for possible malfunctioning worflows that rely on them to operate."

md_log "
Two good examples for this, when it comes to HashiCorp's tool deployment are the 
[releases.hashicorp.com](https://releases.hashicorp.com/) and the [checkpoint.hashicorp.com](https://checkpoint.hashicorp.com/).
These endpoints are often integrate in the tool installation process when information about version is required."

md_log "
Generate a UUID to use as node ID for the external services."

export RANDOM_UUID=`cat /proc/sys/kernel/random/uuid`


md_log "
Create the configuration for an external node with the relative services and health checks configured."

_RUN_CMD 'tee ~/assets/scenario/conf/external-services/hashicorp-releases.json > /dev/null << EOF
{
  "Datacenter": "$CONSUL_DATACENTER",
  "Node": "hashicorp",
  "ID": "${RANDOM_UUID}",
  "Address": "hashicorp.com",
  "NodeMeta": {
    "external-node": "true"
  },
  "Service": {
    "ID": "releases.hashicorp.com",
    "Service": "hashicorp-releases",
    "Tags": [
      "external",
      "deploy"
    ],
    "Address": "releases.hashicorp.com",
    "Port": 443
  },
  "Checks": [{
    "CheckID": "releases.hashicorp.com",
    "Name": "releases.hashicorp.com check",
    "Status": "warning",
    "ServiceID": "releases.hashicorp.com",
    "Definition": {
      "http": "https://releases.hashicorp.com",
      "Interval": "30s",
      "Timeout": "10s"
     }
  }]
}
EOF
'

_RUN_CMD 'tee ~/assets/scenario/conf/external-services/hashicorp-checkpoint.json > /dev/null << EOF
{
  "Datacenter": "$CONSUL_DATACENTER",
  "Node": "hashicorp",
  "ID": "${RANDOM_UUID}",
  "Address": "hashicorp.com",
  "NodeMeta": {
    "external-node": "true"
  },
  "Service": {
    "ID": "checkpoint.hashicorp.com",
    "Service": "hashicorp-checkpoint",
    "Tags": [
      "external",
      "deploy"
    ],
    "Address": "checkpoint.hashicorp.com",
    "Port": 443
  },
  "Checks": [{
    "CheckID": "checkpoint.hashicorp.com",
    "Name": "checkpoint.hashicorp.com check",
    "Status": "warning",
    "ServiceID": "checkpoint.hashicorp.com",
    "Definition": {
      "http": "https://checkpoint.hashicorp.com",
      "Interval": "30s",
      "Timeout": "10s"
     }
  }]
}
EOF
'

for i in `find ~/assets/scenario/conf/external-services/hashicorp*.json`; do

  _RUN_CMD 'curl --silent \
    --header "X-Consul-Token: $CONSUL_HTTP_TOKEN" \
    --connect-to server.${CONSUL_DATACENTER}.${CONSUL_DOMAIN}:8443:consul-server-0:8443 \
    --cacert ${CONSUL_CACERT} \
    --data @'$i' \
    --request PUT \
    https://server.${CONSUL_DATACENTER}.${CONSUL_DOMAIN}:8443/v1/catalog/register'

done


_RUN_CMD 'tee ~/assets/scenario/conf/acl-policy-consul-esm-strict-addendum.hcl > /dev/null << EOF
# To check version compatibility and calculating network coordinates
# Requires at least read for the agent API for the Consul node 
# where consul-esm is registered
agent "consul-esm-0" {
  policy = "read"
}

# To store assigned checks
key_prefix "consul-esm/" {
  policy = "write"
}

# To update the status of each node monitored by consul-esm
# Requires one acl block per node
node_prefix "hashicups-db" {
  policy = "write"
}

node_prefix "hashicorp" {
  policy = "write"
}

# To retrieve nodes that need to be monitored
node_prefix "" {
  policy = "read"
}

# To register consul-esm service
service_prefix "consul-esm" {
  policy = "write"
}

service "hashicups-db" {
  policy = "write"
}

service_prefix "hashicorp-" {
  policy = "write"
}

# To acquire consul-esm cluster leader lock when used in HA mode
session "consul-esm-0" {
   policy = "write"
}
EOF
'

_RUN_CMD 'consul acl policy update -name "acl-policy-consul-esm-strict" -rules @/home/${_USER}/assets/scenario/conf/acl-policy-consul-esm-strict-addendum.hcl > /dev/null 2>&1'

log_err "$CONSUL_HTTP_TOKEN"