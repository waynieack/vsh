#tcl
#############################################################################
# Copyright       EDS, D.Koncic, 2006, All rights reserved
##############################################################################
#
# AUTHOR        : D.Koncic, davor.koncic@eds.com, Wayne Gatlin, wayne@razorcla.ws
# VERSION       : 1.2
#                 vsh.tcl, 8.12.2013
#
# This program is used to parse the CISCO IOS config and show only configuration elements relevant for specified VRF. It can be selected which element to display:
# * VRF definition ('def' keyword)
# * A routing element ('routing|bgp|ospf|rip|eigrp|static')
# * Interface ('interface' keyword) 
# * VPN ('crypto' keyword)
# * Nat Static/Dynamic ('nat' keyword)
# * All VRF Config ('all' keyword)
# 
# Any ACL, prefix-list, route-map, crypto-map, or nat referenced in the relevant config part will also be shown.
#
# ios config:
#
#    * download the file into flash:vsh.tcl
#    * configure alias exec vsh tclsh flash:vsh.tcl
#             (NOTE: name 'vsh' can be any name that does not 
#                    conflict with built-in IOS commands)
#
# Usage: vsh <config_source> <config_area> vrf <vrf_name>
#    config_source : running|{startup|config} or filename
#    config_area   : all|bgp|ospf|rip|eigrp|static|interface|def|routing|crypto|nat
#    vrf_name      : <name of the VRF wished to display>
#       All keywords can be abbreviated
#
# Examples: vsh start eigr vrf MyVRF
#           vsh run all vrf MyVRF
#           vsh flash:myconf.txt routing vrf MyVRF
#           vsh help
# NOTE: it is recommended to perform this program on saved config ('startup')
#       or saved file, to avoid running config file locking by IOS. 
#       This program can also be executed on any other OS with tclsh
#
# Change log:   Ver 1.0
#			  - Added crypto section of vrf configuration. (Wayne Gatlin, U.S., wayne@razorcla.ws)
#			  - Added nat section of vrf configuration. (Wayne Gatlin, U.S., wayne@razorcla.ws)
#			  - Corrected problem with missing last ACL in configuration in 'findprintacls'. (Wayne Gatlin, U.S., wayne@razorcla.ws)
#			  - Moved to loop in 'checkintacl' to ensure all ACLs are found. (Wayne Gatlin, U.S., wayne@razorcla.ws)
#			  
#				Ver 1.1
#			  - Moved to reusable name search (checkintnames) to shorten script. (Wayne Gatlin, U.S., wayne@razorcla.ws)
#			  - Added dynamic crypto maps to crypto section. (Wayne Gatlin, U.S., wayne@razorcla.ws)
#			  - Corrected issue with not finding crypto maps with "redundancy". (Wayne Gatlin, U.S., wayne@razorcla.ws)
#			  - Corrected issue with not finding crypto key rings linked to the vrf. (Wayne Gatlin, U.S., wayne@razorcla.ws)
#
#				Ver 1.2
#			  - Added a failsafe loop count to all the "while" loops to ensure an endless loop does not occur (Wayne Gatlin, U.S., wayne@razorcla.ws)
#			  - Added transform set to crypto section (Wayne Gatlin, U.S., wayne@razorcla.ws)
#			  - Fixed issue with NAT section (Wayne Gatlin, U.S., wayne@razorcla.ws)
#			  - Added dynamic crypto dhcp pool to crypto section (Wayne Gatlin, U.S., wayne@razorcla.ws)
#
###############################LICENCE#########################################
#Redistribution and use in source and binary forms, with or without modification,
# are permitted provided that the following conditions are met:
#
#* Redistributions of source code must retain the above copyright notice, 
#this list of conditions and the following disclaimer. 
#
#*Redistributions in binary form must reproduce the above copyright notice, 
#this list of conditions and the following disclaimer in the documentation and/or 
#other materials provided with the distribution. 
#
#* Neither the name of EDS, HP, the name of the copyright holder nor the 
#names of their respective contributors may be used to endorse or promote products
# derived from this software without specific prior written permission. 
#
#
#THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND 
#ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED 
#WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
#  IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, 
#INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, 
#BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, 
#DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
# LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE
# OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED
# OF THE POSSIBILITY OF SUCH DAMAGE.
#################################################################################


#################################################################
# PROCEDURE NAME: setcrlf
# AUTHOR        : D.Koncic, EDS Switzerland
# USE           : this tcl procedure determines what type of config
#                 file is in use and defines CRLF properties. This
#                 is due to OS/FS differencies
# ARGUMENTS     : 
# NOTES         : this proc uses some global variables (G_runcfg)
#                 to avoid copying with long configs
#################################################################

proc setcrlf { } {

    global G_runcfg
    global ICRLF
    global CRLF
    global CRLFlen

 if { $CRLFlen == 0 } {
    # test for the crlf type (\r\n or \n)
    set testcrlf [ string first !\r\n $G_runcfg 0 ]
    if { $testcrlf != -1} {
         set ICRLF "!\r\n"
         set CRLF  "\r\n"
         set CRLFlen 3
        } else {
         set ICRLF "!\n"
         set CRLF  "\n"
         set CRLFlen 2
        }
   }
}


#-----------------------------------------------------------------

#################################################################
# PROCEDURE NAME: getvrfint
# AUTHOR        : D.Koncic, EDS Switzerland
# USE           : this tcl procedure goes throught the IOS
#                 device config file and selects only those parts
#                 corresponding to interfaces with given VRF name
# ARGUMENTS     : CFG_MODE - determines if running, startup or
#                            file name of the local disk/flash
#                 condvar  - VRF name
# NOTES         : this proc uses some global variables (G_runcfg)
#                 to avoid copying with long configs
#################################################################

proc getvrfint {CFG_MODE condvar} {

    global G_runcfg
    global ICRLF
    global CRLF
    global CRLFlen
    global LOOPCOUNT
    set LC 0

    fetchcfg $CFG_MODE

    setcrlf

    # get the length of the runcfg string
    set runcfglen [ string length $G_runcfg ]

    # init variables for the loop
    set i 0
    set newi 0

    puts "!"
    #

    while {$i < $runcfglen && $newi > -1} {
      # search for the occurances of "!" as the last in the line
      set newi [ string first $ICRLF $G_runcfg $i ]

      # handle the end of the string (-1 return code)
      if { $newi != -1 } {

         # cut out one paragraph between the two !s
         set parag [ string range $G_runcfg $i $newi ]

         # print the paragraph out if including the search string, vrf name
         if { [ string first "ip vrf forwarding $condvar$CRLF" $parag 0 ] != -1} {
                puts $parag
                # Now need to check for access-group/ACLs
                checkintacl $parag
                checkintcryptomap $parag
           }

         # move the pointers
         set i [ expr $newi+$CRLFlen ]
       }
       incr LC
        #fail safe for endless looops
         if { $LC > $LOOPCOUNT } {
         puts "Loop count is $LC and global fail safe is $LOOPCOUNT exiting!!"
        break
        }
     }
}

#-----------------------------------------------------------------


##################################################################
# PROCEDURE NAME: checkintacl
# AUTHOR        : D.Koncic, EDS Switzerland
# USE           : this tcl procedure goes throught the given string
#                 as an argument and finds the names of ACLs 
# ARGUMENTS     : string to analyze
# NOTES         : this proc uses some global variables (G_runcfg)
#                 to avoid copying with long configs
#################################################################

