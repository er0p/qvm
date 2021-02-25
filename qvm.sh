#!/bin/sh

QVM_PARSER=/home/er0p/wrk/src/qvm/qvm-conf-parser.py

get_ssh_free_port() {
	ssh_port=""
	for port in $(seq 20000 20099);
	do
		echo -ne "\035" | telnet 127.0.0.1 $port > /dev/null 2>&1;
		if [ $? -eq 1 ] ; then
			ssh_port=$port
	       		break;
		fi
	done
	echo $ssh_port
}

get_vnc_free_port() {
	vnc_port=""
	for port in $(seq 5900 5999);
	do
		echo -ne "\035" | telnet 127.0.0.1 $port > /dev/null 2>&1;
		if [ $? -eq 1 ] ; then
			vnc_port=$port
	       		break;
		fi
	done
	if [ ! -z $vnc_port ] ; then
		echo ":"$((vnc_port-5900))
	else
		echo ""
	fi
}

bridge_create() {
	local BRIDGE="$1"
	ip link show $BRIDGE 
	if [ $? -ne 0 ] ; then
		ip link add name $BRIDGE type bridge
		ip link set $BRIDGE up
	else
		echo "bridge $BRIDGE already exists"
	fi
}

bridge_destroy() {
	local BRIDGE="$1"
	ip link show $BRIDGE 
	if [ $? -ne 0 ] ; then
		ip link del name $BRIDGE type bridge
	else
		echo "bridge $BRIDGE doen't exist"
	fi
}

tapm_up()
{
	local TAP="$1"
	local BRIDGE="$2"

	ip tuntap add "$TAP" mode tap
	ip link set "$TAP" promisc on
	ip link set "$TAP" up
	ip link set "$TAP" master "$BRIDGE"
}

tapm_down()
{
	local TAP="$1"

	ip link set "$TAP" down
	ip link set "$TAP" promisc off
	ip link set "$TAP" nomaster
	ip tuntap del "$TAP" mode tap
}

gen_mac_end() {
	hexchars="0123456789ABCDEF"
	#end=$( for i in {1..6} ; do echo -n ${hexchars:$(( $RANDOM % 16 )):1} ; done | sed -e 's/\(..\)/:\1/g' )
	end=$( for i in {1..6} ; do echo -n ${hexchars:$(( $RANDOM % 16 )):1} ; done)
	echo $end
}

