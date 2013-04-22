Classstack is an XCP/Xenserver management stack for classroom environments. It's purpose is to manage groups of virtual machines by class. Input data comes from Instructor Briefcase formatted rosters. Instructor Briefcase doesn't export so a copy and paste of the web screen is then saved into a text file in the IBCfiles directory. Use mkroster.sh to convert the Instructor Briefcase file into a classtack roster file in the Rosters directory. 

Setup
======
Git clone both classstack and xenapi-admin-tools. This can be done on your XCP host directly by installing git on XCP/Xenserver - http://grantmcwilliams.com/item/652-install-git-on-xcp-host.

git clone https://github.com/Xenapi-Admin-Project/xenapi-admin-tools.git
git clone https://github.com/grantmcwilliams/classstack.git

Once you've cloned xaptools and classstack you'll need to copy xaptools.lib into the classstack directory and add that directory to your system $PATH. 

The directory structure should look like this 
[root@cloud0 bin]# ls
IBCfiles  mkroster.sh  Rosters  test.sh  vm.sh  wipevdis.sh  wipevm.sh  xaptools.lib

I like putting these files into /root/bin so they're in my path. I also like symbolically linking vm.sh to vm. 

cd /root/bin
ln -s vm.sh vm

This allows me to just run vm instead of having to type vm.sh.

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