proc checkintacl {args} {

    global G_runcfg
    global G_RMAP_LIST
    global G_ACL_LIST
    global G_PREFX_LIST
    global ICRLF
    global CRLF
    global CRLFlen
    global LOOPCOUNT
    set LC 0

    set aclgi1 [ string first "ip access-group " $args 0 ]
    while { $aclgi1 != -1} {
        #found one
        set crlfi [ string first $CRLF $args $aclgi1 ]
        if { $crlfi != -1 } {
            set aclgline [ string range $args $aclgi1 $crlfi ]
            set aclglist [ split $aclgline ]
            set aclglistout [ lindex $aclglist end-2]
            lappend G_ACL_LIST $aclglistout   
            #search for another one
            set aclgi1 [ string first "ip access-group " $args $crlfi ]                                 
           }
            incr LC
            #fail safe for endless looops
           if { $LC > $LOOPCOUNT } { 
              puts "Loop count is $LC and global fail safe is $LOOPCOUNT exiting!!"
				puts "Search string was > ip access-group $args <"
             break
          }
       }
#puts "ACLlist>$G_ACL_LIST<"
}

#-----------------------------------------------------------------

##################################################################
# PROCEDURE NAME: checkintnames
# AUTHOR        : Wayne Gatlin, U.S., wayne@razorcla.ws  
# USE           : this tcl procedure goes throught the given string
#                 as an argument and finds the name
# ARGUMENTS     : string to analyze, element number, string to search for.
# NOTES         : 
#################################################################

proc checkintnames {args itemnum schstr} {

    global CRLF
    global LOOPCOUNT
    set ITEM_LIST ""
    set LC 0 

    set itname [ string first $schstr $args 0 ]
    
    while { $itname != -1} {
        #found one
        set itnamecnt [ string first $CRLF $args $itname ]
        if { $itnamecnt != -1 } {
            set itnameline [ string range $args $itname $itnamecnt ]
            set itnamelist [ split $itnameline ]
            set itnamelistout [ lindex $itnamelist $itemnum ]
            lappend ITEM_LIST $itnamelistout 
           #search for another one
            set itname [ string first $schstr $args $itnamecnt ]
           }
	    incr LC
            #fail safe for endless looops
            if { $LC > $LOOPCOUNT } {
             puts "Loop count is $LC and global fail safe is $LOOPCOUNT exiting!!"
	     puts "Search string was > $schstr $args <"
             break
          }
       }
return $ITEM_LIST
}

#-----------------------------------------------------------------


##################################################################
# PROCEDURE NAME: checkintcryptomap
# AUTHOR        : Wayne Gatlin, U.S., wayne@razorcla.ws 
# USE           : this tcl procedure goes throught the given string
#                 as an argument and finds the names of crypto maps
# ARGUMENTS     : string to analyze
# NOTES         : this proc uses some global variables (G_runcfg)
#                 to avoid copying with long configs
#################################################################

proc checkintcryptomap {args} {

    global G_runcfg
    global G_CRYMP_LIST
    global ICRLF
    global CRLF
    global CRLFlen

    set crymp1 [ string first "crypto map " $args 0 ]
    if { $crymp1 != -1} {
        #found one
        set crympcnt [ string first $CRLF $args $crymp1 ]
        if { $crympcnt != -1 } {
            set crympline [ string range $args $crymp1 $crympcnt ]
            set crymplist [ split $crympline ]
            set crymplistout [ lindex $crymplist 2 ]
            lappend G_CRYMP_LIST $crymplistout   
           }
       }
#puts "Cryptolist>$G_CRYMP_LIST<"
}

#-----------------------------------------------------------------


##################################################################
# PROCEDURE NAME: checkintcrydhcp
# AUTHOR        : Wayne Gatlin, U.S., wayne@razorcla.ws 
# USE           : this tcl procedure goes throught the given string
#                 as an argument and finds the names of crypto dhcp 
#				  pools
# ARGUMENTS     : string to analyze
# NOTES         : this proc uses some global variables (G_runcfg)
#                 to avoid copying with long configs
#################################################################

proc checkintcrydhcp {args} {

    global ICRLF
    global CRLF
    global CRLFlen

    foreach crydhcppool [ regexp -all -inline -line "pool \.*" $args ] {
   regsub -all "^pool " $crydhcppool "" crydhcppool
  regsub -all "\}" $crydhcppool "" crydhcppool 
   return $crydhcppool }

}

#-----------------------------------------------------------------


################################################################
# PROCEDURE NAME: findprintcryptomap
# AUTHOR        : Wayne Gatlin, U.S., wayne@razorcla.ws 
# USE           : this tcl procedure goes throught the IOS
#                 device config file and selects only the part
#                 corresponding to crypto maps based on the global 
#		  		  list G_CRYMP_LIST if crymptyp = static or G_DYNMP_LIST 
#				  if crymptyp = dynamic
# ARGUMENTS     : CFG_MODE crymptyp
# NOTES         : this proc uses some global variables (G_runcfg)
#                 to avoid copying with long configs
#################################################################

proc findprintcryptomap {CFG_MODE MP_LIST crymptyp} {

    global G_runcfg
    global ICRLF
    global CRLF
    global CRLFlen
    global G_CRYMP_LIST

    fetchcfg $CFG_MODE

    setcrlf

    # Remove all duplicate entries in the list and set search string
	# based on crypto map type
     if { $crymptyp == "static" } {	
         set crymp_list [ lsort -unique $G_CRYMP_LIST ]
		 set srchstr "crypto map"
	    } elseif {$crymptyp == "dynamic"} {
		 set crymp_list [ lsort -unique $MP_LIST ] 
		 set srchstr "crypto dynamic-map"
		}
  
    foreach crympname $crymp_list {
             # puts "Crypto map names > $crympname <"
             set i [ regexp -inline -indices "$srchstr $crympname " $G_runcfg ]
             if { "$i" != "" } {
                 set pos [ lindex [lindex $i 0 ] 0 ]
                } else {
                 set pos -1
                }
             if { $pos != -1 } {
                 #found the crypto map start line, now need to find the end line
                  set posend [ string first $ICRLF $G_runcfg [ expr $pos+15 ] ]
                    if { $posend != -1 } {
                      set crympparag [ string range $G_runcfg $pos $posend ]
		            # get dynamic crypto maps if type is static
		             if {$crymptyp == "static"} { 
	 			 findprintcryptomap $CFG_MODE [ checkintnames $crympparag end-1 " ipsec-isakmp dynamic " ] dynamic 
				}
                     # get ike profiles
                     findprintikepro $CFG_MODE [ checkintnames $crympparag end-1 "set isakmp-profile " ] "crypto isakmp profile"
		     findprintikepro $CFG_MODE [ checkintnames $crympparag end-1 "set ikev2-profile " ] "crypto ikev2 profile"	 		     
                     # get crypto acls
                     checkintcryacl $crympparag
		     # get transform set
		     findprintcryptotrans $CFG_MODE [ checkintnames $crympparag end-2 "set transform-set " ] 
                     # print crypto map config
                     puts $crympparag
                     puts "!"
                    }
                }    
       }
}


#-----------------------------------------------------------------


##################################################################
# PROCEDURE NAME: checkintcryacl
# AUTHOR        : Wayne Gatlin, U.S., wayne@razorcla.ws 
# USE           : this tcl procedure goes throught the given string
#                 as an argument and finds the names of Crypto ACLs 
# ARGUMENTS     : string to analyze
# NOTES         : this proc uses some global variables (G_runcfg)
#                 to avoid copying with long configs
#################################################################

proc checkintcryacl {args} {

    global G_runcfg
    global G_ACL_LIST
    global ICRLF
    global CRLF
    global CRLFlen
    global LOOPCOUNT
    set LC 0

    set cryaclgi1 [ string first "match address " $args 0 ]
   #loop through and find crypto acl names in the map
    while { $cryaclgi1 != -1} {
        #found one
        set cryaclcnt [ string first $CRLF $args $cryaclgi1 ]
         if { $cryaclcnt != -1 } {
            set cryaclline [ string range $args $cryaclgi1 $cryaclcnt ]
            set cryacllist [ split $cryaclline ]
            set cryacllistout [ lindex $cryacllist end-1]
            lappend G_ACL_LIST $cryacllistout
            #check for another
           set cryaclgi1 [ string first "match address " $args $cryaclcnt ] 
	 }
           incr LC
            #fail safe for endless looops
           if { $LC > $LOOPCOUNT } {
              puts "Loop count is $LC and global fail safe is $LOOPCOUNT exiting!!"
             break
          }
       }
 #puts "Crypto ACL list>$G_ACL_LIST<"
}

