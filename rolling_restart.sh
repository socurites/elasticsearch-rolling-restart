#!/bin/bash
 
#
# perform a rolling restart of all data/master nodes in a stable cluster
#
# args: [elasticsearch-host:port]
#


set -e
set -u

GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color
 
CLUSTER="${1:-localhost:9200}"
 
function dprintf {
    printf "$( date -u +"%Y-%m-%dT%H:%M:%SZ" ) $@\n"
}
 
 
if [[ "green" != $(curl -s "${CLUSTER}/_cat/health?h=status" | tr -d '[:space:]') ]] ; then
    echo "Cluster is not green!"
 
exit 1
else
    printf "Cluster is ${GREEN}green${NC}!\n"
fi
 
 
# enumerate nodes, starting with master, finishing with data
for NODEREF in $( curl -s "${CLUSTER}/_cat/nodes?h=host,node.role,master,name" | sed -E 's/ (.) \* / \1 m /' | sort -k 3,3r -k 2,2 -k 4,4 | awk '{ printf "%s|%s\n", $1, $4 }' ) ; do

    NODE=$( echo "${NODEREF}" | awk -F '|' '{ print $1 }' )
    NODE_NAME=$( echo "${NODEREF}" | awk -F '|' '{ print $2 }' )
 
    dprintf "> restarting ${BLUE}${NODE_NAME}${NC} STARTED"

    dprintf ">>> disabling allocations"
    curl -s -X PUT "${CLUSTER}/_cluster/settings" -d '{"transient":{"cluster.routing.allocation.enable":"none"}}' > /dev/null

    dprintf ">>> sending shutdown to ${BLUE}${NODE_NAME}${NC}"
    curl -s -X POST "${CLUSTER}/_cluster/nodes/${NODE_NAME}/_shutdown" > /dev/null

    dprintf ">>> waiting for node to leave"
    while curl -s "${CLUSTER}/_cat/nodes?h=name" | grep "${NODE_NAME}" > /dev/null ; do
        sleep 2
    done 

    dprintf ">>> !!! Go and manually start node ${BLUE}${NODE_NAME}${NC}"

    dprintf ">>> waiting for node to rejoin"
    while ! curl -s --retry 8 "${CLUSTER}/_cat/nodes?h=name" | grep "${NODE_NAME}" > /dev/null ; do
        sleep 2
    done 

    dprintf ">>> enabling allocations"
    curl -s -X PUT "${CLUSTER}/_cluster/settings" -d '{"transient":{"cluster.routing.allocation.enable":"all"}}' > /dev/null

    dprintf ">>> waiting for green"
    while [[ "green" != $(curl -s "${CLUSTER}/_cat/health?h=status" | tr -d '[:space:]') ]] ; do
        sleep 8
    done

    dprintf "> restarting ${BLUE}${NODE_NAME}${NC} ENDED"
    echo "================================================================="
done
