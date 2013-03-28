#!/bin/bash

BASEUUID=$(xe vbd-list  vm-name-label=studentbase userdevice=0 params=vdi-uuid --minimal)
echo "Studentbase UUID is $BASEUUID - not deleting"

for i in $(xe vdi-list params=name-label --minimal | sed 's/,/\n/g' | grep '^[89].*_[0-9]' | sort) ;do 
	VDIS=$(xe vdi-list name-label=$i params=uuid --minimal)
	for VDI in $(echo $VDIS | sed 's/,/\n/g') ;do
		if [ ! "$VDI" = "$BASEUUID" ] ;then
			echo "Deleting VDI for $i"
			xe vdi-destroy uuid="$VDI"
		fi
	done
done 



