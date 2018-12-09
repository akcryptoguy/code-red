#!/bin/bash
# Silently install masternodes and insert privkeys

function setup_environment() {
# Set Variables

# create or assign mnprefix



# create root/installtemp if it doesn't exist
	if [ ! -d /root/installtemp ]
	then mkdir /root/installtemp
	else :
	fi

# set hostname variable to the name planted by API installation script
	if [ -e /root/installtemp/vpshostname.info ]
	then HNAME=$(</root/installtemp/vpshostname.info)
	else HNAME=`hostname`
	fi
# read or assign number of masternodes to install
	if [ -e /root/installtemp/vpsnumber.info ]
	then MNS=$(</root/installtemp/vpsnumber.info)
	else MNS=5
	fi
LOGFILE='/root/installtemp/silentinstall.log'
INSTALLDIR='/root/installtemp'
}

function begin_log() {
# Create Log File and Begin
echo -e "---------------------------------------------------- " | tee -a "$LOGFILE"
echo -e " `date +%m.%d.%Y_%H:%M:%S` : SCRIPT STARTED SUCCESSFULLY " | tee -a "$LOGFILE"
echo -e "---------------------------------------------------- " | tee -a "$LOGFILE"
echo -e "--------- AKcryptoGUY's Code Red Script ------------ " | tee -a "$LOGFILE"
echo -e "---------------------------------------------------- \n" | tee -a "$LOGFILE"
echo -e " I am going to create $MNS masternodes and install them\n" | tee -a "$LOGFILE"
# sleep 1
}

function add_cron() {
# reboot logic for status feedback
	(crontab -l ; echo "*/1 * * * * /root/installtemp/postinstall_api.sh") | crontab -
}

function silent_harden() {
	# modify get-hard.sh to add a file when complete, and check for that instead of server-hardening.log
	if [ -e /var/log/server_hardening.log ]
	then echo -e "System seems to already be hard, skipping this part" | tee -a "$LOGFILE"
	else
	cd ~/code-red/vps-harden
	bash get-hard.sh
	fi
}

function install_mns() {
	if [ -e /etc/masternodes/helium_n1.conf ]
	then
	echo -e "Masternodes seem to already be installed, skipping this part" | tee -a "$LOGFILE"
	else
	cd ~/
	sudo git clone https://github.com/heliumchain/vps.git && cd vps
		# update helium.conf template the way I like it
		# this next may not be necessary
		# masternodes may not start syncing the blockchain without a privatekey
		# install the masternodes with the dummykey and replace it later on
		DUMMYKEY='masternodeprivkey=7Qwk3FNnujGCf8SjovuTNTbLhyi8rs8TMT9ou1gKNonUeQmi91Z'
		sed -i "s/^masternodeprivkey=.*/$DUMMYKEY/" config/helium/helium.conf >> $LOGFILE 2>&1
		sed -i "s/^maxconnections=256.*/maxconnections=56/" config/helium/helium.conf >> $LOGFILE 2>&1
	sudo ./install.sh -p helium -c $MNS
	activate_masternodes_helium
	echo -e "It looks like masternodes installed correctly, continuing in 5 seconds... " | tee -a "$LOGFILE"
	sleep 5
	fi
}

function get_genkeys() {

   # the API gives info too: https://www.heliumchain.info/api/address/Sh5k5vub4QnTWGec1XUUuX9AUjCF4eL6or
   
   # Create a file containing all the masternode genkeys you want
   echo -e "Saving genkey(s) to $INSTALLDIR/genkeys \n"  | tee -a "$LOGFILE"
   rm $INSTALLDIR/genkeys 
   touch $INSTALLDIR/genkeys  | tee -a "$LOGFILE"
   for ((i=1;i<=$MNS;i++)); 
   do 
	# create genkey
	/usr/local/bin/helium-cli -conf=/etc/masternodes/helium_n1.conf masternode genkey >> $INSTALLDIR/genkeys   | tee -a "$LOGFILE"
	echo -e "$(sed -n ${i}p $INSTALLDIR/genkeys)" >> $INSTALLDIR/GENKEY$i
	echo "masternodeprivkey=" > $INSTALLDIR/MNPRIV1
	# append "masternodeprivkey="
	paste $INSTALLDIR/MNPRIV1 $INSTALLDIR/GENKEY$i > $INSTALLDIR/GENKEY${i}FIN
	tr -d '[:blank:]' < $INSTALLDIR/GENKEY${i}FIN > $INSTALLDIR/MNPRIVKEY$i
	rm $INSTALLDIR/GENKEY${i}FIN ; rm $INSTALLDIR/GENKEY$i

#        echo -e "MNPRIVKEY$i is set to:"
#        cat $INSTALLDIR/MNPRIVKEY$i

	GENKEYVAR=`cat $INSTALLDIR/MNPRIVKEY$i`
	# this is an alternative that also works  GENKEYVAR=$(</root/installtemp/MNPRIVKEY$i)
	# echo -e "GENKEYVAR = $GENKEYVAR"

sed -i "s/^masternodeprivkey=.*/$GENKEYVAR/" /etc/masternodes/helium_n$i.conf >> $LOGFILE 2>&1
# systemctl stop helium_n$i ; systemctl start helium_n$i

# create file with IP addresses
sed -n -e '/^bind/p' /etc/masternodes/helium_n$i.conf >> $INSTALLDIR/mnipaddresses
# IPADDR=$(sed -n -e '/^bind/p' /etc/masternodes/helium_n1.conf)

done

# remove unneeded files
rm $INSTALLDIR/MNPR*

#remove "bind=" from mnipaddresses
sed -i "s/bind=//" $INSTALLDIR/mnipaddresses >> log 2>&1
	
	echo -e "This is the contents of your file $INSTALLDIR/genkeys:"
	cat $INSTALLDIR/genkeys
	echo -e "\n"
	
	echo -e "This is the contents of your file $INSTALLDIR/mnipaddresses:"
	cat $INSTALLDIR/mnipaddresses
	echo -e "\n"

#lists the garbage I leftover after installation
ls $INSTALLDIR


# read -p "Does this look the way you expected?" LOOKP
 }