################################################################
# PROCEDURE NAME: findprintcryptotrans
# AUTHOR        : Wayne Gatlin, U.S.
# USE           : this tcl procedure goes throught the IOS
#                 device config file and selects only the part
#                 corresponding to the transform set 
#				  tied to a crypto map
# ARGUMENTS     :
# NOTES         : this proc uses some global variables (G_runcfg)
#                 to avoid copying with long configs
#################################################################

proc findprintcryptotrans {CFG_MODE condvar} {

    global G_runcfg
    global ICRLF
    global CRLF
    global CRLFlen

    fetchcfg $CFG_MODE

    puts "!"
    foreach crytransformset [ regexp -all -inline -line "crypto ipsec transform-set $condvar \.* $CRLF" $G_runcfg ] {
    puts $crytransformset }
    puts "!"

}

################################################################
# PROCEDURE NAME: findprintikepro
# AUTHOR        : Wayne Gatlin, U.S., wayne@razorcla.ws 
# USE           : this tcl procedure goes throught the IOS
#                 device config file and selects only the part
#                 corresponding to crypto isakmp profile based on
#		  		  the global list G_CRYIKE_LIST
# ARGUMENTS     :
# NOTES         : this proc uses some global variables (G_runcfg)
#                 to avoid copying with long configs
#################################################################

proc findprintikepro {CFG_MODE IKE_LIST srchstr} {

    global G_runcfg
    global ICRLF
    global CRLF
    global CRLFlen

    fetchcfg $CFG_MODE

    setcrlf

    #Remove all duplicate entries in the list
    set ikepro_list [ lsort -unique $IKE_LIST ]
	 
    #set srchstr "crypto isakmp profile"
    if { $srchstr == "crypto ikev2 profile" } { 
	 set keytype "crypto ikev2 keyring"
        } else {
         set keytype "crypto keyring"
        }
		
    foreach ikeproname $ikepro_list {
             # puts "Isakmp profle names > $ikeproname <"
             set i [ regexp -inline -indices "$srchstr $ikeproname$CRLF" $G_runcfg ]
             if { "$i" != "" } {
                 set pos [ lindex [lindex $i 0 ] 0 ]
                } else {
                 set pos -1
                }
             if { $pos != -1 } {
                 #found the Isakmp profle start line, now need to find the end line
                 set posend [ string first "$srchstr " $G_runcfg [ expr $pos+15 ] ]
                     if { $posend == -1 } {
		              set posend [ string first $ICRLF $G_runcfg [ expr $pos+15 ] ]
			     } 
                      if { $posend != -1 } {
                      set ikeproparag [ string range $G_runcfg $pos [ expr $posend-$CRLFlen ] ]
                     
                     # get crypto keyring
                     findprintcrykey $CFG_MODE [ checkintnames $ikeproparag end-1 "keyring " ] $keytype
		     # get isakmp client configuration
                     findprintikeclient $CFG_MODE [ checkintnames $ikeproparag end-1 "match identity group " ]

                     # print crypto map config
                     puts $ikeproparag
                     puts "!"
                    }
                }
       }
}

#-----------------------------------------------------------------

################################################################
# PROCEDURE NAME: findprintikeclient
# AUTHOR        : Wayne Gatlin, U.S., wayne@razorcla.ws 
# USE           : this tcl procedure goes throught the IOS
#                 device config file and selects only the part
#                 corresponding to crypto isakmp client configuration
# ARGUMENTS     :
# NOTES         : this proc uses some global variables (G_runcfg)
#                 to avoid copying with long configs
#################################################################

proc findprintikeclient {CFG_MODE IKE_LIST} {

    global G_runcfg
    global ICRLF
    global CRLF
    global CRLFlen

    fetchcfg $CFG_MODE

    setcrlf

    #Remove all duplicate entries in the list
    set ikeclient_list [ lsort -unique $IKE_LIST ]
	 
    set srchstr "crypto isakmp client configuration group"
		
    foreach ikeclientname $ikeclient_list {
             # puts "Isakmp profle names > $ikeclientname <"
             set i [ regexp -inline -indices "$srchstr $ikeclientname$CRLF" $G_runcfg ]
             if { "$i" != "" } {
                 set pos [ lindex [lindex $i 0 ] 0 ]
                } else {
                 set pos -1
                }
             if { $pos != -1 } {
                 #found the Isakmp profle start line, now need to find the end line
                 set posend [ string first "$srchstr " $G_runcfg [ expr $pos+15 ] ]
                     if { $posend == -1 } {
		       set posend [ string first $ICRLF $G_runcfg [ expr $pos+15 ] ]
			     } 

                      if { $posend != -1 } {
                      set ikeclientparag [ string range $G_runcfg $pos [ expr $posend-$CRLFlen ] ]
			
			# get dhcp pool
                        findprintdhcp $CFG_MODE [ checkintcrydhcp $ikeclientparag ]

                     # print crypto map config
                     puts $ikeclientparag
                     puts "!"
                    }
                }
       }
}

#-----------------------------------------------------------------


################################################################
# PROCEDURE NAME: findprintcrykey
# AUTHOR        : Wayne Gatlin, U.S., wayne@razorcla.ws 
# USE           : this tcl procedure goes throught the IOS
#                 device config file and selects only the part
#                 corresponding to crypto keyring
# ARGUMENTS     :
# NOTES         : this proc uses some global variables (G_runcfg)
#                 to avoid copying with long configs
#################################################################

proc findprintcrykey {CFG_MODE KEY_LIST srchstr} {

    global G_runcfg
    global ICRLF
    global CRLF
    global CRLFlen


    fetchcfg $CFG_MODE

    setcrlf

    #Remove all duplicate entries in the list
    set crykey_list [ lsort -unique $KEY_LIST ]

    foreach crykeyname $crykey_list {
  	     if { $srchstr == "crypto ikev2 keyring" } {
         	 set i [ regexp -inline -indices "$srchstr $crykeyname$CRLF" $G_runcfg ]
             } else {
         	  set i [ regexp -inline -indices "$srchstr $crykeyname  $CRLF" $G_runcfg ]
       	     }
             #set i [ regexp -inline -indices "$srchstr $crykeyname  $CRLF" $G_runcfg ]
             if { "$i" != "" } {
                 set pos [ lindex [lindex $i 0 ] 0 ]
                } else {
                 set pos -1
                }
             if { $pos != -1 } {
                 #found the crypto keyring start line, now need to find the end line
                 set posend [ string first "$srchstr " $G_runcfg [ expr $pos+15 ] ]
                      if { $posend == -1 } {
                          set posend [ string first $ICRLF $G_runcfg [ expr $pos+15 ] ]
			 }
        
                     if { $posend != -1 } {
                      set crykeyparag [ string range $G_runcfg $pos [ expr $posend-$CRLFlen ] ]
                  
                     # print crypto keyring config
                     puts $crykeyparag
                     puts "!"
                    }
                }
       }
}

#-----------------------------------------------------------------


################################################################
# PROCEDURE NAME: findprintvrfcrykey
# AUTHOR        : Wayne Gatlin, U.S., wayne@razorcla.ws 
# USE           : this tcl procedure goes throught the IOS
#                 device config file and selects only the part
#                 corresponding to a crypto keyring linked to a VRF
# ARGUMENTS     :
# NOTES         : this proc uses some global variables (G_runcfg)
#                 to avoid copying with long configs
#################################################################