qvm_start() {
	local VM=$1
	VNC_PORT=$(get_vnc_free_port)
	SSH_PORT=$(get_ssh_free_port)
	echo $VNC_PORT
	echo $SSH_PORT
	mkfifo /tmp/qvm-pipe-guest-$VM.in /tmp/qvm-pipe-guest-$VM.out
	#exit 0
	QEMU_CMDLINE=$($QVM_PARSER --get $1)
	set -x
	eval $QEMU_CMDLINE
	exit 0

BR_PUBLIC=qvm-pub-br0
BR_PRIVATE=qvm-pub-br1

IF_NAME=$(gen_mac_end)
#echo $IF_NAME
TAP_PUBLIC=P_${IF_NAME}
TAP_PRIVATE=p_${IF_NAME}
MAC_END=$(echo -n $IF_NAME | sed -e "s/\(..\)/:\1/g")
MAC_PUBLIC=02:01:00${MAC_END}
MAC_PRIVATE=02:02:00${MAC_END}
#echo $MAC_PUBLIC
#echo $MAC_PRIVATE
set -x
	bridge_create $BR_PUBLIC
	bridge_create $BR_PRIVATE
	tapm_up $TAP_PUBLIC $BR_PUBLIC
	tapm_up $TAP_PRIVATE $BR_PRIVATE

NETWORK_PUBLIC="-device virtio-net-pci,mac=$MAC_PUBLIC,netdev=netdev_public -netdev tap,id=netdev_public,ifname=$TAP_PUBLIC,script=no,vhost=on"

NETWORK_PRIVATE="-device virtio-net-pci,mac=$MAC_PRIVATE,netdev=netdev_private -netdev tap,id=netdev_private,ifname=$TAP_PRIVATE,script=no,vhost=on"

# Important MQ mode on !!!
#-device virtio-net-pci,netdev=dev1,mac=9a:e8:e9:ea:eb:ec,id=net1,vectors=9,mq=on \
#-netdev tap,id=dev1,vhost=on,script=no,queues=4 \
#-device virtio-net-pci,netdev=dev2,mac=9a:e8:e9:ea:eb:ed,id=net2,vectors=9,mq=on \
#-netdev tap,id=dev2,vhost=on,script=no,queues=4 \

# Important MQ mode off !!!
#		-device virtio-net-pci,netdev=dev1,mac=9a:e8:e9:ea:eb:ec,id=net1,mq=off \
#		-netdev tap,id=dev1,vhost=on,script=no \
#		-device virtio-net-pci,netdev=dev2,mac=9a:e8:e9:ea:eb:ec,id=net2,mq=off \
#		-netdev tap,id=dev2,vhost=on,script=no \

	local FULL_PATH_ROOTFS_IMG=$QVM_DIR/$VM".qcow2"


	set -x
	qemu-system-x86_64 -enable-kvm \
		-machine pc-q35-5.2,kernel-irqchip=split \
		-device intel-iommu,intremap=on \
		-boot d \
		-hda $FULL_PATH_ROOTFS_IMG \
		-m 16G \
		-cpu host \
		-smp $(nproc) \
		-device e1000,netdev=user.0 -netdev user,id=user.0,hostfwd=tcp:127.0.0.1:$SSH_PORT-:22 \
		-serial pipe:/tmp/qvm-pipe-guest-$VM \
		-device virtio-net-pci,netdev=dev1,mac=9a:e8:e9:ea:eb:ec,id=net1,vectors=9,mq=on \
		-netdev tap,id=dev1,vhost=on,script=no,queues=4 \
		-device virtio-net-pci,netdev=dev2,mac=9a:e8:e9:ea:eb:ed,id=net2,vectors=9,mq=on \
		-netdev tap,id=dev2,vhost=on,script=no,queues=4 \
		-daemonize \
		-vnc $VNC_PORT
		#-hda deb-10-rootfs.qcow2 \
		#$NETWORK_PUBLIC \
		#$NETWORK_PRIVATE \

	set +x
	echo $? > $result_qvm_file
}

DIALOG=${DIALOG=dialog}
result_qvm_file=`mktemp 2>/dev/null` || result_qvm_file=/tmp/test$$
tempfile=`mktemp 2>/dev/null` || tempfile=/tmp/test$$
selected_vm_file=`mktemp 2>/dev/null` || selected_vm_file=/tmp/test$$
qvm_list_file=`mktemp 2>/dev/null` || qvm_list_file=/tmp/test$$
trap "rm -f $qvm_list_file $tempfile $selected_vm_file" 0 1 2 5 15

qvm_message_box() {
	$DIALOG --clear --title "qVM" --msgbox "$1" 6 20
}

QVM_CONF=`readlink -f ~/.qvm.conf`
if [ ! -f $QVM_CONF ] ; then
	touch $QVM_CONF
	echo "qvm_dir = "$HOME"/qemu" > $QVM_CONF
fi
QVM_DIR=$(awk -F "=" '/qvm_dir/ {print $2}' $QVM_CONF)
echo $QVM_DIR
if [ -z $QVM_DIR ] ; then
	qvm_message_box "Error: qvm_dir isn't set properly"
	exit $LINENO
fi
#QVM_DIR=`readlink -f ~/qemu/templates`
#QVM_CONF=`readlink -f ~/.qvm.conf`

#if [ ! -f $QVM_CONF ] ; then 
#	touch $QVM_DIR
#fi

