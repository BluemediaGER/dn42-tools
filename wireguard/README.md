# wireguard

This folder contains my WireGuard script, which I use on all my servers to manage my tunnels. Corresponding example configurations can also be found here.  
Since wg-quick also manages routing in addition to the tunnels themselves, I need a separate tool, as route management is supposed to be done exclusively by Bird 2.  
The script is designed to be able to configure the individual tunnels in JSON files. This has the advantage that tunnels can be managed e.g. via Ansible and the whole configuration can be tracked in a git repo.

## Quick start

Before you can create your first tunnel, you must first configure the global settings needed by the script. The script expects a config file named `wg-config.json` in the same path as the script itself. To create a new empty configuration you can use the following command:

```bash
./wireguard.sh config
```
This command creates a new configuration file and already inserts the necessary JSON structure. Complete it with your settings. You can find an example configuration in the file `wg-config.json.example`.  

The configuration options are explained below:

| Key | Description |
|:----|:------------|
|privateKey|This should be the WireGuard private key used for all connections|
|ownIPv4|IPv4 address used on tunnel interfaces|
|ownIPv6|IPv6 address used on tunnel interfaces|
|ownIPv6LinkLocal|IPv6 link local address used on tunnel interfaces|
|peerConfigPath|Path (without trailing slash) where your peer configurations are located|
|excludedInterfaces|Array of interface names that should be excluded from allowed packet forwarding via iptables|

Next, you can create your first peer. Create a new configuration file in the path you set above. You must use the file extension `.wg.json`. The script can create the corresponding file as a template. Use the following command and specify the path for the new file:

```bash
./wireguard.sh template /home/dn42/peers/example-peer.wg.json
```
An example configuration can be found in `example-peer.wg.json`.

The configuration options are explained below:

| Key | Description |
|:----|:------------|
|publicKey|This should be the WireGuard public key of your peer|
|localPort|Local port the WireGuard interface will listen on (leave empty to auto generate)|
|endpoint|WireGuard endpoint of your peer (can also be left blank)|
|peerIPv4|In-tunnel IPv4 address of your peer (used for point to point connection)|
|peerIPv6|In-tunnel IPv6 address of your peer (used for point to point connection)|
|customLinkLocal|Overide the IPv6 link local address from the global config (leave blank to use global default)|

The interface name is derived from the filename. It is generated in in the format `wg-<filename>`.  
  
To bring your newly created interface up, run the following command with elevated privileges:
```bash
./wireguard.sh up example-peer
```

If you want to know more about the actions the script offers, try using the following command:
```bash
./wireguard.sh help
```