#!/bin/bash

set -eu

# Get path of the script
SCRIPT_PATH=$(dirname "${BASH_SOURCE[0]}")

# Check if a special command is issued and ignore the config check if thats the case
if [ $1 != "config" ] && [ $1 != "help" ]; then
    if ! test -f "$SCRIPT_PATH/wg-config.json"; then
        echo "ERROR: wg-config.json is missing in script path. Please create a config file first."
        exit 1
    fi

    # Get global config values
    CONFIG_FILE=$(cat $SCRIPT_PATH/wg-config.json)
    PRIVATE_KEY=$(echo "$CONFIG_FILE" | jq -r '.privateKey')
    OWN_IP4=$(echo "$CONFIG_FILE" | jq -r '.ownIPv4')
    OWN_IP6=$(echo "$CONFIG_FILE" | jq -r '.ownIPv6')
    OWN_IP6LL=$(echo "$CONFIG_FILE" | jq -r '.ownIPv6LinkLocal')
    PEER_CONFIG_FOLDER=$(echo "$CONFIG_FILE" | jq -r '.peerConfigPath')
    EXCLUDED_INTERFACES=($(echo "$CONFIG_FILE" | jq -r '.excludedInterfaces | .[]'))
fi

create() {

    echo "Creating interface for peer \"$1.wg.json\"..."

    # Check if config file for given peer exists
    if ! test -f "$PEER_CONFIG_FOLDER/$1.wg.json"; then
        echo "ERROR: Can't find config file for peer \"$1\" in path \"$PEER_CONFIG_FOLDER\"."
        exit 1
    fi

    # Get peer config variables
    PEER_CONF=$(cat $PEER_CONFIG_FOLDER/$1.wg.json)
    PEER_PUB_KEY=$(echo "$PEER_CONF" | jq -r '.publicKey')
    PEER_LOCAL_PORT=$(echo "$PEER_CONF" | jq -r '.localPort')
    PEER_ENDPOINT=$(echo "$PEER_CONF" | jq -r '.endpoint')
    PEER_IP4=$(echo "$PEER_CONF" | jq -r '.peerIPv4')
    PEER_IP6=$(echo "$PEER_CONF" | jq -r '.peerIPv6')
    PEER_CUSTOM_IP6LL=$(echo "$PEER_CONF" | jq -r '.customLinkLocal')

    # Create interface
    ip link add dev "wg-$1" type wireguard

    # Configure wireguard
    echo "$PRIVATE_KEY" | wg set "wg-$1" \
        $([ -n "${PEER_LOCAL_PORT+x}" ] && echo "listen-port $PEER_LOCAL_PORT") \
        private-key /dev/stdin \
        peer "$PEER_PUB_KEY" \
        allowed-ips "0.0.0.0/0,::/0" \
        $([ -n "$PEER_ENDPOINT" ] && echo "endpoint $PEER_ENDPOINT")

    # Set interface up
    ip link set dev "wg-$1" up

    # Add own and peer ip4 addresses
    if [ -n "${OWN_IP4+x}" ]; then
        add_addr="ip addr add $OWN_IP4 dev wg-$1"
        if [ -n "${PEER_IP4}" ]; then
            add_addr="$add_addr peer $PEER_IP4"
        fi
        eval $add_addr
    fi

    # Set own ip6 address
    if [ -n "${OWN_IP6+x}" ]; then
        ip addr add "$OWN_IP6" dev "wg-$1"
    fi

    # Set peer specific ip6 link-local, otherwise default ip6 link-local
    if [ -n "${PEER_CUSTOM_IP6LL}" ]; then
        ip addr add "$PEER_CUSTOM_IP6LL" dev "wg-$1"
    else
        if [ -n "${OWN_IP6LL+x}" ]; then
            ip addr add "$OWN_IP6LL" dev "wg-$1"
        fi
    fi

    #Set own ip6
    if [ -n "$OWN_IP6" ]; then
        ip route add "$OWN_IP6" dev "wg-$1"
    fi

    # Deny forwarding for excluded interfaces
    for interface in "${EXCLUDED_INTERFACES[@]}"
    do
        ip6tables -A FORWARD -i "wg-$1" -o "$interface" -j DROP
        ip6tables -A FORWARD -i "$interface" -o "wg-$1" -j DROP
        iptables -A FORWARD -i "wg-$1" -o "$interface" -j DROP
        iptables -A FORWARD -i "$interface" -o "wg-$1" -j DROP
    done
}

# Remove interface if existent
remove() {
    if ip link | grep -q "wg-$1"; then
        ip link del "wg-$1"
        echo "Interface wg-$1 removed."
    else
        echo "ERROR: Interface \"wg-$1\" could't be removed, because it doesn't exist."
        exit 1
    fi
}

# Call create() for every peer in the configured folder
createall() {
    echo "Creating interfaces for peers in path \"$PEER_CONFIG_FOLDER\"."
    for peer in $(ls $PEER_CONFIG_FOLDER | egrep -i '.*\.wg\.json' ); do
        peer=$(echo "$peer" | sed 's/.wg.json//g')
        create $peer
    done
}

# Call remove() for every interface that starts with wg-*
removeall() {
    echo "Removing all active interfaces..."
    for peer in $(ip link | egrep -o "wg-[^:]*"); do
        peer=$(echo "$peer" | sed 's/wg-//')
        remove $peer
    done
}

# Create an empty config file in the script path
config() {
    echo "{
        \"privateKey\": \"\",
        \"ownIPv4\": \"\",
        \"ownIPv6\": \"\",
        \"ownIPv6LinkLocal\": \"\",
        \"peerConfigPath\": \"\",
        \"excludedInterfaces\": [
            \"\"
        ]
    }" | jq '.' > $SCRIPT_PATH/wg-config.json
}

# Create an example peer config at the specified location
template() {
    echo "{
        \"publicKey\": \"\",
        \"localPort\": 1234,
        \"endpoint\": \"example.com:1234\",
        \"peerIPv4\": \"10.0.0.1\",
        \"peerIPv6\": \"fe80::1\",
        \"customLinkLocal\": \"\"
    }" | jq '.' > $1
}

ACTION=$1
case $ACTION in
    up)
        if [ "$#" -ne 2 ]; then
            echo "ERROR: Please specify a peer name."
            exit 1
        else
            create $2
        fi
    ;;
    down)
        if [ "$#" -ne 2 ]; then
            echo "ERROR: Please specify a peer name."
            exit 1
        else
            remove $2
        fi
    ;;
    restart)
        if [ "$#" -ne 2 ]; then
            echo "ERROR: Please specify a peer name."
            exit 1
        else
            remove $2
            create $2
        fi
    ;;
    allup)
        createall
    ;;
    alldown)
        removeall
    ;;
    config)
        config
    ;;
    template)
        if [ "$#" -ne 2 ]; then
            echo "ERROR: Please specify a path for the new template."
            exit 1
        else
            template $2
        fi
    ;;
    help)
        echo "Usage: ./wireguard.sh <action> (parameters)"
        echo "Available actions:"
        echo "    up <peername>        Create new wireguard interface for a given peer."
        echo "    down <peername>      Remove wireguard interface for a given peer."
        echo "    restart <peername>   Recreate the wireguard interface for a given peer."
        echo "    allup                Create interfaces for all peers in configured folder."
        echo "    alldown              Remove all active wireguard interfaces."
        echo "    config               Create an empty config file in the script path."
        echo "    template <path>      Create an empty peer config template."
    ;;
    *)
        echo "Invalid action \"$ACTION\"."' Use "./wireguard.sh help" to get help.'
        exit 1
esac
