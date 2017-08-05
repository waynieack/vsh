# vsh
TCL script for Cisco routers that parses out all parts of specified VRF including vpn/crypto, nat, routing, and acl config.

This program is used to parse the CISCO IOS config and show only configuration elements relevant for specified VRF. It can be selected which element to display:
* VRF definition ('def' keyword)
* A routing element ('routing|bgp|ospf|rip|eigrp|static')
* Interface ('interface' keyword) 
* VPN ('crypto' keyword)
* Nat Static/Dynamic ('nat' keyword)
* All VRF Config ('all' keyword)

Any ACL, prefix-list, route-map, crypto-map, or nat referenced in the relevant config part will also be shown.

* It can be run directly on the router or you can download the config to a server and run it against the config on the server. 
* It has been extensively tested running directly on a Cisco 7609. 

ios config:

   * download the file into flash:vsh.tcl
   * configure alias:
   
   	exec vsh tclsh flash:vsh.tcl
	
NOTE: name 'vsh' can be any name that does not conflict with built-in IOS commands

Usage: 
	
	vsh <config_source> <config_area> vrf <vrf_name>
   		config_source : running|{startup|config} or filename
   		config_area   : all|bgp|ospf|rip|eigrp|static|interface|def|routing|crypto|nat
   		vrf_name      : <name of the VRF wished to display>
      		All keywords can be abbreviated

Examples:

	vsh start eigr vrf MyVRF
          vsh run all vrf MyVRF
          vsh flash:myconf.txt routing vrf MyVRF
          vsh help


To run from a server with a downloaded config:

	tclsh ./vsh_v5.tcl ./router1.cfg all vrf MyVrfName