proc findprintvrfcrykey {CFG_MODE condvar} {

    global G_runcfg
    global ICRLF
    global CRLF
    global CRLFlen


    fetchcfg $CFG_MODE

    setcrlf
    
	set srchstr "crypto keyring"
    foreach crykeyname [ regexp -all -inline -line -indices "$srchstr \.* vrf $condvar\$" $G_runcfg ] {
             if { "$crykeyname" != "" } {
                 set pos [ lindex [lindex $crykeyname 0 ] 0 ]
                } else {
                 set pos -1
                }
             if { $pos != -1 } {
                 #found the crypto keyring start line, now need to find the end line
                 set posend [ string first "$srchstr " $G_runcfg [ expr $pos+15 ] ]
                      if { $posend == -1 } {
                      set posend [ string first $ICRLF $G_runcfg [ expr $pos+15 ] ]
				        }
        
                     if { $posend != -1 } {
                      set crykeyparag [ string range $G_runcfg $pos [ expr $posend-$CRLFlen ] ]

                     # print crypto keyring config
                     puts $crykeyparag
                     puts "!"
                    }
                }
       }
}

#-----------------------------------------------------------------

################################################################
# PROCEDURE NAME: findprintdhcp
# AUTHOR        : Wayne Gatlin, U.S., wayne@razorcla.ws 
# USE           : this tcl procedure goes throught the IOS
#                 device config file and selects only the part
#                 corresponding to dhcp pools with given name
# ARGUMENTS     :
# NOTES         : this proc uses some global variables (G_runcfg)
#                 to avoid copying with long configs
#################################################################

proc findprintdhcp {CFG_MODE DHCP_LIST} {

    global G_runcfg
    global ICRLF
    global CRLF
    global CRLFlen

    fetchcfg $CFG_MODE
    
	set srchstr "ip local pool"
	set dhcppl_list [ lsort -unique $DHCP_LIST ]

  foreach dhcpplname $dhcppl_list {
   if { "$dhcpplname" != "" } {
      foreach dhcppool [ regexp -all -inline -line "$srchstr $dhcpplname \.*" $G_runcfg ] {
       puts $dhcppool }
      puts "!"
	 }
    }
}
#-----------------------------------------------------------------

################################################################
# PROCEDURE NAME: findprintstaticnat
# AUTHOR        : Wayne Gatlin, U.S., wayne@razorcla.ws 
# USE           : this tcl procedure goes throught the IOS
#                 device config file and selects only the part
#                 corresponding to static nats with given VRF name
# ARGUMENTS     :
# NOTES         : this proc uses some global variables (G_runcfg)
#                 to avoid copying with long configs
#################################################################

proc findprintstaticnat {CFG_MODE condvar} {

    global G_runcfg

    fetchcfg $CFG_MODE

    puts "!"
    foreach staticnat [ regexp -all -inline -line "ip nat \.* source static \.* vrf $condvar" $G_runcfg ] {
    puts $staticnat }
    puts "!"

}

#-----------------------------------------------------------------

################################################################
# PROCEDURE NAME: findprintdynnat
# AUTHOR        : Wayne Gatlin, U.S., wayne@razorcla.ws 
# USE           : this tcl procedure goes throught the IOS
#                 device config file and selects only the part
#                 corresponding to dynamamic nats with given VRF name
#		  		  and prints the nat and pool config
# ARGUMENTS     : 
# NOTES         : this proc uses some global variables (G_runcfg)
#                 to avoid copying with long configs
#################################################################

proc findprintdynnat {CFG_MODE condvar} {

    global G_runcfg
    global G_ACL_LIST
    global G_RMAP_LIST
    global ICRLF
    global CRLF
    global CRLFlen


    set dynamicnatacl 0
    set dynamicnatpool 0
    set dynamicnatrm 0
    set dynamicnatpoolcfg ""

    fetchcfg $CFG_MODE

    puts "!"
	foreach dynamicnat [ regexp -all -inline -line "ip nat \.* source list \.* pool \.* vrf $condvar$|ip nat \.* source list \.* pool \.* vrf $condvar overload|ip nat \.* source route-map \.* pool \.* vrf $condvar$|ip nat \.* source route-map \.* pool \.* vrf $condvar overload" $G_runcfg ] {
    puts $dynamicnat
	set splitdynamicnat [split $dynamicnat " "]
    	foreach dynamicnatvar $splitdynamicnat {
		  #get nat acl names and append them to the global acl list
		   if { $dynamicnatvar == "list" } {
                       incr dynamicnatacl 
                    }
			if { $dynamicnatacl == "1" } {
			  if { $dynamicnatvar != "list" } {
                		lappend G_ACL_LIST $dynamicnatvar
				incr dynamicnatacl
			    } 
			 }

			#get route-map names and append them to the global route-map list
			if { $dynamicnatvar == "route-map" } {
			   incr dynamicnatrm
                	  }
			if { $dynamicnatrm == "1" } {
			  if { $dynamicnatvar != "route-map" } {
			     lappend G_RMAP_LIST $dynamicnatvar
				 incr dynamicnatrm
			  } 
			}
                    
			#get nat pool names and print pool config
			if { $dynamicnatvar == "pool" } {
                 	  incr dynamicnatpool
               		 }
			if { $dynamicnatpool == "1" } {
			  if { $dynamicnatvar != "pool" } {
			   regexp -line "ip nat pool $dynamicnatvar \.*" $G_runcfg dynamicnatpoolcfg
                           incr dynamicnatpool
			  } 
			}
	     }
    puts $dynamicnatpoolcfg
    puts "!"
    }
}


#-----------------------------------------------------------------


################################################################
# PROCEDURE NAME: findprintacls
# AUTHOR        : D.Koncic, EDS Switzerland
# USE           : this tcl procedure goes throught the IOS
#                 device config file and selects only the part
#                 corresponding to ACLs with names found in the
#                 global var G_ACL_LIST
# ARGUMENTS     : 
# NOTES         : this proc uses some global variables (G_runcfg)
#                 to avoid copying with long configs
#################################################################

proc findprintacls {CFG_MODE } {

    global G_runcfg
    global ICRLF
    global CRLF
    global CRLFlen
    global G_ACL_LIST

    fetchcfg $CFG_MODE

    setcrlf

    #Remove all duplicate entries in the list
    set acl_list [ lsort -unique $G_ACL_LIST ]

    foreach aclname $acl_list {
         #Determine if the list element is a number or a word
         if { [string is integer $aclname] == 1 } {
             #acl name is a number so should find an old style acl
             set i_start [ string first "access-list $aclname " $G_runcfg 0 ]
             if { $i_start != -1} {
                 # found the acl paragraph...
                 set i_end [ string last "access-list $aclname " $G_runcfg ]
                 set i_end2 [ string first $CRLF $G_runcfg $i_end ]
                 set aclparag [ string range $G_runcfg $i_start $i_end2 ]
                 puts $aclparag
                 puts "!"
                }
            } else {
             # acl name is some form of a word so it is new acl type
             set i [ regexp -inline -indices "ip access-list \[a-z]* $aclname$CRLF" $G_runcfg ]
             if { "$i" != "" } {
                 set pos [ lindex [lindex $i 0 ] 0 ]
                } else {
                 set pos -1
                }
             if { $pos != -1 } {
                 #found the acl start line, now need to find the end line
                 set posend [ string first "ip access-list " $G_runcfg [ expr $pos+15 ] ]
               if { $posend == -1 } {
		 set posend [ string first $ICRLF $G_runcfg [ expr $pos+15 ] ]
		           } 
                 if { $posend != -1 } {
                         set aclparag [ string range $G_runcfg $pos [ expr $posend-$CRLFlen ] ]
                        
                     puts $aclparag
                     puts "!"
                    }
                }    
            }
       }
}

#-----------------------------------------------------------------


################################################################
# PROCEDURE NAME: getvrfstat
# AUTHOR        : D.Koncic, EDS Switzerland
# USE           : this tcl procedure goes throught the IOS
#                 device config file and selects only the part
#                 corresponding to statics with given VRF name
# ARGUMENTS     : CFG_MODE - determines if running, startup or
#                            file name of the local disk/flash
#                 condvar  - VRF name
# NOTES         : this proc uses some global variables (G_runcfg)
#                 to avoid copying with long configs
#################################################################

