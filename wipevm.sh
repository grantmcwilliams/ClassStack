#!/bin/bash

SCRIPTDIR=$(dirname $(readlink -f "${BASH_SOURCE[0]}"))
source "$SCRIPTDIR/xaptools.lib" 
ROSTERFILE="Rosters/ROSTDOWN.csv"
BASEIMAGE="studentbase"
DISKSIZE="536870912"
DISKTOTAL="4"
CLASSNET[0]="xenbr1"
CLASSNET[1]="xenbr0"
XE=xe
MEMMIN=805306368
MEMMAX=805306368
SSDSANNUM="2"
for i in $(seq 0 $(( ${SSDSANNUM} - 1 )) ) ;do
	SSDSANUUID[$i]=$( ${XE} sr-list name-label=iSCSI-SSD_${i} --minimal)
done

IFS=$'\n'
PS3="Please Choose User: "
select USERNAME in $(awk -F, '{print $6}' $ROSTERFILE  | grep '^[a-Z].*') ;do
	break ;
done

if ! yesno "Wipe disk for $USERNAME" ;then
	exit 1
fi 
clear


STUDENT="$(grep "$USERNAME" $ROSTERFILE | awk -F, '{print $11}')"
VMUUID=$(xe vm-list name-label="$STUDENT" params=uuid --minimal)
if [[ -z "$VMUUID" ]] ;then
	echo "VM doesn't exist"
else
	STATE=$(xe vm-param-get uuid="${VMUUID}" param-name=power-state)
	if [[ "$STATE" = "running" ]] ;then
		echo "*     Shutting down $USERNAME"
		xe vm-shutdown uuid=${VMUUID}
		xe event-wait class=vm power-state=halted uuid=${VMUUID}
		echo "*     Shutdown succeeded for $USERNAME"
	fi
	echo "*     Uninstalling VM for $USERNAME"
	VDIS=$(xe vbd-list vm-uuid=$VMUUID params=vdi-uuid --minimal | sed 's/,/\n/g')
	for VDI in $VDIS ;do
		xe vdi-destroy uuid="$VDI"
	done
	xe vm-uninstall uuid=${VMUUID} force=true
fi


if ! yesno "Create new VM for $USERNAME" ;then
	exit 1
fi 
clear

STUDENT="$(grep "$USERNAME" $ROSTERFILE | awk -F, '{print $11}')"
echo "Creating new VM for ${STUDENT}"

#Create the MAC addresses form the SID
	MAC[0]="00:1$(echo "${STUDENT}" | sed ':a;s/\B[0-9]\{2\}\>/:&/;ta')"
	MAC[1]="00:2$(echo "${STUDENT}" | sed ':a;s/\B[0-9]\{2\}\>/:&/;ta')"

	#Clone studentbase
	BASEUUID=$(${XE} vm-list name-label=${BASEIMAGE} --minimal)
	STATE=$(${XE} vm-param-get uuid=${BASEUUID} param-name=power-state)
	if [ "$STATE" == 'running' ]; then
	    ${XE} vm-shutdown uuid="${BASEUUID}"
	    ${XE} event-wait class=vm power-state=halted uuid="${BASEUUID}"
	fi
	
	if ! ${XE} vm-list name-label="${STUDENT}" | grep -q "uuid" ;then
		VMUUID=$(${XE} vm-clone uuid=${BASEUUID} new-name-label=${STUDENT})
	else
		echo "VM exists: ${STUDENT}"
		VMUUID=$(${XE} vm-list name-label=${STUDENT} params=uuid --minimal)
	fi

	#Delete old virtual network interfaces
	STATE=$(${XE} vm-param-get uuid=${VMUUID} param-name=power-state)
	if [ ! "$STATE" == 'running' ]; then
		echo ""
		echo "Configuring Network Interfaces"
		VIFUUIDS=$(${XE} vif-list vm-name-label=${STUDENT} --minimal | sed 's/,/\n/g')
		for VIF in $VIFUUIDS ;do
			VIFDEV=$(${XE} vif-param-get uuid="${VIF}" param-name=device)
			echo "*     Removing Network Interface eth${VIFDEV}" 
			${XE} vif-destroy uuid="${VIF}"
		done
		#Create new virtual network interfaces
		echo "*     Creating new Network Interface eth${VIFDEV}"
		NETUUID[0]=$(${XE} network-list bridge=${CLASSNET[0]} --minimal)
		VIFUUID[0]=$(${XE} vif-create vm-uuid="${VMUUID}" network-uuid="${NETUUID[0]}" device=0 mac="${MAC[0]}")
		echo "*     Creating new Network Interface eth${VIFDEV}"
		NETUUID[1]=$(${XE} network-list bridge=${CLASSNET[1]} --minimal)
		VIFUUID[1]=$(${XE} vif-create vm-uuid="${VMUUID}" network-uuid="${NETUUID[1]}" device=1 mac="${MAC[1]}")
	fi

	echo ""
	#Set memory limits
	echo "Configuring Misc Parameters"
	STATE=$(${XE} vm-param-get uuid="${VMUUID}" param-name=power-state)
	if [[ ! "$STATE" == 'running' ]] ;then
		echo "*     Setting memory limits"
		${XE} vm-memory-limits-set uuid="${VMUUID}" static-min="${MEMMIN}" dynamic-min="${MEMMIN}" dynamic-max="${MEMMAX}" static-max="${MEMMAX}"
	fi


	echo ""
	echo "Configuring Hard drives"
	
	#Change the name of xvda
	VDIUUID[0]=$(${XE} vbd-list vm-uuid="${VMUUID}" device=xvda params=vdi-uuid --minimal)
	VDINAME[0]=$(${XE} vdi-param-get uuid=537cb4fd-ac64-4e93-88e6-af1a0f132a0a param-name=name-label)
	if [[ ! "${VDINAME[0]}" = "${STUDENT}_0" ]] ;then
		echo "*     Setting name-label for xvda"
		echo ${XE} vdi-param-set uuid="${VDIUUID[0]}" name-label="${STUDENT}_0"
	fi
	
	#Create new SSD disks
	j=0
	for i in $(seq 1 ${DISKTOTAL}) ;do
	if [[ "$j" -ge "${SSDSANNUM}" ]] ;then
			j=0
		fi
		case $i in
			1) DNAME="xvdb" ;;
			2) DNAME="xvdc" ;;
			3) DNAME="xvde" ;;
			4) DNAME="xvdf" ;;
			5) DNAME="xvdg" ;;
			6) DNAME="xvdh" ;;
			7) DNAME="xvdi" ;;
			8) DNAME="xvdj" ;;
		esac
		SSDUUID=$(${XE} vdi-create sr-uuid="${SSDSANUUID[$j]}" name-label=${STUDENT}_${i} type=user virtual-size="${DISKSIZE}")
		echo "*     Creating VDI for $DNAME"
		BLANK=$(${XE} vdi-param-set uuid="$SSDUUID" name-description="$DNAME on ${STUDENT}")
		echo "*     Creating VBD for $DNAME"
		VBDUUID=$(${XE} vbd-create vdi-uuid="$SSDUUID" bootable=false type=disk device="$i" vm-uuid="${VMUUID}")
		(( j++ ))
	done

if yesno "Do you want to start the VM for ${STUDENT}" ;then
	${XE} vm-start uuid=${VMUUID} 
fi
echo "Dom-id is $(xe vm-list uuid=${VMUUID}  params=dom-id)"











