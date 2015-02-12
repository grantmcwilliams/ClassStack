#!/bin/bash 


setup()
{
	if [[ -e "/lib/lsb/init-functions" ]] ;then  
		source /lib/lsb/init-functions
	fi
	SCRIPTDIR=$(dirname $(readlink -f "${BASH_SOURCE[0]}"))
	source "$SCRIPTDIR/xaptools.lib"  #after we move to rpm we'll find a better place for this
	
	#for now
	DOMAIN="acs.edcc.edu"	
	TMPDIR=$(mktemp -d)
	SALTDIR="/etc/salt"
	ROSTER="${SCRIPTDIR}/Rosters/ROSTDOWN.csv"
	BASEIMAGE="studentbase"
	setcolors	
	DEFSPACE="5"
	MAXVIFS="2"
	MINSPACE="$DEFSPACE"
	VERSION="0.5"
	CLASSNET[0]="xenbr1"
	CLASSNET[1]="xenbr0"
	MEMMIN=805306368
	MEMMAX=805306368
	DISKSIZE="536870912" #In Bytes 
	DISKTOTAL="4"
	if [[ -f ${ROSTER} ]] ;then
		getclasses
	fi
	VMSTARTIP="102"
	VMTOTAL="68"
}

setupsan()
{
	SSDSANNUM="1"
	for x in $(seq 0 $(( ${SSDSANNUM} - 1 )) ) ;do
		SSDSANUUID[$x]=$(xe sr-list name-label=iSCSI-SSD_${x} --minimal)
		if [[ -z "${SSDSANUUID[$x]}" ]] ;then
			echo "Error \$SSDSANUUID is empty"
			if yesno "Are you sure you want to continue" ;then
				return 1
			else
				exit 1
			fi
		fi
	done
}

syntax()
{

        echo ""
        echo "	Usage: $(basename $0) [options] <subcommand>"
        echo ""
		cecho "	Version: " cyan ; echo "	$VERSION"
		echo ""
        cecho "	Options:" blue ; echo ""
        cecho "	 -d" cyan ; echo "				Turn on shell debugging"
        cecho "	 -h" cyan ; echo "				This help text"
        cecho "	 -w" cyan ; echo "				Number of whitespaces between columns"
        cecho "	 -s <host>" cyan ; echo "			Remote poolmaster host"
        cecho "	 -s list" cyan ; echo "			List stored poolmaster configs"
        cecho "	 -p <password>" cyan ; echo "			Remote poolmaster password"
        echo ""
        cecho "	Subcommands:" blue ;echo""
        cecho "	 acceptkeys" cyan; echo "		  	Accept Salt keys"
        cecho "	 createvm" cyan; echo "			Create VM for student"
        cecho "	 createclass" cyan; echo "			Create VMs for class"
        cecho "	 createroster <IBC file>" cyan; echo "	Convert Instructor Briefcase screen to CSV"
        cecho "	 listclass" cyan; echo " 			List students, SIDs, IPs and ports"
        cecho "	 listports" cyan; echo " 			List students and their ports"
        cecho "	 listinfo" cyan; echo " 			List information about students"
        cecho "	 listconsoles" cyan; echo "			List consoles for VMs"
		cecho "	 listrunning" cyan; echo "			List power-state for VMs"
        cecho "	 startvm" cyan; echo "	 		Start VM for student"
        cecho "	 startclass" cyan; echo " 			Start VMs for class"
        cecho "	 restartvm" cyan; echo "    			Restart VM for student"
        cecho "	 restartclass" cyan; echo "    		Restarts VMs for class"
        cecho "	 runvm" cyan ; echo " 				Run command on VM"
        cecho "	 runclass" cyan ; echo " 			Run command on all VMs in a class"
        cecho "	 showconsole" cyan ; echo " 			Show VM console for student"
        cecho "	 stopvm" cyan; echo " 			Stops VM for student"
        cecho "	 stopclass" cyan; echo " 			Stops VMs for class"
        cecho "	 updategrains" cyan; echo "			Append class grain to VMs"
        cecho "	 updatebase" cyan; echo "			Update Base Image"
        cecho "	 deletevm" red; echo "			Delete VM for student"
        cecho "	 deleteclass" red;	echo "			Delete VMs for class"
        cecho "	 recreatevm" red; echo " 			Shutdown, recreate, start a VM"
        echo ""
        exit
}

getethers()
{
	# get classserver:/etc/{ethers|hosts}
	
	for FILE in "$TMPDIR/ethers" "$TMPDIR/ethers.tmp" "$TMPDIR/hosts" "$TMPDIR/hosts.tmp" ;do
		if [[ -e "$FILE" ]] ;then
			rm -f "$FILE"
		fi
	done
	if ! scp -P 1022 -q classserver:/etc/ethers "$TMPDIR/ethers.tmp" ;then
		log_failure_msg "Could not retrieve ethers file" ;return 1
	else
		sed '/^$/d' "$TMPDIR/ethers.tmp" | sort +1 -2 > "$TMPDIR/ethers"
	fi
	if ! scp -P 1022 -q classserver:/etc/hosts "$TMPDIR/hosts.tmp" ;then
		log_failure_msg "Could not retrieve hosts file" ;return 1
	else
		sed '/^$/d' "$TMPDIR/hosts.tmp" > "$TMPDIR/hosts"
	fi
}

