#!/usr/bin/env bash

# ++-----------------+
# || Variables       |
# ++-----------------+

export STEP_ASSETS="${SCENARIO_OUTPUT_FOLDER}conf/"

# ++-----------------+
# || Begin           |
# ++-----------------+

header1 "Deploy HashiCups application in service discovery mode"


# You can exclude services from the configuration 
_EXTERNAL_SERVICES=( "hashicups-db" )

