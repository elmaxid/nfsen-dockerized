# Linux Networking Flow Exporting

There are currently two prevalent virtual switch datapaths:

1. Linux Bridge: while natively installed, it does not have a native means for exporting Netflow, sFlow or IPFIX
2. OpenvSwitch: has native flow export support but requires installation from package (yum install/apt-get install)

## Linux Bridging Export Config ###

Here are some quick instructions for compiling and running it. This exports netflow traffic to the running nfsen collector you define in /etc/default/softflowd

	$ apt-get install softflowd
	$ sed  -i 's/^INTERFACE=\"\"/INTERFACE=\"any\"/' /etc/default/softflowd
	$ sed -i 's/^OPTIONS=\"\"/OPTIONS=\"-n 192.168.59.103:9995\"/' /etc/default/softflowd
	$ /etc/init.d/softflowd start


## OVS Flow Export Configuration ###

Simply paste in the environmental variables above into your terminal:

	COLLECTOR_NFLOW_IP=192.168.59.103
	COLLECTOR_NFLOW_PORT=9995
	AGENT_IP=eth0
	HEADER_BYTES=512
	SAMPLING_N=64
	POLLING_SECS=5

If you want this environmental variable to be persistent add them to your `.bashrc` followed by `source ~/.bashrc`

To add them to your container, open the Dockerfile and add (ENV key=val):

## Exporting Netflow from OVS ###

-Example without variables

Create a bridge:

	$ ovs-vsctl add-br br0

Add the net flow export

	$ ovs-vsctl -- set Bridge br0 netflow=@nf -- --id=@nf create NetFlow targets=\"192.168.59.103:9995\"

or using ENV variables

-Example using the ENV variables (verify they are defined with `export` from your bash shell)

	$ ovs-vsctl -- set Bridge br0 netflow=@nf -- --id=@nf create NetFlow target=\"${COLLECTOR_NFLOW_IP}:${COLLECTOR_NFLOW_PORT}\"


List the newly added sFlow export:

	$ ovs-vsctl list NetFlow

- To remove the configuration in the sFlow ovsdb table, simply use the following:

	$ ovs-vsctl -- clear Bridge br0 NetFlow

### Exporting sFlow from OVS ###

Add ENV variables since this is a slightly complex command to keep things consistent (low sampling for debugging/validation):

	COLLECTOR_SFLOW_IP=192.168.59.103
	COLLECTOR_SFLOW_PORT=6343
	AGENT_IP=eth0
	HEADER_BYTES=512
	SAMPLING_N=1
	POLLING_SECS=5

Create a bridge:

	$ ovs-vsctl add-br br0

Add the sFlow export (one liner broken up into multiple lines with an escape backslash):

	$ ovs-vsctl -- --id=@sflow create sflow agent=${AGENT_IP} \
	target=\"${COLLECTOR_SFLOW_IP}:${COLLECTOR_SFLOW_PORT}\" header=${HEADER_BYTES} \
	sampling=${SAMPLING_N} polling=${POLLING_SECS} -- set bridge br0 sflow=@sflow


List the newly added sFlow export:

	$ ovs-vsctl list sFlow

To remove the sFlow export (*note* unlike the NetFlow entry this requires the UUID as a parameter):

	$ ovs-vsctl remove bridge br0 sFlow c4364139-5329-44fb-8a91-e9dd1d2caca4


## Exporting IPFIX from OVS ###

Create a bridge:

	$ ovs-vsctl add-br br0

These are pretty random values below for debugging and testing payload generation:

	CACHE_ACTIVE_TIMEOUTS=20
	CACHE_MAX_TIMEOUTS=20
	CACHE_MAX_FLOWS=50
	OBS_DOMAIN_ID=123
	OBS_POINT_ID=456
	SAMPLING_RATE=1
	COLLECTOR_IPFIX_IP=192.168.59.103
	COLLECTOR_IPFIX_PORT=4739

Add the example export to OVS:

	$ ovs-vsctl -- set Bridge br0 ipfix=@i -- --id=@i \
	create IPFIX target=\"${COLLECTOR_IPFIX_IP}:${COLLECTOR_IPFIX_PORT}\" \
	obs_domain_id=${OBS_DOMAIN_ID} obs_point_id=${OBS_POINT_ID} \
	cache_active_timeout=${CACHE_ACTIVE_TIMEOUTS} \
	sampling=${SAMPLING_RATE} cache_max_flows=${CACHE_MAX_FLOWS}

List the newly added IPFIX export:

	$ ovs-vsctl list IPFIX

Outputs:

	_uuid               : 10c97f52-c9fe-41d0-93ad-a0a9a43b46f0
	cache_active_timeout: 200
	cache_max_flows     : 1000
	external_ids        : {}
	obs_domain_id       : 123
	obs_point_id        : 456
	other_config        : {}
	sampling            : 1
	targets             : ["192.168.59.103:4739"]

Remove the IPFIX table entry with the following  (*note* unlike the NetFlow entry this requires the UUID as a parameter):

	$ ovs-vsctl remove bridge br0 IPFIX 10c97f52-c9fe-41d0-93ad-a0a9a43b46f0