proc getvrfstat {CFG_MODE condvar} {

    global G_runcfg
    global ICRLF
    global CRLF
    global CRLFlen

    fetchcfg $CFG_MODE

    setcrlf
    puts "!"

            # special attention for the static routes due to no ! signs to delimit
            # from other static routes
            set i_start [ string first "ip route vrf $condvar " $G_runcfg 0 ]
            if { $i_start != -1} {
                # found the statics paragraph...
                set i_end [ string last "ip route vrf $condvar " $G_runcfg ]
                set i_end2 [ string first $CRLF $G_runcfg $i_end ]
                set stat_parag [ string range $G_runcfg $i_start $i_end2 ]
                puts $stat_parag
                puts "!"
             }
}

#-----------------------------------------------------------------


#################################################################
# PROCEDURE NAME: getvrfbgp_r_e                               
# AUTHOR        : D.Koncic, EDS Switzerland
# USE           : this tcl procedure goes throught the IOS 
#                 device config file and selects only those parts  
#                 corresponding to bgp part for given VRF name
#                 Using variable RPROTOCOL it will work for rip, eigrp
# ARGUMENTS     : CFG_MODE - determines if running, startup or
#                            file name of the local disk/flash
#                 condvar  - VRF name
# NOTES         : this proc uses some global variables (G_runcfg)
#                 to avoid copying with long configs
#################################################################


proc getvrfbgp_r_e {CFG_MODE condvar RPROTOCOL} { 

    global G_runcfg
    global ICRLF
    global CRLF
    global CRLFlen

    fetchcfg $CFG_MODE

    setcrlf

    # init variables for the loop
    set i [ string first "router $RPROTOCOL" $G_runcfg 0 ]
    puts "!"

    if { $i != -1} {
        # search for the occurance of "!" as the last in the line
        set newi [ string first $ICRLF $G_runcfg $i ]

        # handle the end of the string (-1 return code)
        if { $newi != -1 } {

           # cut out one paragraph between the two !s
           set parag [ string range $G_runcfg $i $newi ]

           # print the paragraph out with 'router xxx', this is global part!!!
#           puts $parag

           set i [ string first "address-family ipv4 vrf $condvar$CRLF" $G_runcfg $newi ]
           # print the paragraph out if including the search string, vrf name
           if { $i != -1} {
               set check [ string first "router " $G_runcfg $newi ]
               if { $check == -1 || $check > $i } {
                   #address-family is of the current routing protocol and exists
                   # search for the occurance of "!" as the last in the line
                   set newi [ string first $ICRLF $G_runcfg $i ]

                   # handle the end of the string (-1 return code)
                   if { $newi != -1 } {
 
                       # print the paragraph out with 'router xxx', this is global part!!!
                       puts $parag

                       # cut out one paragraph between the two !s
                       set parag [ string range $G_runcfg $i $newi ]
       
                       # this is the paragraph so just print it out
                       puts $parag
                       #now need to check for route-maps, distrib-lists, pref-lists, acls
                       switch $RPROTOCOL {
                          bgp   { searchbgpparag $parag }

                          rip   { searchripparag $parag }
  
                          eigrp { searcheigrpparag $parag }
                         }
                      }
                  }
              }
           }
      }
}

#------------------------------------------------------------------


#################################################################
# PROCEDURE NAME: searchbgpparag
# AUTHOR        : D.Koncic, EDS Switzerland
# USE           : this tcl procedure goes throught the bgp paragraph
#                 and scans for route-maps or ACLs
# ARGUMENTS     : args - ospf paragraph string
# NOTES         : this proc uses some global variables (G_runcfg)
#                 to avoid copying with long configs
#################################################################

proc searchbgpparag { args } {

    global G_runcfg
    global ICRLF
    global CRLF
    global CRLFlen
    global G_RMAP_LIST
    global G_ACL_LIST
    global G_PREFX_LIST

    set par_records [ split [lindex $args 0 ] $CRLF ]
    foreach parrec $par_records {
        #search for distribute-list line
        set pos [ lsearch $parrec "distribute-list" ]
        if { $pos != -1 } {
            #it is distribution-list with ACL or route-map
            set dlistacl [ lindex $parrec [ expr $pos+1 ] ]
            lappend G_ACL_LIST $dlistacl
           } else {
            # it could be a line with route-map
            set pos [ lsearch $parrec "route-map" ]
            if { $pos != -1 } {
                #found a route-map keyword, next one is the name
                set redismap [ lindex $parrec [ expr $pos+1 ] ]
                lappend G_RMAP_LIST $redismap
               } else {
                # it could be a line with pref-list
                set pos [ lsearch $parrec "prefix-list" ]
                if { $pos != -1 } {
                    #found a prefix-list keyword, next one is the name
                    set preflist [ lindex $parrec [ expr $pos+1 ] ]
                    lappend G_PREFX_LIST $preflist
                   }
               }
           }
       }
}

#------------------------------------------------------------------


################################################################
# PROCEDURE NAME: searchripparag
# AUTHOR        : D.Koncic, EDS Switzerland
# USE           : this tcl procedure goes throught the rip paragraph
#                 and scans for route-maps or ACLs
# ARGUMENTS     : args - ospf paragraph string
# NOTES         : this proc uses some global variables (G_runcfg)
#                 to avoid copying with long configs
#################################################################

proc searchripparag { args } {

    global G_runcfg
    global ICRLF
    global CRLF
    global CRLFlen
    global G_RMAP_LIST
    global G_ACL_LIST
    global G_PREFX_LIST

    set par_records [ split [lindex $args 0 ] $CRLF ]
    foreach parrec $par_records {
        #search for distribute-list line
        if { [ lindex  $parrec 0 ] == "distribute-list" } {
            #it is distribution-list with ACL
            set dlistacl [ lindex $parrec 1 ]
            lappend G_ACL_LIST $dlistacl
           } else {
            #it could be redistribution line
            if { [ lindex  $parrec 0 ] == "redistribute" } {
                #yes it is redis line
                set pos [ lsearch $parrec "route-map" ]
                if { $pos != -1 } {
                    #found a route-map keyword, next one is the name
                    set redismap [ lindex $parrec [ expr $pos+1 ] ]
                    lappend G_RMAP_LIST $redismap
                   }
               }
           }
       }
}

#------------------------------------------------------------------


#################################################################
# PROCEDURE NAME: searcheigrpparag
# AUTHOR        : D.Koncic, EDS Switzerland
# USE           : this tcl procedure goes throught the eigrp paragraph
#                 and scans for route-maps or ACLs
# ARGUMENTS     : args - ospf paragraph string
# NOTES         : this proc uses some global variables (G_runcfg)
#                 to avoid copying with long configs
#################################################################

proc searcheigrpparag { args } {

    global G_runcfg
    global ICRLF
    global CRLF
    global CRLFlen
    global G_RMAP_LIST
    global G_ACL_LIST
    global G_PREFX_LIST

    set par_records [ split [lindex $args 0 ] $CRLF ]
    foreach parrec $par_records {
        #search for distribute-list line
        if { [ lindex  $parrec 0 ] == "distribute-list" } {
            if { [ lindex  $parrec 1 ] == "route-map" } {
                #it is distribution-list with r-map
                set dlistrmap [ lindex $parrec 2 ]
                lappend G_RMAP_LIST $dlistrmap
               } else {
                #it is distribution-list with ACL
                set dlistacl [ lindex $parrec 1 ]
                lappend G_ACL_LIST $dlistacl
               }
           } else {
            #if not distribution list, it could be redistribution line
            if { [ lindex  $parrec 0 ] == "redistribute" } {
                #it is redis line
                set pos [ lsearch $parrec "route-map" ]
                if { $pos != -1 } {
                    #found a route-map keyword, next one is the name
                    set redismap [ lindex $parrec [ expr $pos+1 ] ]
                    lappend G_RMAP_LIST $redismap
                   }
               }
           }
       }
}

