# vsh
TCL script for Cisco routers that parses out all parts of specified VRF including vpn/crypto, nat, routing, and acl config.

This script can be run directly on the router or you can download the config to a server and run it against the config on the server. It has been extensively tested running directly on a Cisco 7609. 

To run it on a cisco router, copy it to the local disk and create an alias for it:

	alias exec vsh tclsh disk0:vsh.tcl

After the Alias is created you can run it as below:

	Usage: vsh <config_source> <config_area> vrf <vrf_name>
	
   	   	config_source: running|startup|config or filename
				
  	   	config_area  : all|bgp|ospf|rip|eigrp|static|interface|def|routing|crypto|nat
				
   	   	vrf_name     : <name of the VRF wished to display>
 
	I.E:  vsh run all vrf MyVrfName

To run from a server with a downloaded config:

	tclsh ./vsh_v5.tcl ./router1.cfg all vrf MyVrfName