qvm_check_state() {
	local VM=$1
	ps_ax=`ps ax | grep qemu | grep $VM | awk '{print $1}'`
	#ps_ax=`ps ax | grep qemu | grep $VM | sed "s/^\s*//" | cut -d' ' -f-1 `
	if [ ! -z $ps_ax ] ; then
		kill -0 $ps_ax
		if [ $? -eq 0 ] ; then
			echo "working"
		else
			echo "not responding"
		fi
	else
			echo "stopped"
	fi
}

qvm_stop() {
	local VM=$1
	ps_ax=`ps ax | grep qemu | grep $VM`
	pid_vm=`echo $ps_ax | cut -d' ' -f-1 `
	kill $pid_vm
	echo $? > $result_qvm_file
	TAP_NAME=$( echo $ps_ax | sed -nre "s/^.*,ifname=._(.{6}),script.*$/\1/p")
	TAP_PUBLIC="P_"${TAP_NAME}
	TAP_PRIVATE="p_"${TAP_NAME}
	tapm_down $TAP_PUBLIC
	tapm_down $TAP_PRIVATE
	exit `cat $result_qvm_file`
}

qvm_wizard(){
	echo "TODO: WIZARD"
}

QVM_LIST=""
qvm_list() {
	QVM_LIST=""
	local CNT=0
	local TMP_LIST=""
	$QVM_PARSER --list
	for i in $($QVM_PARSER --list) ;
	#for i in $(find ${QVM_DIR} -name "*.qcow2" 2>/dev/null) ;
	do
		CNT=$((CNT+1))
		#ENTRY="$(basename $i | cut -d '.' -f 1)"
		ENTRY="$i"
		STATE=$(qvm_check_state $ENTRY)
		#TMP_LIST=${TMP_LIST}printf "%d %s\n" $CNT "$ENTRY"
		TMP_LIST=${TMP_LIST}$ENTRY" "$STATE" "
		QVM_LIST=${QVM_LIST}${ENTRY}" "
		#echo -e "${TMP_LIST}"
	done
	if [ $CNT -eq 0 ] ; then
		#qvm_message_box "No VMs found"
		$DIALOG --clear --title "qVM" \
			--yesno "No VMs found.\nWould you like to create new VM instance?" 7 60
			#--backtitle "No VMs found" \
		if [ $? -eq 0 ] ; then
			qvm_wizard
		fi
		exit 0
	fi
	echo $CNT
	echo $QVM_LIST > $qvm_list_file
	echo $QVM_LIST
	echo $TMP_LIST
	$DIALOG --clear --title "qVM list" --menu "Select qVM:" $((CNT+10)) 40 4 \
$TMP_LIST \
2> $selected_vm_file
#	exit 1
#	$DIALOG --clear --title "qVM list" \
#		--menu "Select qVM:"  $CNT 51 4 \
#			"list" "show all qVMs and its status" \
#			#$TMP_LIST 2> $selected_vm_file
#			#        "list" "show all qVMs and its status" \
			retval=$?

			vm=`cat $selected_vm_file`
			echo $vm

			case $retval in
				0)
					echo $vm;;
				1)
					echo "User didn't provide output"; exit 0;;
				255)
					echo "Pressed ESC button"; exit 0;;
			esac
		}

#if [ ! -d $QVM_DIR ] ; then 
#	mkdir $QVM_DIR
#	mkdir $QVM_DIR/templates
#fi

get_vm_vnc_port() {
	SEL_VM=`cat $selected_vm_file`
	vnc_port=`ps ax | grep qemu | grep $SEL_VM | sed -nre "s/^.*-vnc\s(:[0-9]+).*$/\1/p"`
	echo $vnc_port
}
get_vm_ssh_port() {
	SEL_VM=`cat $selected_vm_file`
	ssh_port=`ps ax | grep qemu | grep $SEL_VM | sed -nre "s/^.*hostfwd=tcp:.*:([0-9]+)-:.*$/\1/p"`
	echo $ssh_port
}

