Classstack is an XCP/Xenserver management stack for classroom environments. It's purpose is to manage groups of virtual machines by class. Input data comes from Instructor Briefcase formatted rosters. Instructor Briefcase doesn't export so a copy and paste of the web screen is then saved into a text file in the IBCfiles directory. Use mkroster.sh to convert the Instructor Briefcase file into a classtack roster file in the Rosters directory. 

My Setup
========

1. 8 core iSCSI SAN host with 1 Hard disk and 3 Solid State disks with 3 network cards
2. 6 core host with no local storage repository with 2 network cards
3. 6 core host with no local storage repository with 2 network cards
4. 6 core host with no local storage repository with 2 network cards
5. A VM named classserver that handles DHCP/DNS, web services (Moodle) and a CentOS software mirror. The DHCP/DNS services are provided by dnsmasq. This is required with classstack currently as classstack uses /etc/hosts and /etc/ethers to configure DHCP/DNS for all student VMs.

Machine #1 acts as the iSCSI SAN for all Storage Repositories and the gateway to the outside world. One network card is plugged into the WAN and the other into an internal network switch for the SAN network. The third network card is plugged into a second network switch for the internal class network. The firewall/NAT is provided by iptables and forwards traffic to the first network card and the internal class network.

Machines #2,3, and 4 are all in the same Pool. These hosts have their default storage repository set to the hard disks in machine #1. The SSD disks are configured as Storage Repositories named iSCSI-SSD_0, iSCSI-SDD_1 and iSCSI-SSD_2.


Requirements
============

1. XCP/Xenserver host
2. A default Storage Repository on any type of disk
2. Storage Repository named iSCSI-SSD_${x} where ${x} is a number 0 or greater (starting from 0). This is for extra disks)
3. Xenapi Admin Tools
4. Instructor Briefcase html screengrab (copy/paste)
5. A golden VM image named baseimage

I've written this to 



Install
=======
Git clone both classstack and xenapi-admin-tools. This can be done on your XCP host directly by installing git on XCP/Xenserver - http://grantmcwilliams.com/item/652-install-git-on-xcp-host.
'''
git clone https://github.com/Xenapi-Admin-Project/xenapi-admin-tools.git
git clone https://github.com/grantmcwilliams/classstack.git
'''

Once you've cloned xaptools and classstack you'll need to copy xaptools.lib into the classstack directory and add that directory to your system $PATH. If you add the files to /root/bin they'll already be in your $PATH. I also like symbollically linking vm.sh to vm.

The directory structure should look like this 
'''
cd /root/bin
[root@cloud0 bin]# ls
IBCfiles  mkroster.sh  Rosters  test.sh  vm.sh  wipevdis.sh  wipevm.sh  xaptools.lib
ln -s vm.sh vm
'''

This allows me to just run vm instead of having to type vm.sh.

Cofiguring multiple poolhosts
-----------------------------

To configure multiple poolhosts create the following directory - $HOME/.XECONFIGS. vm.sh will also create the directory the first time it's run and set the permissions appropriately. Inside that directory create ONE file per host with the following information in it. 

'''
LABEL="cloudhost1"
POOLMASTER="cloud1.acs.edcc.edu"
PORT="443"
USERNAME="root"
PASSWORD="password"
'''

The label is freeform so you can name the config anything you want. When you list configs with vm.sh -s list both the LABEL and the POOLMASTER will be displayed. Unless you're using a custom USER or PORT leave these as they are. Change PASSWORD to match your POOLMASTER passsword. This file will be readable only by the owner of the file. This is enforced by classstack.

VM Help
=======

Output of vm.sh help 

  Usage: vm [options] <subcommand>

	Version: 	0.2

	Options:
	-d		turn on shell debugging
	-h		this help text
	-w		number of whitespaces between columns
	-s <host>	remote poolmaster host
	-s list		list stored poolmaster configs
	-p <password>	remote poolmaster password

	Subcommands:
	listclass 	list members of a class
	infoclass 	show information about students
	classrun 	run command on all VMs in a class
	createvm	create a new student VM
	createclass	create VMs for all students in a class
	createroster	convert Instructor Briefcase screen to CSV
	startvm	 	starts the VM for a student
	startclass 	starts the VMs for an entire class
	stopvm 		stops the VM for a student
	stopclass 	stops the VMs for a class
	deletevm	deletes the VM for a student
	deleteclass	deletes all VMs for an entire class
	recreatevm 	shutdown, delete, create then start a vm
	

Create a Class
==============

Create a class by opening up the class roster in Instructor Briefcase. Copy and paste the ENTIRE webpage (top left to bottom right) and paste it into a text file on the machine running classtack.

The format of the resulting file should look like this. 

```
[root@cloud0 IBCfiles]# cat CS125.txt 
Class Roster
QUARTER	ITEM	COURSE	SECTION	TITLE	INSTRUCTOR
Winter 2013	3057	CS 125	SA	LINUX/UNIX I	GRANT MCWILLIAMS

BUILDING
ROOM	CREDIT	START
TIME	END
TIME	DAYS	START
TENTH
DAY	COUNT
METH	SECT
STAT
ALD 0105	 5.0	06:00pm	07:40pm	TTh	01/02/13	01/15/13	 	 

 	SID	STUDENT`S NAME	GRADE	DAY PHONE	EVENING PHONE
1	111-11-1111	BLOW JOE	 	425 111-1111	425 111-1111

Total students	0001	Total students excluding withdrawals	0001
```

In my example below I've named the file CS126.txt. Create a classtack roster by running vm.sh createroster <IBC file>.

vm.sh createroster IBCfiles/CS126.txt

Now that you have a classstack roster file in CSV format you can run some commands on it like vm.sh listclass. 