function get_blocks() {
# echo "grep "blocks" $INSTALLDIR/getinfo_n1" 
BLOCKS=$(grep "blocks" $INSTALLDIR/getinfo_n1 | tr -dc '0-9')
echo -e "Masternode 1 is currently synced through block $BLOCKS.\n"
}

function check_blocksync() {
# set SECONDS+XXXXX to however long is reasonable to let the initial
# chain sync continue before reporting an error back to the user
end=$((SECONDS+7200))

while [ $SECONDS -lt $end ]; do
    echo -e "Time $SECONDS"
    
	rm -rf $INSTALLDIR/getinfo_n1
	touch $INSTALLDIR/getinfo_n1
	/usr/local/bin/helium-cli -conf=/etc/masternodes/helium_n1.conf getinfo  | tee -a $INSTALLDIR/getinfo_n1
	clear
    
    # if  masternode not running, echo masternode not running and break
    BLOCKS=$(grep "blocks" $INSTALLDIR/getinfo_n1 | tr -dc '0-9')
    echo -e "$BLOCKS is the current number of blocks"
    
    if (($BLOCKS <= 1 )) ; then echo "Masternode is not syncing" ; break
    else sync_check
    fi
    
    if [ "$SYNCED" = "yes" ]; then printf "${lightcyan}" ; echo "Masternode synced" ; printf "${nocolor}" ; break
    else echo -e "Blockchain not synced; will check again in 5 seconds\n"
    sleep 5
    fi
done

    if [ "$SYNCED" = "no" ]; then printf "${lightred}" ; echo "Masternode did not sync in allowed time" ; printf "${nocolor}"
    # radio home that blockchain sync was unsuccessful
    # add curl here
    else : ; fi

echo -e "All done."
}

function sync_check() {
CNT=`/usr/local/bin/helium-cli -conf=/etc/masternodes/helium_n1.conf getblockcount`
# echo -e "CNT is set to $CNT"
HASH=`/usr/local/bin/helium-cli -conf=/etc/masternodes/helium_n1.conf getblockhash ${CNT}`
#echo -e "HASH is set to $HASH"
TIMELINE1=`/usr/local/bin/helium-cli -conf=/etc/masternodes/helium_n1.conf getblock ${HASH} | grep '"time"'`
TIMELINE=$(echo $TIMELINE1 | tr -dc '0-9')
BLOCKS=$(grep "blocks" $INSTALLDIR/getinfo_n1 | tr -dc '0-9')
# echo -e "TIMELINE is set to $TIMELINE"
LTRIMTIME=${TIMELINE#*time\" : }
# echo -e "LTRIMTIME is set to $LTRIMTIME"
NEWEST=${LTRIMTIME%%,*}
# echo -e "NEWEST is set to $NEWEST"
TIMEDIF=$(echo -e "$((`date +%s`-$NEWEST))")
echo -e "This masternode is $TIMEDIF seconds behind the latest block." 
   #check if current
   if (($TIMEDIF <= 60 && $TIMEDIF >= -60))
	then echo -e "The blockchain is almost certainly synced.\n"
	SYNCED="yes"
	else echo -e "That's the same as $(((`date +%s`-$NEWEST)/3600)) hours or $(((`date +%s`-$NEWEST)/86400)) days behind.\n"
	SYNCED="no"
   fi	
}


function restart_server() {
:
echo -e "Going to restart server in 30 seconds. . . "
sleep 30
shutdown -r now
}


# This is where the script actually starts

setup_environment
curl -X POST https://www.heliumstats.online/code-red/status.php -H 'Content-Type: application/json-rpc' -d '{"hostname":"'"$HNAME"'","message": "Beginning Install Script..."}'

begin_log
add_cron

curl -X POST https://www.heliumstats.online/code-red/status.php -H 'Content-Type: application/json-rpc' -d '{"hostname":"'"$HNAME"'","message": "Updating and Hardening Server..."}'
silent_harden
curl -X POST https://www.heliumstats.online/code-red/status.php -H 'Content-Type: application/json-rpc' -d '{"hostname":"'"$HNAME"'","message": "Building Helium Wallet..."}'
install_mns
curl -X POST https://www.heliumstats.online/code-red/status.php -H 'Content-Type: application/json-rpc' -d '{"hostname":"'"$HNAME"'","message": "Configuring Masternodes..."}'
get_genkeys

### for testing
echo -e "Exiting now for testing porpoises...\n"
check_blocksync
exit

curl -X POST https://www.heliumstats.online/code-red/status.php -H 'Content-Type: application/json-rpc' -d '{"hostname":"'"$HNAME"'","message": "Restarting Server..."}'
restart_server

# check_blocksync
# sync_check

echo -e "Log of events saved to: $LOGFILE \n"