qvm_action() {
	local VM=$1
	$DIALOG --clear --title "qVM action menu" \
		--menu "Select qVM action to do" 20 51 4 \
		"attach_ssh"  "ssh to qVM" \
		"attach_vnc"  "VNCViewer to qVM" \
		"start"  "start qVM" \
		"stop" "stop qVM" \
		"list" "show all qVMs and its status" \
		2> $tempfile
			retval=$?

			action=`cat $tempfile`

			case $retval in
				0)
					echo "Entered: \"$action\"";;
				1)
					echo "User didn't provide output"; exit 0;;
				255)
					echo "Pressed ESC button"; exit 0;;
			esac

			case $action in
				attach_vnc)
					if [ "$(qvm_check_state `cat $selected_vm_file`)" = "working" ] ; then
						vnc_port=$(get_vm_vnc_port)
						nohup vncviewer $vnc_port &
					else
						exit 1
						qvm_message_box "VM "`cat $selected_vm_file | tr '\n' ' '`" isn't running" 
					fi
					;;
				attach_ssh)
					if [ "$(qvm_check_state `cat $selected_vm_file`)" = "working" ] ; then
						
						VM=$(cat $selected_vm_file)
						ssh_user=$($QVM_PARSER --keyvalue $VM ssh_user)
						if [ $? -ne 0 ] ; then
							ssh_user="root"
						fi
						ssh_port=$(get_vm_ssh_port)
						echo "ssh_port=$ssh_port"
						ssh -i ~/.ssh/id_rsa_qvm -p $ssh_port $ssh_user@127.0.0.1 
					else
						#qvm_message_box "VM "`cat $selected_vm_file | tr '\n' ' '`" isn't running" 
						exit 1
					fi
					;;
				start)
					qvm_start $VM;;
				stop)
					qvm_stop  $VM;;
				1)
					echo "User didn't provide output"; exit 0;;
				255)
					echo "Pressed ESC button"; exit 0;;
			esac
		}
qvm_list
SEL_VM=`cat $selected_vm_file`
qvm_action $SEL_VM

exit `cat $result_qvm_file`

dialog --menu "Select qVM action:" 10 30 \
       	1 "start" \
	2 stop \
	3 show \ 
	2>$QVM_DIALOG_ANSWER

retval=$?
case $retval in
	0)
		echo "Вы ввели `cat $QVM_DIALOG_ANSWER`"
		;;
	1)
		echo "User didn't provide output";;
	255)
		if test -s $QVM_DIALOG_ANSWER ; then
			cat $QVM_DIALOG_ANSWER
		else
			echo "Pressed ESC button"
		fi
		;;
esac

exit 0

dialog --radiolist "Select QVM action:" 1000 100 10\
  1 "Start qVM" on \
  2 "Stop qVM" off \
  3 "Show qVM" off

echo "$?"
exit 13




qvm_name=${@: -1}

start_fl=0
stop_fl=0


ARGUMENT_LIST=(
    "start"
    "stop"
    "list"
)


# read arguments
opts=$(getopt \
    --longoptions "$(printf "%s," "${ARGUMENT_LIST[@]}")" \
    --name "$(basename "$0")" \
    --options "" \
    -- "$@"
)

eval set --$opts

while [[ $# -gt 0 ]]; do
	case "$1" in
		--start)
			start_fl=1
			shift 1
			;;
		--stop)
			stop_fl=1
			shift 1
			;;
		*)
			break
			;;
	esac
done


echo $start_fl" "$stop_fl" "$qvm_name

if [ $stop_fl -eq 1 ] ; then
	#set -x
	ps_ax=`ps ax | grep qemu | grep $qvm_name | cut -d' ' -f-1 `
	set +x
	#echo $ps_ax
	kill $ps_ax

	tapm_down $TAP_PUBLIC
	tapm_down $TAP_PRIVATE
	exit 0
fi



# hostfwd=[tcp|udp]:[hostaddr]:hostport-[guestaddr]:guestport
# -device e1000,netdev=user.0 -netdev user,id=user.0,hostfwd=tcp:192.168.8.100:2222-:22 \