putethers()
{
	#Copies ethers/hosts to classserver
	cecho "*" cyan ;echo "     Uploading ethers/hosts"
	sed '/^$/d' "$TMPDIR/ethers" | sort +1 -2 > "$TMPDIR/ethers.tmp"
	scp -P 1022 -q "$TMPDIR/ethers.tmp" "classserver:/etc/ethers"
	sed -i '/^$/d' "$TMPDIR/hosts"
	scp -P 1022 -q "$TMPDIR/hosts" "classserver:/etc/hosts"
	OUT=$(ssh -p 1022 classserver "service dnsmasq restart")
	for LINE in $OUT ;do
		cecho "*" cyan ;echo "     $LINE"
	done
}

acceptkeys()
{
	PS3="Please choose keys to accept: "
	while true ;do
		clear
		echo ""
		KEYS=$(salt-key -l unaccepted | grep -v 'Unaccepted Keys:')
		if [[ -z "$KEYS" ]] ;then
			echo "All keys accepted - exiting"
			exit 
		else
			select CHOICE in ${KEYS} "All" "Exit" ;do
				case "$CHOICE" in
					"Exit")	
						break 2 ;;	
					"All")
						salt-key -A
						break 2 ;;
					*) 
						salt-key -a "$CHOICE" -y
						sleep 2
						break ;;
				esac
			done
		fi
	done
}

runstudent()
{   
	shift
	COMMAND="$@"
	getethers
	if ! choosestudent ;then
		exit
	fi
	clear ; echo ""
	runvm "${STUSIDS[$STUDENTINDEX]}" "${COMMAND}"
}