#------------------------------------------------------------------



################################################################
# PROCEDURE NAME: getvrfdef
# AUTHOR        : D.Koncic, EDS Switzerland
# USE           : this tcl procedure goes throught the IOS
#                 device config file and selects only those parts
#                 corresponding to definition part for given VRF name
# ARGUMENTS     : CFG_MODE - determines if running, startup or
#                            file name of the local disk/flash
#                 condvar  - VRF name
# NOTES         : this proc uses some global variables (G_runcfg)
#                 to avoid copying with long configs
#################################################################

proc getvrfdef {CFG_MODE condvar} {

    global G_runcfg
    global G_RMAP_LIST
    global G_ACL_LIST
    global G_PREFX_LIST
    global ICRLF
    global CRLF
    global CRLFlen

    fetchcfg $CFG_MODE

    setcrlf

    puts "!"

           set i [ string first "ip vrf $condvar$CRLF" $G_runcfg 0 ]
           # print the paragraph out if including the search string, vrf name
           if { $i != -1} {

               # search for the occurance of "!" as the last in the line
               set newi [ string first $ICRLF $G_runcfg $i ]

               # handle the end of the string (-1 return code)
               if { $newi != -1 } {

                    # cut out one paragraph between the two !s
                    set parag [ string range $G_runcfg $i $newi ]

                    # this is the paragraph so just print it out
                    puts $parag

                    #Find if there are import/export maps
                    set mapi1 [ string first "port map " $parag 0 ]
                    if { $mapi1 != -1} {
                       #found one map
                       set crlfi [ string first $CRLF $parag $mapi1 ]
                       if { $crlfi != -1 } {
                          set mapline [ string range $parag $mapi1 $crlfi ]
                          set maplist [ split $mapline ]
                          set maplistout [ lindex $maplist end-1 ]
                          lappend G_RMAP_LIST $maplistout   
                         }
                       set mapi1 [ string first "port map " $parag $crlfi ]
                       if { $mapi1 != -1} { 
                          #found onether map
                          set crlfi [ string first $CRLF $parag $mapi1 ]
                          if { $crlfi != -1 } {
                             set mapline [ string range $parag $mapi1 $crlfi ]       
                             set maplist [ split $mapline ]
                             set maplistout2 [ lindex $maplist end-1 ] 
                             lappend G_RMAP_LIST $maplistout2
                            }
                          }
                     }
                  }
              }
}

#------------------------------------------------------------------


#################################################################
# PROCEDURE NAME: findprintprefls
# AUTHOR        : D.Koncic, EDS Switzerland
# USE           : this tcl procedure finds all PREFX lists
#                 and prints it out,
# ARGUMENTS     : CFG_MODE
# NOTES         : this proc uses some global variables (G_runcfg)
#                 to avoid copying with long configs
#################################################################

proc findprintprefls {CFG_MODE } {    

    global G_runcfg
    global G_RMAP_LIST
    global G_ACL_LIST
    global G_PREFX_LIST
    global ICRLF
    global CRLF
    global CRLFlen

    fetchcfg $CFG_MODE

    setcrlf

    puts "!"
    
    set i 0

    #Remove all duplicate entries in the list
    set prefl_list [ lsort -unique $G_PREFX_LIST ]

   foreach preflname $prefl_list {
      
        set i [ string first "ip prefix-list $preflname " $G_runcfg 0 ]
        # continue if prefl exists at all
        if { $i != -1} {
            set i_end [ string last "ip prefix-list $preflname " $G_runcfg ]
            set i_end2 [ string first $CRLF $G_runcfg $i_end ]
            set prefparag [ string range $G_runcfg $i $i_end2 ]
            puts $prefparag
            puts "!"
           }
       }

}

#------------------------------------------------------------------


#################################################################
# PROCEDURE NAME: findprintrmaps
# AUTHOR        : D.Koncic, EDS Switzerland
# USE           : this tcl procedure finds a route map by name
#                 and prints it out
# ARGUMENTS     : rmapname
# NOTES         : this proc uses some global variables (G_runcfg)
#                 to avoid copying with long configs
#################################################################

proc findprintrmaps { } {

    global G_runcfg
    global G_RMAP_LIST
    global G_ACL_LIST
    global G_PREFX_LIST
    global ICRLF
    global CRLF
    global CRLFlen
    global LOOPCOUNT
    set LC 0

#    fetchcfg $CFG_MODE

    setcrlf

    #Remove all duplicate entries in the list
    set rmap_list [ lsort -unique $G_RMAP_LIST ]

 foreach rmapname $rmap_list { 
    set rmap_loc1 [ string first "\nroute-map $rmapname" $G_runcfg 0 ]
    if { $rmap_loc1 != -1 } {
        #route map found, now need to find the last element of the same map
        set rmap_loc11 [ string last "\nroute-map $rmapname" $G_runcfg ]
        if { $rmap_loc11  != -1 } {
            set rmap_loc2 [ string first $ICRLF $G_runcfg $rmap_loc11 ]
            set rmap_para [ string range $G_runcfg $rmap_loc1 $rmap_loc2 ]
            puts $rmap_para
           } else {
            set rmap_loc2 [ string first $ICRLF $G_runcfg $rmap_loc1 ]
            set rmap_para [ string range $G_runcfg $rmap_loc1 $rmap_loc2 ]
            puts $rmap_para
           }
        
        # Now route maps need to be searched to find ACLs and PRFXLISTs...
        # get the length of the rmap_para
        set rmapparlen [ string length $rmap_para ]

        # init variables for the loop
        set i 0
        set newi 0
        set crlfi 0

        puts "!"
        # 
        while {$i < $rmapparlen && $newi > -1} {
               # search for the occurances of "match ip address"
               set newi [ string first "match ip address" $rmap_para $i ]

               # handle the end of the para string (-1 return code)
               if { $newi != -1 } {
                   #found one match line
                   set crlfi [ string first $CRLF $rmap_para $newi ]
                   if { $crlfi != -1 } {
                       set matchline [ string range $rmap_para $newi $crlfi ]
                       set matchlist [ split $matchline ]
                       set matclilen [ llength $matchlist ]
                       if { $matclilen == 5 } {
                           #match is with ACL
                           set matchlistout [ lindex $matchlist 3 ]
                           lappend G_ACL_LIST $matchlistout
                          } else {
                           if { $matclilen == 6 } {
                               #match is with prefix list
                               set matchlistout [ lindex $matchlist 4 ]
                               lappend G_PREFX_LIST $matchlistout
                              }
                          }
                      }
                  }
               # move the pointers
               set i $crlfi 
                incr LC
                 #fail safe for endless looops
                 if { $LC > $LOOPCOUNT } {
                  puts "Loop count is $LC and global fail safe is $LOOPCOUNT exiting!!"
                 break
                } 
              }
       }
  }
#puts ">$G_ACL_LIST"
#puts ">>$G_PREFX_LIST" 
}

#------------------------------------------------------------------


#################################################################
# PROCEDURE NAME: getvrfospf                               
# AUTHOR        : D.Koncic, EDS Switzerland
# USE           : this tcl procedure goes throught the IOS 
#                 device config file and selects only those parts  
#                 corresponding to ospf of given VRF name
# ARGUMENTS     : CFG_MODE - determines if running, startup or
#                            file name of the local disk/flash
#                 condvar  - VRF name
# NOTES         : this proc uses some global variables (G_runcfg)
#                 to avoid copying with long configs
#################################################################

