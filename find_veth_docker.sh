#!/bin/bash
ROOT="$(dirname "$0")"

source $ROOT/sources/extra.sh


function show_help
 {
 	c_print "Green" "This script finds out which vethXXXX is connected to what container!"
 	c_print "Bold" "Example: ./find_veth_docker.sh -n <CONTAINER_NAME> -i <INTEFACE_IN_CONTAINER>"
 	c_print "Bold" "\t\t-n <CONTAINER_NAME>: set here the name of the container (Default: No name specified, printing all containers' data)."
  c_print "Bold" "\t\t-i <INTERFACE_IN_CONTAINER>: set here the name of the interace in the container (Default: eth0)."
 	exit
 }

NAME=""
INTF=""

while getopts "h?n:i:" opt
 do
 	case "$opt" in
 	h|\?)
 		show_help
 		;;
 	n)
 		NAME=$OPTARG
 		;;
  i)
    INTF=$OPTARG
    ;;
  *)
    show_help
 		;;
 	esac
 done

c_print "White" "Testing dependencies (jq)..." 1
which jq >> /dev/null
retval=$(echo $?)
check_retval $retval



if [ -z $NAME ]
then
  # c_print "Yellow" "No container name specified...looking for all veths...!"
  cmd="docker ps --format {{.Names}}"
else
  cmd="docker ps --format {{.Names}} -f name=$NAME"
 fi

if [ -z $INTF ]
then
  # c_print "Yellow" "No interface name specified in the container...Using default: ${INTF}!"
  INTF="eth0"
fi



#getting the container names and interface data
c_print "BBlue" "VETH@HOST\tVETH_MAC\t\tCONTAINER_IP\tCONTAINER_MAC\t\tBridge@HOST\t\tBridge_IP\tBridge_MAC\t\tCONTAINER"
for i in $($cmd)
do
  # c_print "BWhite" "${i}"
  #getting the PIDs of the containers
  PID=$(docker inspect $i --format "{{.State.Pid}}")
  if [[ $PID -eq 0 ]]; then
    continue
  fi
  #using the PID, we can get the interface index of the eth0 interfae inside the container
  INDEX=$(cat /proc/$PID/net/igmp |grep "$INTF"| awk '{print $1}')
  #using the index, we can identify the veth interface
  veth=$(ip -br addr |grep "if${INDEX} "|awk '{print $1}'|cut -d '@' -f 1) #we need that extra whitespace at grep "if${INDEX} ", otherwise interface with the prefix will shown too
  veth_mac=$(ip a|grep $veth -A 2|grep ether|awk '{print $2}')
  #check if there is any special subnet created instead of the default
  network_mode=$(docker inspect $i|jq .[].HostConfig.NetworkMode | sed "s/\"//g")
  if [ "$network_mode" == "default" ]
  then
    network="bridge"
  else
    network=$network_mode
  fi

  ip_address=$(docker inspect $i|jq -r .[].NetworkSettings.Networks.\"$network\".IPAddress)
  mac_address=$(docker inspect $i| jq -r .[].NetworkSettings.Networks.\"$network\".MacAddress)
  gateway=$(docker inspect $i| jq -r .[].NetworkSettings.Networks.\"$network\".Gateway)
  bridge=$(ip -br addr |grep $gateway|awk '{print $1}')
  bridge_ip=$(ip a |grep $bridge |grep inet|awk '{print $2}')

  #colons are super important below, without them, grep would find the veth interfaces as well that are connected to the bridge
  #by grepping on the ": <VETH>:", only the right line will be found
  bridge_mac=$(ip a |grep ": ${bridge}:" -A 1| grep ether| awk '{print $2}')

  #residuals from previous version that required built-in tools inside the container, but keeping them for reference
  #veth_in_container=$(docker exec $i ip a|grep ${INTF}@|cut -d ':' -f 1)
  #veth_in_host=$(ip a|grep "if${veth_in_container}:"|cut -d ":" -f 2|cut -d '@' -f 1|sed "s/ //g")
  if [ "$bridge" == "docker0" ]
  then
    #we need an extra TAB before Bridge
    echo -e "${veth}\t${veth_mac}\t${ip_address}\t${mac_address}\t${bridge}\t\t\t${bridge_ip}\t${bridge_mac}\t${i}"
  else
    echo -e "${veth}\t${veth_mac}\t${ip_address}\t${mac_address}\t${bridge}\t\t${bridge_ip}\t${bridge_mac}\t${i}"
  fi
done