runclass()
{
	shift
	COMMAND="$@"
	if [[ -z ${COMMAND} ]] ;then
		warn "No command to run" ; echo ""
	else
		getethers
		getstudents
		if ! chooseclass;then
			exit
		fi
		clear ; echo ""
		title1 "Running $1 on ${CLASSES[$CLASSINDEX]} VMs" ;echo ""
		for i in $(seq 0 $(( ${#STUCLASSES[@]} - 1 )) ) ;do
			if [[ "${STUCLASSES[$i]}" == "${CLASSES[$CLASSINDEX]}" ]] ;then
				runvm "${STUSIDS[$i]}" "${COMMAND}"
			fi
		done
	fi
}

runvm()
{
	VM="${1}"
	shift
	COMMAND="${@}"
    if [[ $(xe vm-list name-label="${VM}" params=power-state --minimal) = "running" ]]; then
		salt "${VM}.${DOMAIN}" cmd.run "${COMMAND}" 
    fi	
}

getclasses()
{
	CLASSES=( $(awk -F, '{print $1}' "$ROSTER" | sed 's/ /_/g' | sort -u ) )
}

chooseclass()
{
	#Returns the Class Index e.g. 1
	IFS=$'\n'
	clear ; echo ""
	title1 "Choose Class" ;echo ""
	PS3=" Please choose: "
	getclasses
	select CHOICE in ${CLASSES[@]} "Exit" ;do
		case "$CHOICE" in
			"Exit")	
				return 1	
			;;
			*) 
				for i in $(seq 0 $(( ${#CLASSES[@]} - 1 )) ) ;do
					if [[ "$CHOICE" = ${CLASSES[$i]} ]];then
						CLASSINDEX="$i"
						break 3
					fi
				done
			;;
		esac
	done
}

choosestudent()
{
	#Returns the Student Index e.g. 21
	IFS=$'\n'
	clear ; echo ""
	title1 "Choose Student" ;echo ""
	PS3=" Please choose: "
	local -a INDEX
	getstudents
	
	fsort_arrays STUNAMES STUSIDS
	select CHOICE in ${STUNAMES[@]} "Exit" ;do
		case "$CHOICE" in
			"Exit")	
				return 1
			;;
			*) 		
				for i in $(seq 0 $(( ${#STUNAMES[@]} - 1 )) ) ;do
					if [[ "$CHOICE" = ${STUNAMES[$i]} ]];then
						STUDENTINDEX="$i"
						break 3
					fi
				done	
			;;
		esac
	done
}

getstudents()
{
	IFS=$'\n'
	i=0
	for LINE in $(cat "$ROSTER") ;do
		STUCLASSES[$i]=$(echo ${LINE%%,*} | sed 's/ /_/g') 			;LINE="${LINE#*,}"
		STUSIDS[$i]=$(echo ${LINE%%,*} | sed 's/-//g')     			;LINE="${LINE#*,}"
		STUNAMES[$i]=$(echo ${LINE%%,*} | awk '{print $2,$1,$3}')	;LINE="${LINE#*,}"
		STUDPHONES[$i]=$(echo ${LINE%%,*} | sed 's/ /-/g')  		;LINE="${LINE#*,}"
		STUEPHONES[$i]=$(echo ${LINE%%,*} | sed 's/ /-/g') 			;LINE="${LINE#*,}"
		STUMAC[$i]=$(echo "001${STUSIDS[$i]}" | sed ':a;s/\B[u0-9]\{2\}\>/:&/;ta')
		STUIP[$i]=$(grep ${STUMAC[$i]} $TMPDIR/ethers.tmp | awk '{print $2}')
		if [[ -z ${STUIP[$i]} ]]  ;then
			STUIP[$i]="-"
		fi
		STUPORT[$i]=$(grep ${STUMAC[$i]} $TMPDIR/ethers.tmp | awk '{print $2}' | sed 's/192.168.0./10/g')
		if [[ -z ${STUPORT[$i]} ]]  ;then
			STUPORT[$i]="-"
		fi
		((i++))
	done
}

showconsoles()
{
	clear ; echo ""
	INDEX="$1" 
	getcmddata vm-list params=name-label,dom-id,resident-on
	getcmddata host-list params=uuid,name-label
	for i in $(seq 0 $(( ${#vm_name_label[@]} - 1 )) ) ;do
		VMNAME[$i]="${vm_name_label[$i]}"
		VMDOMID[$i]="${vm_dom_id[$i]}"
		HOSTUUID[$i]="${vm_resident_on[$i]}"
		for j in $(seq 0 $(( ${#host_uuid[@]} - 1 )) ) ;do
			if [[ ${HOSTUUID[$i]} = ${host_uuid[$j]} ]] ;then
				STUFQDN=${host_name_label[$j]}
				HOSTLABEL[$i]=${STUFQDN%%.*}
			fi
		done
	done
	
	for i in $(seq 0 $(( ${#STUSIDS[@]} - 1 )) ) ;do	
		for j in $(seq 0 $(( ${#VMNAME[@]} - 1 )) ) ;do
			if [[ ${STUSIDS[$i]} = ${VMNAME[$j]} ]] ;then
				STUDOMID[$i]=${VMDOMID[$j]}
				STUHOSTLABLE[$i]=${HOSTLABEL[$j]}
			fi
		done
	done
	
	#for i in $(seq 0 $(( ${#STUSIDS[@]} - 1 )) ) ;do	
	#	STUCONSOLE[$i]=$(xe vm-list name-label=${STUSIDS[$i]} params=dom-id --minimal)
	#	CLOUDHOSTUUID=$(xe vm-list name-label=${STUSIDS[$i]} params=resident-on --minimal)
	#	STUFQDN=$(xe host-list uuid=$CLOUDHOSTUUID params=name-label --minimal)
	#	STUHOST[$i]=${STUFQDN%%.*}
	#done
	
	fsort_arrays STUNAMES STUCLASSES STUSIDS STUDOMID STUHOSTLABLE
	TITLES=( 'Name' 'SID' 'Dom-id' 'Host' )
	COLLONGEST[0]=$(getcolwidth "${TITLES[0]}" "${STUNAMES[@]}")
	COLLONGEST[1]=$(getcolwidth "${TITLES[1]}" "${STUSIDS[@]}")
	COLLONGEST[2]=$(getcolwidth "${TITLES[2]}" "${STUDOMID[@]}")
	COLLONGEST[3]=$(getcolwidth "${TITLES[3]}" "${STUHOSTLABLE[@]}")
	TITLEBARWIDTH=$(( ${COLLONGEST[0]} + $MINSPACE + ${COLLONGEST[1]} + $MINSPACE + ${COLLONGEST[2]} + $MINSPACE + ${COLLONGEST[3]} ))
	printtitlebar "Console List" "$TITLEBARWIDTH" black
	printheadings
	for i in $(seq 0 $(( ${#STUSIDS[@]} - 1 )) ) ;do	
		if [[ "${STUCLASSES[$i]}" = "${CLASSES[$INDEX]}" ]] ;then
			cecho "${STUNAMES[$i]}" cyan 					;printspaces "${COLLONGEST[0]}" "${#STUNAMES[$i]}" 
			cecho "${STUSIDS[$i]}" cyan 					;printspaces "${COLLONGEST[1]}" "${#STUSIDS[$i]}" 
			cecho "${STUDOMID[$i]}" cyan 					;printspaces "${COLLONGEST[2]}" "${#STUDOMID[$i]}"     
			cecho "${STUHOSTLABLE[$i]}" blue     			
			echo ""
		fi
	done
}

showclass()
{

	local MODE="standard"
	while getopts :vp opt ;do
        	case $opt in
                	v) local MODE="verbose" ;;
                	p) local MODE="ports" ;;
        	esac
	done
	shift $(($OPTIND - 1))
	clear ; echo ""
	INDEX="$1"
	fsort_arrays STUNAMES STUSIDS STUDPHONES STUEPHONES STUIP STUPORT STUCLASSES STUMAC
	case "$MODE" in
		"standard")
			TITLES=( 'Name' 'SID' 'IP' 'Port' )
			COLLONGEST[0]=$(getcolwidth "${TITLES[0]}" "${STUNAMES[@]}")
			COLLONGEST[1]=$(getcolwidth "${TITLES[1]}" "${STUSIDS[@]}")
			COLLONGEST[2]=$(getcolwidth "${TITLES[2]}" "${STUIP[@]}")
			COLLONGEST[3]=$(getcolwidth "${TITLES[3]}" "${STUPORT[@]}")
			TITLEBARWIDTH=$(( ${COLLONGEST[0]} + $MINSPACE + ${COLLONGEST[1]} + $MINSPACE + ${COLLONGEST[2]} +  $MINSPACE + ${COLLONGEST[3]} ))
			printtitlebar "Student List" "$TITLEBARWIDTH" black
			printheadings
			for i in $(seq 0 $(( ${#STUSIDS[@]} - 1 )) ) ;do	
				if [[ "${STUCLASSES[$i]}" = "${CLASSES[$INDEX]}" ]] ;then
					cecho "${STUNAMES[$i]}" cyan 					;printspaces "${COLLONGEST[0]}" "${#STUNAMES[$i]}" 
					cecho "${STUSIDS[$i]}" cyan 					;printspaces "${COLLONGEST[1]}" "${#STUSIDS[$i]}" 
					cecho "${STUIP[$i]}" cyan 						;printspaces "${COLLONGEST[2]}" "${#STUIP[$i]}"  
					cecho "${STUPORT[$i]}" blue     			
				echo ""
				fi
			done
		;;
		"ports")
			TITLES=( 'Name' 'Port' )
			COLLONGEST[0]=$(getcolwidth "${TITLES[0]}" "${STUNAMES[@]}")
			COLLONGEST[1]=$(getcolwidth "${TITLES[1]}" "${STUSIDS[@]}")
			COLLONGEST[2]=$(getcolwidth "${TITLES[2]}" "${STUIP[@]}")
			COLLONGEST[3]=$(getcolwidth "${TITLES[3]}" "${STUPORT[@]}")
			TITLEBARWIDTH=$(( ${COLLONGEST[0]} + $MINSPACE + ${COLLONGEST[1]} + $MINSPACE + ${COLLONGEST[2]} +  $MINSPACE + ${COLLONGEST[3]} ))
			printtitlebar "Student Ports List" "$TITLEBARWIDTH" black
			printheadings
			for i in $(seq 0 $(( ${#STUSIDS[@]} - 1 )) ) ;do	
				if [[ "${STUCLASSES[$i]}" = "${CLASSES[$INDEX]}" ]] ;then
					cecho "${STUNAMES[$i]}" cyan 					;printspaces "${COLLONGEST[0]}" "${#STUNAMES[$i]}" 
					cecho "${STUPORT[$i]}" blue     			
				echo ""
				fi
			done
		;;
		"verbose")
			TITLES=( 'Name' 'SID' 'IP' 'Port' 'Day Phone' 'Eve Phone' )
			COLLONGEST[0]=$(getcolwidth "${TITLES[0]}" "${STUNAMES[@]}")
			COLLONGEST[1]=$(getcolwidth "${TITLES[1]}" "${STUSIDS[@]}")
			COLLONGEST[2]=$(getcolwidth "${TITLES[2]}" "${STUIP[@]}")
			COLLONGEST[3]=$(getcolwidth "${TITLES[3]}" "${STUPORT[@]}")
			COLLONGEST[4]=$(getcolwidth "${TITLES[4]}" "${STUDPHONES[@]}")
			COLLONGEST[5]=$(getcolwidth "${TITLES[5]}" "${STUEPHONES[@]}")
			TITLEBARWIDTH=$(( ${COLLONGEST[0]} + $MINSPACE + ${COLLONGEST[1]} + $MINSPACE + ${COLLONGEST[2]} + $MINSPACE + ${COLLONGEST[3]}  + $MINSPACE + ${COLLONGEST[4]} + $MINSPACE + ${COLLONGEST[5]} ))
			printtitlebar "Student Info" "$TITLEBARWIDTH" black
			printheadings
			for i in $(seq 0 $(( ${#STUSIDS[@]} - 1 )) ) ;do	
				if [[ "${STUCLASSES[$i]}" = "${CLASSES[$INDEX]}" ]] ;then
					cecho "${STUNAMES[$i]}" cyan 					;printspaces "${COLLONGEST[0]}" "${#STUNAMES[$i]}" 
					cecho "${STUSIDS[$i]}" blue     	 			;printspaces "${COLLONGEST[1]}" "${#STUSIDS[$i]}" 
					cecho "${STUIP[$i]}" cyan 						;printspaces "${COLLONGEST[2]}" "${#STUIP[$i]}" 
					cecho "${STUPORT[$i]}" cyan 					;printspaces "${COLLONGEST[3]}" "${#STUPORT[$i]}" 
					cecho "${STUDPHONES[$i]}" blue      			;printspaces "${COLLONGEST[4]}" "${#STUDPHONES[$i]}" 
					cecho "${STUEPHONES[$i]}" blue
				echo ""
				fi
			done
		;;	
	esac
}


consolestudent()
{
	getethers
	if ! choosestudent ;then
		exit
	fi

    getconsole "${STUSIDS[STUDENTINDEX]}"
	showconsole "$HOSTLABEL" "$VMDOMID"
}

getconsole()
{
        STUDENTID="$1"
     	getcmddata vm-list params=name-label,dom-id,resident-on
        getcmddata host-list params=uuid,name-label
        for i in $(seq 0 $(( ${#vm_name_label[@]} - 1 )) ) ;do
                VMNAME="${vm_name_label[$i]}"
                if [[ $VMNAME = ${STUDENTID} ]] ;then
                	VMDOMID="${vm_dom_id[$i]}"
                	HOSTUUID="${vm_resident_on[$i]}"
					for j in $(seq 0 $(( ${#host_uuid[@]} - 1 )) ) ;do
                        	if [[ ${HOSTUUID} = ${host_uuid[$j]} ]] ;then
                                	STUFQDN=${host_name_label[$j]}
                                	HOSTLABEL=${STUFQDN%%.*}
                       	 	fi
                	done
                fi
        done
}

showconsole()
{
   	CLOUDHOST="$1"
	CONSOLE="$2"

	echo "Hit enter to see console"
	echo "Type exit to logout and control ] to exit console"
    sleep 3
	ssh -t root@${CLOUDHOST} /usr/lib/xen/bin/xenconsole ${CONSOLE}
}


listclass()
{
	getethers
	getstudents
	if ! chooseclass ;then
		exit 1
	else
		showclass "$CLASSINDEX"
	fi
}

listports()
{
	getethers
	getstudents
	if ! chooseclass ;then
		exit 1
	else
		showclass -p "$CLASSINDEX"
	fi
}

listconsoles()
{
	getethers
	getstudents
	if ! chooseclass ;then
		exit 1
	else
		showconsoles "$CLASSINDEX"
	fi
	
}

listinfo()
{
	getethers
	getstudents
	if ! chooseclass ;then
		exit 1
	else
		showclass -v "$CLASSINDEX"
	fi
}

listrunning()
{
	getethers
	getstudents
	if ! chooseclass ;then
		exit 1
	else
		showrunning "$CLASSINDEX"
	fi
}

createclass()
{
	getethers
	getstudents
	if ! chooseclass;then
		exit
	fi
	title1 "Creating VMs for ${CLASSES[$CLASSINDEX]}" ;echo ""
	for i in $(seq 0 $(( ${#STUCLASSES[@]} - 1 )) ) ;do
		if [[ "${STUCLASSES[$i]}" == "${CLASSES[$CLASSINDEX]}" ]] ;then
			createvm "$i"
		fi
	done
	putethers
}

createroster()
{
	IBCFILE="$1"
	IFS=$'\n'
	
	if [ -z "$IBCFILE" ] ;then
		echo "No rosterfile specified - exiting"
		exit 1
	fi

	if [ -d /root/bin/Rosters ] ;then
		ROSTDIR="$SCRIPTDIR/Rosters"
	else
		mkdir -p "$SCRIPTDIR/Rosters"
		ROSTDIR="$SCRIPTDIR/Rosters"
	fi

	NEWROSTER="$ROSTDIR/ROSTDOWN.csv"
	if [ -e "$NEWROSTER" ];then
		if ! yesno "Roster already exits - append? y|n" ;then
			rm -f "$NEWROSTER"
		fi 
	fi

	COURSE=$(grep -A1 QUARTER ${IBCFILE} | tail -n1 | awk -F'\t' '{print $3}' | sed 's/^[ \t]*//;s/[ \t]*$//')
	for LINE in $(cat "$IBCFILE") ;do
		if echo "$LINE" | grep -q '^[0-9]' ;then
			NEWLINE=$(echo "$LINE" | sed 's/\t/,/g' | awk -F, '{print $2","$3","$5","$6","$7}')
			echo "${COURSE},${NEWLINE}" >> "$NEWROSTER"
		fi
	done

	if [[ -e "$NEWROSTER" ]] ;then	
		dos2unix "$NEWROSTER" &> /dev/null
	fi

}

createstudent()
{
	getethers
	if ! choosestudent ;then
		exit
	fi
	createvm "$STUDENTINDEX"
	putethers
}

createvm()
{
	clear ; echo ""
	#Pass the INDEX number from the student SID in "${STUNAMES[$INDEX]}" 
	local INDEX="$1"
	title1 "Creating VM for ${STUSIDS[$INDEX]}" ; echo ""
	#Get studentbase UUID, if it's running shut it down
	if [[ ! -z $(xe vm-list name-label="${STUSIDS[$INDEX]}") ]] ;then
		cecho "VM exists: " cyan ; echo "${STUSIDS[$INDEX]} - skipping"
		return 1
	fi
	
	BASEUUID=$(xe vm-list name-label="${BASEIMAGE}" --minimal)
	if [ $(xe vm-param-get uuid="${BASEUUID}" param-name=power-state) == 'running' ]; then
	    xe vm-shutdown uuid="${BASEUUID}"
	    xe event-wait class=vm power-state=halted uuid="${BASEUUID}"
	fi
	
	#Clone base VM
	STUUUID[$INDEX]=$(xe vm-clone uuid="${BASEUUID}" new-name-label="${STUSIDS[$INDEX]}")
	
	#Configure Network for ${STUUUID[$INDEX]}
	if [[ ! $(xe vm-param-get uuid="${STUUUID[$INDEX]}" param-name=power-state) == 'running' ]]; then
		echo "Configuring Network Interfaces"
		VIFUUIDS=$(xe vif-list vm-uuid="${STUUUID[$INDEX]}" params=uuid --minimal | sed 's/,/\n/g')
		for VIF in $VIFUUIDS ;do
			VIFDEV=$(xe vif-param-get uuid="${VIF}" param-name=device)
			cecho "*" cyan ;echo "     Removing Network Interface eth${VIFDEV}" 
			xe vif-destroy uuid="${VIF}"
		done
		for ((i=0; i <= $(($MAXVIFS - 1)) ; i++)); do 
			NETUUID[$i]=$(xe network-list bridge="${CLASSNET[$i]}" --minimal)
			cecho "*" cyan ;echo "     Creating new Network Interface eth${i}"
			MAC=$(echo "00$((i + 1))${STUSIDS[$INDEX]}" | sed ':a;s/\B[u0-9]\{2\}\>/:&/;ta')
			VIFUUID[$i]=$(xe vif-create vm-uuid="${STUUUID[$INDEX]}" network-uuid="${NETUUID[$i]}" device="${i}" mac="${MAC}")
		done
	fi ; echo
	
	#Change the name of xvda to ${STUNAMES[$INDEX]}_0 e.g. 987654321_0
	echo "Configuring Hard drives"
	VDINUM=$(xe vbd-list vm-uuid="${STUUUID[$INDEX]}" params=vdi-uuid --minimal | wc -l)
	if [[ $VDINUM -eq 1 ]] ;then
		VDIUUID=$(xe vbd-list vm-uuid="${STUUUID[$INDEX]}" params=vdi-uuid --minimal)
	else
		VDIUUID=$(xe vbd-list vm-uuid="${STUUUID[$INDEX]}" device=xvda params=vdi-uuid --minimal)
	fi
	if [[ ! -z $VDIUUID ]] ;then
		VDINAME=$(xe vdi-param-get uuid="$VDIUUID" param-name=name-label)
		if [[ ! "$VDINAME" = "${STUSIDS[$INDEX]}_0" ]] ;then
			cecho "*" cyan ;echo "     Setting name-label for xvda"
			xe vdi-param-set uuid="$VDIUUID" name-label="${STUSIDS[$INDEX]}_0"
		fi
	else
		cecho "*" red ;echo "     VDIUUID empty for ${STUNAMES[$INDEX]}"
		return 1
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
		
		# Check to see if the disks are there first before creating them.....!!!!!!!
		if [[ -z $(xe vdi-list name-label="${STUSIDS[$INDEX]}_${i}" params=uuid --minimal) ]];then
			SSDUUID=$(xe vdi-create sr-uuid="${SSDSANUUID[$j]}" name-label="${STUSIDS[$INDEX]}_${i}" type=user virtual-size="${DISKSIZE}")
			cecho "*" cyan ;echo "     Creating disk $DNAME"
			BLANK=$(xe vdi-param-set uuid="$SSDUUID" name-description="$DNAME on ${STUSIDS[$INDEX]}")
		fi
		SSDUUID=$(xe vdi-list name-label="${STUSIDS[$INDEX]}_${i}" params=uuid --minimal)
		VBDUUID=$(xe vbd-create vdi-uuid="$SSDUUID" bootable=false type=disk device="$i" vm-uuid="${STUUUID[$INDEX]}")
		if [[ $(xe vm-param-get uuid="${STUUUID[$INDEX]}" param-name=power-state) == 'running' ]]; then
			xe vbd-plug uuid="${VBDUUID}"
		fi
		(( j++ ))
	done	
	
	#Set memory limits
	if [[ ! $(xe vm-param-get uuid="${STUUUID[$INDEX]}" param-name=power-state) == 'running' ]]; then
		echo ""
		echo "Configuring Misc Parameters"
		if [[ ! $(xe vm-param-get uuid="${STUUUID[$INDEX]}" param-name=power-state) == 'running' ]] ;then
			if [[ ! $(xe vm-list uuid="${STUUUID[$INDEX]}" params=memory-static-max --minimal) == "${MEMMIN}" ]] ;then
				cecho "* " cyan ;echo "    Setting memory limits"
				xe vm-memory-limits-set uuid="${STUUUID[$INDEX]}" static-min="${MEMMIN}" dynamic-min="${MEMMIN}" dynamic-max="${MEMMAX}" static-max="${MEMMAX}"
			fi
		fi
	fi
	
	#Update ethers/hosts files
	cecho "*" cyan ;echo "     Updating ethers/hosts"
	for FILE in "$TMPDIR/ethers" "$TMPDIR/hosts" ;do
		if [[ ! -e "$FILE" ]] ;then
			if ! getethers ; then
				echo "Unable to get ethers/hosts - exiting"
			fi
		fi
	done
	
	if ! grep -q "${STUMAC[$INDEX]}" "$TMPDIR/ethers" ;then
		VMENDIP=$(( VMSTARTIP + VMTOTAL ))
		for IP in $(seq "$VMSTARTIP" "$VMENDIP") ;do
		    if ! grep -q "192.168.0.${IP}" "$TMPDIR/ethers" ;then
				STUIP[$INDEX]="192.168.0.${IP}"
				STUPORT[$INDEX]="10${IP}"
				echo "${STUMAC[$INDEX]} 192.168.0.${IP}" >> "$TMPDIR/ethers"
				break
		    fi
		done
	else
		STUIP[$INDEX]=$(grep "${STUMAC[$INDEX]}" "$TMPDIR/ethers" | awk '{print $2}')
	fi
	if ! grep -q "${STUSIDS[$INDEX]}" "$TMPDIR/hosts" ;then
  		echo "${STUIP[$INDEX]} ${STUSIDS[$INDEX]}.${DOMAIN} ${STUSIDS[$INDEX]}" >> "$TMPDIR/hosts"	
	fi
	
	#Add entry to salt-ssh roster
	grep -v "${STUSIDS[$INDEX]}" "${SALTDIR}/roster" > "${TMPDIR}/roster"
	echo "${STUSIDS[$INDEX]}: ${STUIP[$INDEX]}" >> "${TMPDIR}/roster"
	cat "${TMPDIR}/roster" > "${SALTDIR}/roster}"
}

startclass()
{
	#Classserver always has to be running before student VMs to provide DHCP/NFS/DNS
    #if [[ -z $(xe vm-list -s $CLOUDCONTROL -u root -pw $CLOUDPASS name-label=classserver params=uuid --minimal) ]] ;then
	#	echo "VM classserver doesn't exist"
	#	exit 1
    #fi
    
    #CSSSTATE=$(xe -s $CLOUDCONTROL -u root -pw $CLOUDPASS vm-list name-label=classserver params=power-state --minimal)
    #if [ "${CSSSTATE}" = "halted" ]; then
	#	xe vm-start -s $CLOUDCONTROL -u root -pw $CLOUDPASS name-label=classserver
	#	xe event-wait -s $CLOUDCONTROL -u root -pw $CLOUDPASS class=vm power-state=running name-label=classserver
    #fi
   
	getethers
	getstudents
	if ! chooseclass;then
		exit
	fi
	clear ; echo ""
	title1 "Starting ${CLASSES[$CLASSINDEX]} VMs" ;echo ""
	for i in $(seq 0 $(( ${#STUCLASSES[@]} - 1 )) ) ;do
		if [[ "${STUCLASSES[$i]}" == "${CLASSES[$CLASSINDEX]}" ]] ;then
			cecho "*" cyan ;echo "     ${STUSIDS[$i]}"
			if [[ $(xe vm-list name-label="${STUSIDS[$i]}" params=power-state --minimal) = "halted" ]]; then
				xe vm-start name-label="${STUSIDS[$i]}"
				xe event-wait class=vm power-state=running name-label="${STUSIDS[$i]}"
			fi
		fi
	done
}

startstudent()
{   
	getethers
	if ! choosestudent ;then
		exit
	fi
	clear ; echo ""
	startvm "${STUSIDS[$STUDENTINDEX]}"
}

startvm()
{
	VM="$1"
    title1 "Starting VM" ;echo ""
	cecho "*" cyan ;echo "     ${VM}"
    if [[ $(xe vm-list name-label="${VM}" params=power-state --minimal) = "halted" ]]; then
		xe vm-start name-label="${VM}"
		xe event-wait class=vm power-state=running name-label="${VM}"
    fi	
}

restartstudent()
{
	getethers
	if ! choosestudent ;then
		exit
	fi
	clear ; echo ""
	title1 "Restarting VM" ;echo ""
	cecho "*" cyan ;echo "     ${STUSIDS[$STUDENTINDEX]}"
	xe vm-reboot name-label="${STUSIDS[$STUDENTINDEX]}"
	xe event-wait class=vm power-state=running name-label="${STUSIDS[$STUDENTINDEX]}"
}

restartclass()
{
	getethers
	getstudents
	if ! chooseclass;then
		exit
	fi
	clear ; echo ""
	title1 "Restarting ${CLASSES[$CLASSINDEX]} VMs" ;echo ""
	for i in $(seq 0 $(( ${#STUCLASSES[@]} - 1 )) ) ;do
		if [[ "${STUCLASSES[$i]}" == "${CLASSES[$CLASSINDEX]}" ]] ;then
			cecho "*" cyan ;echo "     ${STUSIDS[$i]}"
			if [[ $(xe vm-list name-label="${STUSIDS[$i]}" params=power-state --minimal) = "halted" ]]; then
				xe vm-reboot name-label="${STUSIDS[$i]}"
				xe event-wait class=vm power-state=running name-label="${STUSIDS[$i]}"
			fi
		fi
	done
}

stopstudent()
{
	getethers
	if ! choosestudent ;then
		exit
	fi
	VMUUID=$(xe vm-list name-label="${STUSIDS[$STUDENTINDEX]}" params=uuid --minimal)
	if [[ $(xe vm-param-get uuid="${VMUUID}" param-name=power-state) == 'running' ]]; then
		clear ; echo ""
		title1 "Shutting down Student VM" ;echo ""
		cecho "*" cyan ;echo "     ${STUSIDS[$STUDENTINDEX]}"
		xe vm-shutdown uuid="${VMUUID}"
		xe event-wait class=vm power-state=halted uuid="${VMUUID}"
	fi
}

stopclass()
{
	getethers
	getstudents
	if ! chooseclass;then
		exit
	fi
	clear ; echo ""
	
	title1 "Shutting down ${CLASSES[$CLASSINDEX]} VMs" ; echo ""
	for i in $(seq 0 $(( ${#STUCLASSES[@]} - 1 )) ) ;do
		VMUUID=$(xe vm-list name-label="${STUSIDS[$i]}" params=uuid --minimal)
		if [[ "${STUCLASSES[$i]}" == "${CLASSES[$CLASSINDEX]}" ]] ;then
			if [[ $(xe vm-param-get uuid=$VMUUID param-name=power-state) == 'running' ]]; then
				cecho "*" cyan ;echo "     ${STUSIDS[$i]}"
				xe vm-shutdown uuid="${VMUUID}"
				xe event-wait class=vm power-state=halted uuid="${VMUUID}"
			fi
		fi
	done
}


updategrains()
{
	getethers
	getstudents
	title1 "Updating grains for all VMs" ;echo ""
	
	for i in $(seq 0 $(( ${#STUSIDS[@]} - 1 )) ) ;do 
		salt "${STUSIDS[$i]}.acs.edcc.edu" grains.append classes "${STUCLASSES[$i]}"
	done
}

updateconfig()
{
	getethers
	getstudents
	if ! chooseclass;then
		exit
	fi
	clear ; echo ""
	title1 "Updating config for ${CLASSES[$CLASSINDEX]} VMs" ;echo ""
	salt -G classes:${CLASSES[$CLASSINDEX]} state.highstate
}

updatebaseimage()
{
	BASEUUID=$(xe vm-list name-label="${BASEIMAGE}" --minimal)
	if [ $(xe vm-param-get uuid="${BASEUUID}" param-name=power-state) == 'halted' ]; then
	    xe vm-start uuid="${BASEUUID}"
	    xe event-wait class=vm power-state=running uuid="${BASEUUID}"
	fi
    BASEDOMID=$(xe vm-list uuid="${BASEUUID}" params=dom-id --minimal)
	BASEHOSTUUID=$(xe vm-list uuid="${BASEUUID}" params=resident-on --minimal)
	BASEHOSTNAME=$(xe host-list uuid="${BASEHOSTUUID}" params=hostname --minimal)
	showconsole "${BASEHOSTNAME}" "${BASEDOMID}"
}

wipevm()
{
	#Pass the INDEX number from the student SID in "${STUSIDS[$INDEX]}"
	local INDEX="$1"
	clear ; echo ""
	if [[ $(xe vm-list name-label="${STUSIDS[$INDEX]}" --minimal | sed 's/,/\n/g' | wc -l) -gt 1 ]] ;then
		warn "There are multiple VMs named ${STUSIDS[$INDEX]}" ;echo ""
		return 1
	fi	
	
	STUUUID[$INDEX]=$(xe vm-list name-label="${STUSIDS[$INDEX]}" --minimal)
	if [[ -z "${STUUUID[$INDEX]}" ]] ;then
		warn " VM - ${STUSIDS[$INDEX]} doesn't exist " ;echo "" ;echo ""
		return 1
	else
		title1 "Uninstalling VM for ${STUSIDS[$INDEX]}" ;echo ""
		if [[ $(xe vm-param-get uuid="${STUUUID[$INDEX]}" param-name=power-state) == "running" ]] ;then
			cecho "*" cyan ;echo "	Shutting down VM ${STUSIDS[$INDEX]}" 
			xe vm-shutdown uuid="${STUUUID[$INDEX]}" force=true
			xe event-wait class=vm power-state=halted uuid="${STUUUID[$INDEX]}"
			cecho "*" cyan ;echo "     Shutdown succeeded for ${STUSIDS[$INDEX]}"
		fi
		for VDI in $(xe vbd-list vm-uuid="${STUUUID[$INDEX]}" params=vdi-uuid --minimal | sed 's/,/\n/g') ;do
			VDINAME=$(xe vdi-param-get uuid=${VDI} param-name=name-label)
			cecho "*" cyan ;echo "     Removing VDI $VDINAME"
			xe vdi-destroy uuid="$VDI"
		done
		OUT=$(xe vm-uninstall uuid="${STUUUID[$INDEX]}" force=true)
		for LINE in $OUT ;do
			cecho "*" cyan ;echo "     $LINE" 
		done
	fi
	#Remove salt key
	if salt-key -L all | grep ${STUSIDS[$INDEX]}.acs.edcc.edu ;then
		salt-key -q -y -d ${STUSIDS[$INDEX]}.acs.edcc.edu
	fi
}

wipestudent()
{
	getethers
	if ! choosestudent ;then
		exit
	fi
	if ! wipevm "$STUDENTINDEX" ;then
		cecho "*" red ;echo "     Unable to wipe $STUDENTINDEX" 
	fi
}


wipeclass()
{
	getethers
	getstudents
	if ! chooseclass;then
		exit
	fi
	clear ; echo ""
	echo "Wiping ${CLASSES[$CLASSINDEX]} VMs"
	for i in $(seq 0 $(( ${#STUCLASSES[@]} - 1 )) ) ;do
		if [[ "${STUCLASSES[$i]}" == "${CLASSES[$CLASSINDEX]}" ]] ;then
			if ! wipevm "$i" ;then
				cecho "*" red ;echo "     Unable to wipe $i" 
			fi
		fi
	done
}

recreatevm()
{
	getethers
	if ! choosestudent ;then
		exit
	fi
	if ! wipevm "${STUDENTINDEX}" ;then
		cecho "*" red ;echo "     Unable to wipe $i" 
		return 1
	fi
	createvm "${STUDENTINDEX}" 
	startvm "${STUDENTINDEX}" 
}

title1()
{
	cecho " $1 " black
}

warn()
{
	cecho "$1" red
}

cleanup() 
{
	# cleans up files that were created during execution
	rm -Rf "$TMPDIR"
}

trap cleanup SIGINT SIGTERM EXIT

setup 
while getopts :dhw:s:p: opt ;do
        case $opt in
                d) set -x ;;
                s) POOLMASTER="$OPTARG" ;;
                h) syntax ;;
                p) PASSWORD="$OPTARG" ;;
                w) isnumber "$OPTARG" && MINSPACE="$OPTARG" ;;
                \?) echo "Unknown option"; syntax ;;
        esac
done
shift $(($OPTIND -1))
if ! getpoolcreds ;then
	exit 1
fi

setupsan


case "$1" in
		listclass) 		listclass    		;;
	    listinfo) 		listinfo    		;;
		listports)		listports			;;
		listconsoles)	listconsoles		;;
		listrunning)	listconsoles		;;
	    createvm)	 	createstudent	 	;;
	    createclass) 	createclass 		;;
	    createroster)	createroster "$2"	;;
	    deletevm)		wipestudent			;;
	    deleteclass)	wipeclass			;;
	    recreatevm)		recreatevm			;;
	    startvm)  	 	startstudent		;;
	    startclass)		startclass			;;
	    restartvm)  	restartstudent		;;
		restartclass)  	restartclass		;;
	    stopvm)			stopstudent			;;
	    stopclass)		stopclass			;;
        showconsole)    consolestudent	    ;;
	    runvm)			runstudent "$@"		;;
	    runclass)		runclass "$@"		;;
	    acceptkeys)     acceptkeys			;;
	    updategrains)   updategrains        ;;
	    updateconfig)	updateconfig		;;
	    updatebase)     updatebaseimage    ;;
	    *)         		syntax       		;;
esac