proc getvrfospf {CFG_MODE condvar} {

    global G_runcfg
    global ICRLF
    global CRLF
    global CRLFlen

    fetchcfg $CFG_MODE

    setcrlf

    # init variables for the loop
    set pos [ regexp -inline -indices "router ospf \[0-9]* vrf $condvar$CRLF" $G_runcfg ]
    if { "$pos" != "" } {
        set i [ lindex [lindex $pos 0 ] 0 ]
      } else {
        set i -1
      }

    if { $i != -1} {

      puts "!"
      # search for the occurance of "!" as the last in the line
      set newi [ string first $ICRLF $G_runcfg $i ]
      # handle the end of the string (-1 return code)
      if { $newi != -1 } {

         # cut out one paragraph between the two !s
         set parag [ string range $G_runcfg $i $newi ]

         # print the paragraph out with 'router ospf'
         puts $parag
         #Now serach for distrib-lists, route-maps etc
         searchospfprg $parag
       }
    }
}

#------------------------------------------------------------------


#################################################################
# PROCEDURE NAME: searchospfprg 
# AUTHOR        : D.Koncic, EDS Switzerland
# USE           : this tcl procedure goes throught the ospf paragraph
#                 and scans for route-maps or ACLs
# ARGUMENTS     : args - ospf paragraph string
# NOTES         : this proc uses some global variables (G_runcfg)
#                 to avoid copying with long configs
#################################################################

proc searchospfprg { args } {

    global G_runcfg
    global ICRLF
    global CRLF
    global CRLFlen
    global G_RMAP_LIST
    global G_ACL_LIST
    global G_PREFX_LIST

    set par_records [ split [lindex $args 0 ] $CRLF ]
    foreach parrec $par_records {
        #search for distribute-list line
        if { [ lindex  $parrec 0 ] == "distribute-list" } {
            if { [llength $parrec ] == 4 } {
                #it is distribution-list with r-map
                set dlistrmap [ lindex $parrec 2 ] 
                lappend G_RMAP_LIST $dlistrmap
               } else {
                #it is distribution-list with ACL
                set dlistacl [ lindex $parrec 1 ]
                lappend G_ACL_LIST $dlistacl
               }
           } else {
            #if not distribution list, it could be redistribution line
            if { [ lindex  $parrec 0 ] == "redistribute" } {
                #yes it is redis line
                set pos [ lsearch $parrec "route-map" ]
                if { $pos != -1 } {
                    #found a route-map keyword, next one is the name
                    set redismap [ lindex $parrec [ expr $pos+1 ] ]
                    lappend G_RMAP_LIST $redismap
                   }
               }
           }
       }
}

#------------------------------------------------------------------

#################################################################
# PROCEDURE NAME: cmdswitch
# AUTHOR        : D.Koncic, EDS Switzerland
# USE           : this tcl procedure calls required procedures,
#                 depending on te main command arguments or prints
#                 a short help message
# ARGUMENTS     : CFG_MODE - determines if running, startup or
#                 FRST,SEC,TRD - 3 command args
# NOTES         : 
#################################################################

proc cmdswitch { CFG_MODE FRST SEC TRD } {

 if { $CFG_MODE == "help" } {
   puts "Usage: vsh <config_source> <config_area> vrf <vrf_name>"
   puts "   config_source: running|startup|config or filename"
   puts "   config_area  : all|bgp|ospf|rip|eigrp|static|interface|def|routing|crypto|nat"
   puts "   vrf_name     : <name of the VRF wished to display>"
   puts " "
   puts "Version: 1.0"
   puts "Author : D.Koncic (davor.koncic@eds.com), EDS, an HP company"
   puts "NOTE: This progrsm is protected by copyright law. Any unauthorised use"
   puts "      or distribution is not permitted."
  } else {
   switch $TRD      {

      all    { 
          # This is for future development, to show info for all VRF's
          switch "$FRST $SEC" {

               "all vrf" { puts "ALL VRF ALL" }

               "bgp vrf" { puts "BGP VRF ALL" }

               "ospf vrf" { puts "OSPF VRF ALL" }

               "interface vrf" { puts "INT VRF ALL" }

               "rip vrf" { puts "RIP VRF ALL" }

               "eigrp vrf" { puts "EIGRP VRF ALL" }

               "static vrf" { puts "STAT VRF ALL" }

               "def vrf" { puts "DEF VRF ALL" }

               "rmap vrf" { puts "RMAP VRF ALL" }   

               "preflist vrf" { puts "PREFL VRF ALL" }   

               default { puts "ERROR -> dksh: wrong set of arguments or spelling" } 
               }
          }


      global  {
          # This is for future development, to show info for global parts
          switch "$FRST $SEC" {

               "all vrf" { puts "ALL VRF GLOB" }

               "bgp vrf" { puts "BGP VRF GLOB" }

               "ospf vrf" { puts "OSPF VRF GLOB" }   

               "interface vrf" { puts "INT VRF GLOB" }   

               "rip vrf" { puts "RIP VRF GLOB" }   

               "eigrp vrf" { puts "EIGRP VRF GLOB" }      

               "static vrf" { puts "STAT VRF GLOB" }   

               "def vrf" { puts "DEF VRF GLOB" }

               "rmap vrf" { puts "RMAP VRF GLOB" }         

               "preflist vrf" { puts "PREFL VRF GLOB" }         

               default { puts "ERROR -> dksh: wrong set of arguments or spelling" }
               }
          }

      default  {
          switch "$FRST $SEC" {

               "all vrf" { 
                           #puts "ALL VRF xxx" 
                           getvrfdef $CFG_MODE $TRD
                           getvrfint $CFG_MODE $TRD

                           getvrfbgp_r_e $CFG_MODE $TRD eigrp  
                           getvrfospf $CFG_MODE $TRD
                           getvrfbgp_r_e $CFG_MODE $TRD rip
                           getvrfbgp_r_e $CFG_MODE $TRD bgp
                           getvrfstat $CFG_MODE $TRD
			  
			   findprintcryptomap $CFG_MODE "" static
			   findprintvrfcrykey $CFG_MODE $TRD

			   findprintstaticnat $CFG_MODE $TRD
			   findprintdynnat $CFG_MODE $TRD
 
                           findprintrmaps
                           findprintacls $CFG_MODE
                           findprintprefls $CFG_MODE
                   
                         }

               "bgp vrf" { 
                           #puts "BGP VRF xxx"
                           getvrfbgp_r_e $CFG_MODE $TRD bgp
                           findprintrmaps
                           findprintacls $CFG_MODE
                           findprintprefls $CFG_MODE
                         }

               "ospf vrf" { 
                           #puts "OSPF VRF xxx"
                           getvrfospf $CFG_MODE $TRD
                           findprintrmaps
                           findprintacls $CFG_MODE
                           findprintprefls $CFG_MODE
                          }   

               "interface vrf" {
                           #puts "INT VRF xxx"
                           getvrfint $CFG_MODE $TRD
                           findprintacls $CFG_MODE
                          }   

               "rip vrf"  {
                           #puts "RIP VRF xxx"
                           getvrfbgp_r_e $CFG_MODE $TRD rip
                           findprintrmaps
                           findprintacls $CFG_MODE
                           findprintprefls $CFG_MODE
                          }   

               "eigrp vrf" {
                           #puts "EIGRP VRF xxx"
                           getvrfbgp_r_e $CFG_MODE $TRD eigrp
                           findprintrmaps
                           findprintacls $CFG_MODE
                           findprintprefls $CFG_MODE
                           }      

               "static vrf" { 
                             #puts "STAT VRF xxx"
                             getvrfstat $CFG_MODE $TRD
                            }   

               "routing vrf" {
                             #puts "ROUT VRF xxx"
                             getvrfospf $CFG_MODE $TRD
                             getvrfbgp_r_e $CFG_MODE $TRD rip
                             getvrfbgp_r_e $CFG_MODE $TRD eigrp
                             getvrfbgp_r_e $CFG_MODE $TRD bgp
                             getvrfstat $CFG_MODE $TRD
                             findprintrmaps
                             findprintacls $CFG_MODE
                             findprintprefls $CFG_MODE
                             }
		"nat vrf" {
                           #puts "NAT VRF xxx"
                           getvrfint $CFG_MODE $TRD
                           findprintstaticnat $CFG_MODE $TRD
                           findprintdynnat $CFG_MODE $TRD
                           findprintrmaps
                           findprintacls $CFG_MODE
			  }
              "crypto vrf" {
                           #puts "CRYPTO VRF xxx"
                           getvrfint $CFG_MODE $TRD
                           findprintcryptomap $CFG_MODE "" static
			   findprintvrfcrykey $CFG_MODE $TRD
                           findprintacls $CFG_MODE
			   }
               "def vrf" { 
                           #puts "DEF VRF xxx"
                           getvrfdef $CFG_MODE $TRD
                           findprintrmaps
                           findprintacls $CFG_MODE
                           findprintprefls $CFG_MODE
                         }

               "rmap vrf" { puts "RMAP VRF xxx" }         

               "preflist vrf" { puts "PREFL VRF xxx" }         

               default { puts "ERROR -> dksh: wrong set of arguments or spelling" }
               }

          }

   }
 }
}

#------------------------------------------------------------------

#################################################################
# PROCEDURE NAME: norm_arg
# AUTHOR        : D.Koncic, EDS Switzerland
# USE           : this tcl procedure is used to normalise possibly
#                 abbreviated initial arguments
# ARGUMENTS     : CFG_MODE - running|startup|filename
#                 FIRST   - all|bgp|ospf|rip|eigrp|static|interface|def|rmap|preflist
#                 SECOND  - keyword 'vrf'
#                 THIRD   - vrf name to be looked upon
# NOTES         : this procedure used global variables as G_runcfg to
#                 avoid copying with long configs
#################################################################

proc norm_arg {CFG_MODE FIRST SECOND THIRD} {

   global G_CMDGRP
   global G_VRFKWD 
   global G_VRFNAME
   global G_CFGMODE

switch [ string tolower $CFG_MODE ]  {
        r         -
        ru        -
        run       -
        runn      -
        runni     -
        runnin    -
        running   { set CFG_MOD_ARG running }
       
        s         -
        st        -
        sta       - 
        star      -  
        start     - 
        startu    - 
        startup   { set CFG_MOD_ARG startup }
        
        c         -
        co        -
        con       -
        conf      -
        confi     -
        config    { set CFG_MOD_ARG startup }

        h         -
        he        -
        hel       -
        help      { set CFG_MOD_ARG help }
 
        default   { set CFG_MOD_ARG $CFG_MODE }
       }

switch [ string tolower $FIRST ]  {
i  -
in  -
int  -
inte  -
inter  -
interf  -
interfa  -
interfac  -
interface { set FRSTARG interface }

o  -
os  -
osp  -
ospf  { set FRSTARG ospf }

s  -
st  -
sta  -
stat  -
stati  -
static  { set FRSTARG static }

b  -
bg  -
bgp  { set FRSTARG bgp }

ri  -
rip  { set FRSTARG rip }

e  -
ei  -
eig  -
eigr  -
eigrp  { set FRSTARG eigrp }

d  -
de  -
def  { set FRSTARG def }


ac  -
acl  { set FRSTARG acl }

al  -
all  { set FRSTARG all }

rm  -
rma  -
rmap  { set FRSTARG rmap }

n  -
na  -
nat  { set FRSTARG nat }

c  -
cr  -
cry  -
cryp  -
crypt  -
crypto  { set FRSTARG crypto }

p  -
pr  -
pre  -
pref  -
prefl  -
prefli  -
preflis  -
preflist  { set FRSTARG preflist }

ro        -
rou       -
rout      -
routi     -
routin    -
routing   { set FRSTARG routing }

default  { set FRSTARG ERROR }

}

switch [ string tolower $SECOND ] {

v  -
vr  -
vrf  { set SCNDARG vrf }

default  { set SCNDARG ERROR }

}


switch $THIRD {

a  -
al  -
all       { set THRDARG all }

g  -
gl  -
glo  -
glob  -
globa  -
global  { set THRDARG global }

default  { set THRDARG $THIRD }

}

    set G_CMDGRP $FRSTARG
    set G_VRFKWD $SCNDARG
    set G_VRFNAME $THRDARG
    set G_CFGMODE $CFG_MOD_ARG

}

#------------------------------------------------------------------

#################################################################
# PROCEDURE NAME: dksh
# AUTHOR        : D.Koncic, EDS Switzerland
# USE           : this tcl procedure is the main procedure acting
#                 as the visible command for users 
# ARGUMENTS     : CFGMODE - running|startup|filename
#                 CMDGRP  - all|bgp|ospf|rip|eigrp|static|interface|def|rmap|preflist
#                 VRFKWD  - keyword 'vrf'
#                 VRFNAME - vrf name to be looked upon
# NOTES         : this procedure used global variables as G_runcfg to
#                 avoid copying with long configs
#################################################################


proc dksh { {CFGMODE help} {CMDGRP ERROR} {VRFKWD ERROR} {VRFNAME ERROR} } {

   #prepare global variables
   global G_CMDGRP
   global G_VRFKWD 
   global G_VRFNAME
   global G_CFGMODE
   global G_runcfg
   global G_RMAP_LIST
   global G_ACL_LIST
   global G_PREFX_LIST
   global G_CRYMP_LIST
   global ICRLF
   global CRLF
   global CRLFlen
   global LOOPCOUNT

   set G_runcfg "N"
   set G_RMAP_LIST ""
   set G_ACL_LIST ""
   set G_PREFX_LIST ""
   set G_CRYMP_LIST ""
   set CRLFlen 0
   set LOOPCOUNT 3000

   norm_arg $CFGMODE $CMDGRP $VRFKWD $VRFNAME
   cmdswitch $G_CFGMODE $G_CMDGRP $G_VRFKWD $G_VRFNAME

} 

#------------------------------------------------------------------

#################################################################
# PROCEDURE NAME: fetchcfg
# AUTHOR        : D.Koncic, EDS Switzerland
# USE           : this tcl procedure acquires the config to be scanned
#                 and stores into global variable G_runcfg
# ARGUMENTS     : CFG_MODE - determines if running, startup or
# NOTES         : this procedure uses global variable G_runcfg to
#                 avoid copying with long configs
#################################################################

proc fetchcfg { CFG_MODE } {

   global G_runcfg

   if { [ string length $G_runcfg ] == 1 } {
       # G_runcfg empty, fill in with cfg, per CFG_MODE
       puts $CFG_MODE
       switch $CFG_MODE {
           running    {
                      # get the running config and store into a string variable runcfg
                      #set G_runcfg [ exec "sh run" ]
                      set catout [ catch { exec "sh run" } G_runcfg ]
                      if { $catout == 1 } {
                           puts "Problem reading the config!!!"
                           set G_runcfg "ERROR"
                         }
                      }

           startup    {
                      # get the running config and store into a string variable runcfg
                      #set G_runcfg [ exec "sh start" ]
                      set catout [ catch { exec "sh start" } G_runcfg ]              
                      if { $catout == 1 } {                        
                           puts "Problem reading the config!!!"                        
                           set G_runcfg "ERROR"                       
                         }                       
                      }

           default    {
                      #the content for analisys would be from a file specified
                      set catout [ catch { open $CFG_MODE } fl ]
                      if { $catout == 0 } {
                           #all OK
                           set G_runcfg [ read $fl ]
                           close $fl
                         } else {
                           puts "Problem opening the file!!!"
                           set G_runcfg "ERROR"
                         }
                      }
          }
     }
#puts $G_runcfg
}


################################MAIN#################################
# following line just invokes the dksh program to pass the arguments
#####################################################################

 dksh [lindex $argv 0] [lindex $argv 1] [lindex $argv 2] [lindex $argv 3]
