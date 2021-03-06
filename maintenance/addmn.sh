#!/bin/bash

# exit with error if not run as root/sudo
if [ "$(id -u)" != "0" ]
then echo -e "\n Please re-run as root or sudo.\n"
    exit 1
fi

# Set common variables
. /var/tmp/nodevalet/maintenance/vars.sh

# check if $POJECT ONLYNET=4, exit with warning
if [ "$ONLYNET" = 4 ]
then echo -e "\n${lightred} $PROJECTt only supports IPv4 and one masternode per VPS.${nocolor}"
    echo -e " No changes were made. This script will now exit.\n"
    exit
fi

# check for possible number of new masternodes
NODES=$(grep MemTotal /proc/meminfo | awk '{print $2 / 1024 / 340}')
MAXNODES=$(echo "$NODES" | awk '{print int($1+0.5)}')
let PNODES=$MAXNODES-$MNS
(($PNODES <= 0)) && echo " ${lightred}This server cannot support any more masternodes${nocolor}\n" && exit


function collect_nnodes() {

    touch $INSTALLDIR/temp/updating

    # read first argument to string
    NNODES=$1

    # if no argument was given, give instructions and ask for one
    if [ -z "$NNODES" ]
    then clear
        echo -e "\n${white} This scriptlet permits you to add new $PROJECTt masternodes to your VPS.\n"
        echo -e " ${lightcyan}This VPS is currently running $MNS masternodes and supports $MAXNODES masternodes"
        echo -e " How many new masternodes would you like to add? ${nocolor}\n"
    fi

    while :; do
        if [ -z "$NNODES" ] ; then read -p " --> " NNODES ; fi
        [[ $NNODES =~ ^[0-9]+$ ]] || { printf "${lightred}"; echo -e "\n --> I only recognize numbers; enter a number between 0 and $PNODES...\n"; NNODES=""; printf "${nocolor}"; continue; }
        if (($NNODES >= 0 && $NNODES <= $PNODES)); then break
        else echo -e "\n${lightred} --> That's too many; please enter a number between 0 and $PNODES.${nocolor}\n"
            NNODES=""
        fi
    done

    # exit if user is adding 0 masternodes
    if [ "$NNODES" = 0 ]
    then echo -e "\n${lightred} You have selected to add no new masternodes.${nocolor}"
        echo -e " No changes were made. This script will now exit.\n"
        rm $INSTALLDIR/temp/updating --force
        restore_crons
        exit
    fi

    echo -e "\n${lightpurple} Perfect.  We are going to try and add $NNODES new MN(s) to this VPS.${nocolor}\n"
    LOGFILE='/var/tmp/nodevalet/logs/silentinstall.log'
    echo -e " $(date +%m.%d.%Y_%H:%M:%S) : Running addmn.sh"  >> $LOGFILE
    echo -e " ${lightcyan}User has requested to add $NNODES new MN(s) to this VPS.${nocolor}\n"  >> $LOGFILE
}

function collect_api() {
    # read API key if it exists, if not prompt for it

    echo -e "${white} Adding $NNODES masternode(s) to your VPS requires 1 NodeValet Deployment credit.${nocolor}\n"
    APITEST="https://api.nodevalet.io/txdata.php?coin=audax&address=APKSdh4QyVGGYBLs7wFbo4MjeXwK3GBD1o&key=$VPSAPI"
    curl -s "$APITEST" > $INSTALLDIR/temp/API.test.json
    APITESTRESPONSE=$(cat $INSTALLDIR/temp/API.test.json)
    ! [[ "${APITESTRESPONSE}" == "Invalid key" ]] && echo -e "${lightgreen} Your original NodeValet Deployment Key is still valid\n${nocolor}" && rm -f $INSTALLDIR/temp/API.test.json && GOODKEY='true'

    if [[ "${GOODKEY}" == "true" ]]
    then :
    else echo -e "${lightred} Your original NodeValet Deployment Key is no longer valid\n${nocolor}"
        echo -e " Before we can begin, we need to collect your NodeValet API Key."
        echo -e "   ! ! Please double check your NodeValet API Key for accuracy ! !"
        cp $INFODIR/vps.api.info $INFODIR/vpsapi.old
        rm -rf $INFODIR/vps.api.info
        touch $INFODIR/vps.api.info
        echo -e -n " "
        while :; do
            echo -e "\n${cyan} Please enter your NodeValet API Key.${nocolor}"
            read -p "  --> " VPSAPI
            echo -e "\n You entered this API Key: ${VPSAPI} "
            read -n 1 -s -r -p "  ${cyan}--> Is this correct? y/n  ${nocolor}" VERIFY
            if [[ $VERIFY == "y" || $VERIFY == "Y" ]]
            then APITEST="https://api.nodevalet.io/txdata.php?coin=audax&address=APKSdh4QyVGGYBLs7wFbo4MjeXwK3GBD1o&key=$VPSAPI"
                curl -s "$APITEST" > $INSTALLDIR/temp/API.test.json
                APITESTRESPONSE=$(cat $INSTALLDIR/temp/API.test.json)
                ! [[ "${APITESTRESPONSE}" == "Invalid key" ]] && echo -e "${lightgreen}NodeValet API Key is valid${nocolor}" && rm -f $INSTALLDIR/temp/API.test.json && break
                echo -e "${lightred}The API Key you entered is invalid.${nocolor}"
            else echo " "
            fi
        done
        echo -e "$VPSAPI" > $INFODIR/vps.api.info
        echo -e " NodeValet API Key set to : $VPSAPI" >> $LOGFILE
    fi
}

function collect_addresses() {
    # Gather new MN addresses
    # Pull BLOCKEXP from $PROJECT.env
    BLOCKEX=$(grep ^BLOCKEXP=unsupported $INSTALLDIR/nodemaster/config/"$PROJECT"/"$PROJECT".env)
    if [ -n "$BLOCKEX" ]
    then echo -e "\n ${lightcyan}NodeValet found no fully-supported block explorer.${nocolor}"
        echo -e " You must manually enter your transaction IDs for new masternodes to work.\n"
        echo -e "\n${white} In order to retrieve your transaction IDs, you should first send the required "
        echo -e " collateral to each new masternode addresses and wait for at least 1 "
        echo -e " confirmation. Once you have done this, open${yellow} debug console ${white}and typically "
        echo -e " you will enter the command ${yellow}masternode outputs${white}. This will display a list of"
        echo -e " all of your valid collateral transactions. You will need pick out the"
        echo -e " new transactions and their index numbers so NodeValet can generate the"
        echo -e " masternode.conf file that you will paste into your local wallet.\n"
        echo -e " A transaction ID and index should look pretty similar to this: "
        echo -e "${yellow} b1097524b3e08f8d7e71be99b916b38702269c6ea37161bba49ba538a631dd56 1 ${nocolor}"
        let TNODES=$NNODES+$MNS
        for ((i=($MNS+1);i<=$TNODES;i++));
        do
            echo -e "${cyan}"
            while :; do
                echo -e "\n Please enter the transaction ID and index for masternode #$i"
                echo -e " Leave this field blank if this masternode is not yet funded.${nocolor}"
                read -p "  --> " UTXID
                echo -e "\n${white} You entered the transaction ID and index:"
                echo -e "${yellow} ${UTXID} ${cyan}"
                read -n 1 -s -r -p "  --> Is this correct? y/n  " VERIFY
                if [[ $VERIFY == "y" || $VERIFY == "Y" ]]
                then echo -e -n "${nocolor}"
                    # save TXID to vps.mntxdata.info if length is greater than 5
                    if [ ${#UTXID} -ge 5 ]; then echo -e "$UTXID" >> $INFODIR/vps.mntxdata.info
                    else echo -e "null null" >> $INFODIR/vps.mntxdata.info
                    fi
                    break
                fi
            done
            echo -e -n "${nocolor}"
        done
        echo -e " User manually entered TXIDs and indices for $NNODES new masternodes\n"

    else echo -e "\n${lightpurple} Next, we need to collect your $NNODES new masternode address(es).${nocolor}"
        let TNODES=$NNODES+$MNS
        for ((i=($MNS+1);i<=$TNODES;i++));
        do
            while :; do
                echo -e "\n${cyan} Please enter the $PROJECTt address for new masternode #$i${nocolor}"
                read -p "  --> " MNADDP
                # echo -e "\n You entered the address: ${MNADDP} \n"
                echo -e "\n"

                CURLAPI=$(echo -e "$BLOCKEXP${MNADDP}&key=$VPSAPI")

                # store NoveValets response in a local file
                curl -s "$CURLAPI" > $INSTALLDIR/temp/API.response$i.json

                # read curl API response into variable
                APIRESPONSE=$(cat $INSTALLDIR/temp/API.response$i.json)

                # check if API response is invalid
                [[ "${APIRESPONSE}" == "Invalid key" ]] && echo -e "NodeValet replied: ${lightred}Invalid API Key${nocolor}"   | tee -a "$LOGFILE" && echo -e "null\nnull" > $INSTALLDIR/temp/TXID$i
                [[ "${APIRESPONSE}" == "Invalid coin" ]] && echo -e "NodeValet replied: ${lightred}Invalid Coin${nocolor}"   | tee -a "$LOGFILE" && echo -e "null\nnull" > $INSTALLDIR/temp/TXID$i
                [[ "${APIRESPONSE}" == "Invalid address" ]] && echo -e "NodeValet replied: ${lightred}Invalid Address${nocolor}"   | tee -a "$LOGFILE" && echo -e "null\nnull" > $INSTALLDIR/temp/TXID$i
                [[ "${APIRESPONSE}" == "null" ]] && echo -e "NodeValet replied: Null ${lightred}(no collateral transaction found)${nocolor}"   | tee -a "$LOGFILE" && echo -e "null\nnull" > $INSTALLDIR/temp/TXID$i

                # check if stored file (API.response$i.json) has NOT length greater than zero
                ! [[ -s $INSTALLDIR/temp/API.response$i.json ]] && echo "--> Server did not respond or response was empty"   | tee -a "$LOGFILE" && echo -e "null\nnull" > $INSTALLDIR/temp/TXID$i

                # check if stored file (TXID$i) does NOT exist (then no errors were detected above)
                ! [[ -e $INSTALLDIR/temp/TXID$i ]] && echo "It looks like this is a valid masternode address." && echo "NodeValet replied with a collateral transaction ID for masternode $i"  | tee -a "$LOGFILE" && cat $INSTALLDIR/temp/API.response$i.json | jq '.["txid","txindex"]' | tr -d '["]' > $INSTALLDIR/temp/TXID$i && cat $INSTALLDIR/temp/API.response$i.json | jq '.'

                TX=$(echo $(cat $INSTALLDIR/temp/TXID$i))
                echo -e "$TX" > $INSTALLDIR/temp/TXID$i
                echo -e " NodeValet API returned $TX as txid for masternode $i " >> $LOGFILE

                echo " "
                read -n 1 -s -r -p "${cyan}  --> Is this what you expected? y/n  ${nocolor}" VERIFY
                echo " "
                if [[ $VERIFY == "y" || $VERIFY == "Y" || $VERIFY == "yes" || $VERIFY == "Yes" ]]
                then echo -e "$TX" >> $INFODIR/vps.mntxdata.info
                    rm $INSTALLDIR/temp/API.response$i.json --force
                    break
                else rm $INSTALLDIR/temp/TXID$i --force
                fi
            done
            echo -e "$MNADDP" >> $INFODIR/vps.mnaddress.info
            echo -e " -> New masternode $i address is: $MNADDP\n"
        done
    fi
}

function install_mns() {

    cd $INSTALLDIR/nodemaster
    echo -e "Invoking local Nodemaster's VPS script to add additional masternodes" | tee -a "$LOGFILE"
    echo -e "Launching Nodemaster using bash install.sh -n $ONLYNET -p $PROJECT" -c "$TNODES" | tee -a "$LOGFILE"
    sudo bash install.sh -n $ONLYNET -p "$PROJECT" -c "$TNODES"
    echo -e "\n"

        # add support for deterministic wallets so they don't break everything
        if [ "${PROJECT,,}" = "mue" ]
        then echo -e "${lightcyan} Setting masternode services to not use deterministic seeds for wallets\n${nocolor}" | tee -a "$LOGFILE"
            let TNODES=$NNODES+$MNS
            for ((i=($MNS+1);i<=$TNODES;i++));
            do
                sed -i "s/${MNODE_DAEMON}/${MNODE_DAEMON} -usehd=0/" /etc/systemd/system/${PROJECT}_n$i.service >> $LOGFILE 2>&1
            done
        fi

    # check for presence of config file to presume success, cancel and report error if does not exist

    # check if $PROJECTd was built correctly and started
    if ps -A | grep "$MNODE_BINARIES" > /dev/null
    then
        # report back to mother
        if [ -e "$INFODIR"/fullauto.info ] ; then echo -e "Reporting ${MNODE_BINARIES} build success to mother" | tee -a "$LOGFILE" ; curl -X POST https://www.nodevalet.io/status.php -H 'Content-Type: application/json-rpc' -d '{"hostname":"'"$HNAME"'","message": "Process '"$MNODE_DAEMON"' has started ..."}' && echo -e " " ; fi

    else
        for ((H=1;H<=10;H++));
        do
            if ps -A | grep "$MNODE_BINARIES" > /dev/null
            then
                # report back to mother
                if [ -e "$INFODIR"/fullauto.info ] ; then echo -e "Reporting ${MNODE_BINARIES} build success to mother" | tee -a "$LOGFILE" ; curl -X POST https://www.nodevalet.io/status.php -H 'Content-Type: application/json-rpc' -d '{"hostname":"'"$HNAME"'","message": "Process '"$MNODE_DAEMON"' started after '"$H"' seconds ..."}' && echo -e " " ; fi
                break
            else

                if [ "${H}" = "10" ]
                then echo " "
                    echo -e "After $H (H) seconds, $MNODE_DAEMON is still not running" | tee -a "$LOGFILE"
                    echo -e "so we are going to abort this installation now. \n" | tee -a "$LOGFILE"
                    echo -e "Reporting ${MNODE_DAEMON} build failure to mother" | tee -a "$LOGFILE"
                    if [ -e "$INFODIR"/fullauto.info ] ; then curl -X POST https://www.nodevalet.io/status.php -H 'Content-Type: application/json-rpc' -d '{"hostname":"'"$HNAME"'","message": "Error: '"$MNODE_DAEMON"' failed to build or start after 10 seconds"}' && echo -e " " ; fi
                    rm $INSTALLDIR/temp/updating --force
                    restore_crons
                    exit
                fi
                sleep 1
            fi
        done
    fi
}

function change_vpsnumber() {
    echo -e "$TNODES" > $INFODIR/vps.number.info
    echo -e "Changing total number of masternodes on this server to $TNODES. \n" | tee -a "$LOGFILE"
}

function create_genkeys() {
    # create new MN genkeys

    echo -e "Creating masternode.conf variables and files for all $TNODES masternodes" | tee -a "$LOGFILE"

    if [ "${PROJECT,,}" = "smart" ] ; then echo "smartnodeprivkey=" > $INSTALLDIR/temp/MNPRIV1
    elif [ "${PROJECT,,}" = "zcoin" ] ; then echo "znodeprivkey=" > $INSTALLDIR/temp/MNPRIV1
else echo "masternodeprivkey=" > $INSTALLDIR/temp/MNPRIV1 ; fi

    # gather existing masternode variables as files for .conf
    for ((i=1;i<=$MNS;i++));
    do
        echo -e "$(sed -n ${i}p $INFODIR/vps.genkeys.info)" > $INSTALLDIR/temp/GENKEY$i

        # append "masternodeprivkey="
        paste $INSTALLDIR/temp/MNPRIV1 $INSTALLDIR/temp/GENKEY$i > $INSTALLDIR/temp/GENKEY${i}FIN
        tr -d '[:blank:]' < $INSTALLDIR/temp/GENKEY${i}FIN > $INSTALLDIR/temp/MNPRIVKEY$i
    done

    for ((i=($MNS+1);i<=$TNODES;i++));
    do
        for ((P=1;P<=35;P++));
        do
            # create masternode genkeys (smart is special "smartnodes")
            if [ -e $INSTALLDIR/temp/bogus ] ; then :
            elif [ "${PROJECT,,}" = "smart" ] ; then /usr/local/bin/"${MNODE_DAEMON::-1}"-cli -conf=/etc/masternodes/"${PROJECT}"_n1.conf smartnode genkey >> $INFODIR/vps.genkeys.info
            elif [ "${PROJECT,,}" = "pivx" ] ; then /usr/local/bin/"${MNODE_DAEMON::-1}"-cli -conf=/etc/masternodes/"${PROJECT}"_n1.conf createmasternodekey >> $INFODIR/vps.genkeys.info
            elif [ "${PROJECT,,}" = "squorum" ] ; then /usr/local/bin/"${MNODE_DAEMON::-1}"-cli -conf=/etc/masternodes/"${PROJECT}"_n1.conf createmasternodekey >> $INFODIR/vps.genkeys.info
        else /usr/local/bin/"${MNODE_DAEMON::-1}"-cli -conf=/etc/masternodes/"${PROJECT}"_n1.conf masternode genkey >> $INFODIR/vps.genkeys.info ; fi
            echo -e "$(sed -n ${i}p $INFODIR/vps.genkeys.info)" > $INSTALLDIR/temp/GENKEY$i

            KEYXIST=$(<$INSTALLDIR/temp/GENKEY$i)

            # add extra pause for wallets that are slow to start
            if [ "${PROJECT,,}" = "polis" ] ; then SLEEPTIME=15 ; else SLEEPTIME=3 ; fi

            # check if GENKEY variable is empty; if so stop script and report error
            if [ ${#KEYXIST} = "0" ]
            then echo -e " ${MNODE_DAEMON::-1}-cli couldn't create genkey $i; engine likely still starting up"
                echo -e " --> Waiting for $SLEEPTIME seconds before trying again... loop $P"
                sleep $SLEEPTIME
            else break
            fi

            if [ ${#KEYXIST} = "0" ] && [ "${P}" = "35" ]
            then echo " "
                # [ -e $INFODIR/fullauto.info ] && curl -X POST https://www.nodevalet.io/status.php -H 'Content-Type: application/json-rpc' -d '{"hostname":"'"$HNAME"'","message": "Error: Could not generate masternode genkeys"}' && echo -e " "
                echo -e "Problem creating masternode $i. Could not obtain masternode genkey." | tee -a "$LOGFILE"
                echo -e "I patiently tried 35 times but something isn't working correctly.\n" | tee -a "$LOGFILE"
                rm $INSTALLDIR/temp/updating --force
                restore_crons
                exit
            fi
        done
    done
}

function sub_genkeys() {
    echo -e "Inserting new genkey(s) into new masternode.conf file(s) \n" | tee -a "$LOGFILE"

    for ((i=($MNS+1);i<=$TNODES;i++));
    do

        # append "masternodeprivkey="
        paste $INSTALLDIR/temp/MNPRIV1 $INSTALLDIR/temp/GENKEY$i > $INSTALLDIR/temp/GENKEY${i}FIN
        tr -d '[:blank:]' < $INSTALLDIR/temp/GENKEY${i}FIN > $INSTALLDIR/temp/MNPRIVKEY$i

        # assign GENKEYVAR to the full line masternodeprivkey=xxxxxxxxxx
        GENKEYVAR=$(cat $INSTALLDIR/temp/MNPRIVKEY$i)

        # insert new genkey into project_n$i.conf files (special case for smartnodes)
        if [ "${PROJECT,,}" = "smart" ]
        then
            sed -i "s/^smartnodeprivkey=.*/$GENKEYVAR/" /etc/masternodes/"${PROJECT}"_n$i.conf
            masternodeprivkeyafter=$(grep ^smartnodeprivkey /etc/masternodes/"${PROJECT}"_n$i.conf)
            echo -e " Privkey in /etc/masternodes/${PROJECT}_n$i.conf after sub is : " >> $LOGFILE
            echo -e " $masternodeprivkeyafter" >> $LOGFILE
    elif [ "${PROJECT,,}" = "zcoin" ]
        then
            sed -i "s/^znodeprivkey=.*/$GENKEYVAR/" /etc/masternodes/"${PROJECT}"_n$i.conf
            masternodeprivkeyafter=$(grep ^znodeprivkey /etc/masternodes/"${PROJECT}"_n$i.conf)
            echo -e " Privkey in /etc/masternodes/${PROJECT}_n$i.conf after sub is : " >> $LOGFILE
            echo -e " $masternodeprivkeyafter" >> $LOGFILE

        else
            sed -i "s/^masternodeprivkey=.*/$GENKEYVAR/" /etc/masternodes/"${PROJECT}"_n$i.conf
            masternodeprivkeyafter=$(grep ^masternodeprivkey /etc/masternodes/"${PROJECT}"_n$i.conf)
            echo -e " Privkey in ${PROJECT}_n$i.conf after sub is : " >> $LOGFILE
            echo -e " $masternodeprivkeyafter" >> $LOGFILE
        fi
    done

}

function start_mns() {
    for ((i=($MNS+1);i<=$TNODES;i++));
    do
        touch $INSTALLDIR/temp/gettinginfo
        clonesync $i
        rm $INSTALLDIR/temp/gettinginfo --force
        # display countdown timer on screen
        echo -e " Please wait patiently while the masternodes start-- do not interrupt!"
        seconds=90; date1=$((`date +%s` + $seconds));
        while [ "$date1" -ge `date +%s` ]; do
            echo -ne "          $(date -u --date @$(($date1 - `date +%s` )) +%H:%M:%S)\r";
            sleep 0.5
        done
    done
    echo -e " New masternodes have all been started \n"

}

function make_newconf() {
    echo -e " Creating new masternode.conf... \n" | tee -a "$LOGFILE"

    cp $INSTALLDIR/masternode.conf $INSTALLDIR/masternode.conf.bak # backup original masternode.conf
    rm $INSTALLDIR/masternode.conf --force
    rm $INFODIR/vps.mnaliases.info --force
    rm $INFODIR/vps.ipaddresses.info --force
    touch $INSTALLDIR/masternode.conf # create initial masternode.conf file
    touch $INFODIR/vps.mnaliases.info
    touch $INFODIR/vps.ipaddresses.info

    cat <<EOT >> $INSTALLDIR/masternode.conf
#######################################################
# Masternode.conf settings to paste into Local Wallet #
#######################################################
EOT
    echo -e "Creating masternode.conf variables and files for $TNODES masternodes" | tee -a "$LOGFILE"
    MNPREFIX=$(hostname)

    for ((i=1;i<=$TNODES;i++));
    do
        # get or iterate mnprefixes
        echo -e "${MNPREFIX}-MN$i" >> $INFODIR/vps.mnaliases.info

        # create masternode prefix files
        echo -e "$(sed -n ${i}p $INFODIR/vps.mnaliases.info)" >> $INSTALLDIR/temp/MNALIAS$i

        # create masternode address files
        echo -e "$(sed -n ${i}p $INFODIR/vps.mnaddress.info)" > $INSTALLDIR/temp/MNADD$i

        # append "masternodeprivkey="
        paste $INSTALLDIR/temp/MNPRIV1 $INSTALLDIR/temp/GENKEY$i > $INSTALLDIR/temp/GENKEY${i}FIN
        tr -d '[:blank:]' < $INSTALLDIR/temp/GENKEY${i}FIN > $INSTALLDIR/temp/MNPRIVKEY$i

        # assign GENKEYVAR to the full line masternodeprivkey=xxxxxxxxxx
        GENKEYVAR=$(cat $INSTALLDIR/temp/MNPRIVKEY$i)

        # insert new genkey into project_n$i.conf files (special case for smartnodes)
        if [ "${PROJECT,,}" = "smart" ]
        then
            sed -i "s/^smartnodeprivkey=.*/$GENKEYVAR/" /etc/masternodes/"${PROJECT}"_n$i.conf
            masternodeprivkeyafter=$(grep ^smartnodeprivkey /etc/masternodes/"${PROJECT}"_n$i.conf)
            echo -e " Privkey in /etc/masternodes/${PROJECT}_n$i.conf after sub is : " >> $LOGFILE
            echo -e " $masternodeprivkeyafter" >> $LOGFILE
    elif [ "${PROJECT,,}" = "zcoin" ]
        then
            sed -i "s/^znodeprivkey=.*/$GENKEYVAR/" /etc/masternodes/"${PROJECT}"_n$i.conf
            masternodeprivkeyafter=$(grep ^znodeprivkey /etc/masternodes/"${PROJECT}"_n$i.conf)
            echo -e " Privkey in /etc/masternodes/${PROJECT}_n$i.conf after sub is : " >> $LOGFILE
            echo -e " $masternodeprivkeyafter" >> $LOGFILE

        else
            sed -i "s/^masternodeprivkey=.*/$GENKEYVAR/" /etc/masternodes/"${PROJECT}"_n$i.conf
            masternodeprivkeyafter=$(grep ^masternodeprivkey /etc/masternodes/"${PROJECT}"_n$i.conf)
            echo -e " Privkey in ${PROJECT}_n$i.conf after sub is : " >> $LOGFILE
            echo -e " $masternodeprivkeyafter" >> $LOGFILE
        fi

        # create file with IP addresses
        sed -n -e '/^bind/p' /etc/masternodes/"${PROJECT}"_n$i.conf >> $INFODIR/vps.ipaddresses.info

        # remove "bind=" from vpsipaddresses.info
        sed -i "s/bind=//" $INFODIR/vps.ipaddresses.info 2>&1

        # the next line produces the IP addresses for this masternode
        echo -e "$(sed -n ${i}p $INFODIR/vps.ipaddresses.info)" > $INSTALLDIR/temp/IPADDR$i

        PUBLICIP=$(sudo /usr/bin/wget -q -O - http://ipv4.icanhazip.com/ | /usr/bin/tail)
        PRIVATEIP=$(sudo ifconfig $(route | grep default | awk '{ print $8 }') | grep "inet addr" | awk -F: '{print $2}' | awk '{print $1}')

        # to enable functionality in headless mode for LAN connected VPS, replace private IP with public IP
        if [ "$PRIVATEIP" != "$PUBLICIP" ]
        then sed -i "s/$PRIVATEIP/$PUBLICIP/" $INSTALLDIR/temp/IPADDR$i
            echo -e " Your private IP address is $PRIVATEIP " | tee -a "$LOGFILE"
            echo -e " Your public IP address is $PUBLICIP " | tee -a "$LOGFILE"
            echo -e " ${lightgreen}This masternode seems to be on a LAN, so we'll replace its private" | tee -a "$LOGFILE"
            echo -e " IPv4 address with a public one in the masternode.conf file if needed. ${nocolor}" | tee -a "$LOGFILE"
        fi

        # Check for presence of txid and, if present, use it for txid/txidx
        echo -e "$(sed -n ${i}p $INFODIR/vps.mntxdata.info)" > $INSTALLDIR/temp/TXID$i
        TXDATEXIST=$(<$INSTALLDIR/temp/TXID$i)

        #
        # replace null with txid info
        sed -i "s/.*null null/collateral_output_txid tx/" $INFODIR/vps.mntxdata.info >> $INFODIR/vps.mntxdata.info 2>&1
        sed -i "s/.*null null/collateral_output_txid tx/" $INSTALLDIR/temp/TXID$i >> $INSTALLDIR/temp/TXID$i 2>&1

        # merge all vars into masternode.conf
        echo "|" > $INSTALLDIR/temp/DELIMETER

        # merge data fields to prepare masternode.return file
        paste -d '|' $INSTALLDIR/temp/MNALIAS$i $INSTALLDIR/temp/IPADDR$i $INSTALLDIR/temp/GENKEY$i $INSTALLDIR/temp/TXID$i >> $INSTALLDIR/temp/masternode.line$i

        # if line contains collateral_tx then start the line with #
        sed -e '/collateral_output_txid tx/ s/^#*/#/' -i $INSTALLDIR/temp/masternode.line$i >> $INSTALLDIR/temp/masternode.line$i 2>&1
        # prepend line with delimeter
        paste -d '|' $INSTALLDIR/temp/DELIMETER $INSTALLDIR/temp/masternode.line$i >> $INSTALLDIR/temp/masternode.all

        # create the masternode.conf output that is returned to consumer
        paste -d ' ' $INSTALLDIR/temp/MNALIAS$i $INSTALLDIR/temp/IPADDR$i $INSTALLDIR/temp/GENKEY$i $INSTALLDIR/temp/TXID$i >> $INSTALLDIR/masternode.conf

        # Set the nosync flag for each masternode on creation
        touch $INSTALLDIR/temp/"${PROJECT}"_n${i}_nosync
        echo -e "$(date +%m.%d.%Y_%H:%M:%S) -- first created" >> $INSTALLDIR/temp/"${PROJECT}"_n${i}_nosync

        # round 1: cleanup and declutter
        rm $INSTALLDIR/temp/GENKEY${i}FIN ; rm $INSTALLDIR/temp/GENKEY$i ; rm $INSTALLDIR/temp/IPADDR$i ; rm $INSTALLDIR/temp/MNADD$i
        rm $INSTALLDIR/temp/MNALIAS$i ; rm $INSTALLDIR/temp/TXID$i ; rm $INSTALLDIR/temp/"${PROJECT}"Ds --force ; rm $INSTALLDIR/temp/DELIMETER
        rm $INSTALLDIR/0 --force

        echo -e " --> Completed masternode $i loop, moving on..."  | tee -a "$LOGFILE"
    done
    # echo -e " \n" | tee -a "$LOGFILE"

    # comment out lines that contain "collateral_output_txid tx" in masternode.conf
    sed -e '/collateral_output_txid tx/ s/^#*/# /' -i $INSTALLDIR/masternode.conf >> $INSTALLDIR/masternode.conf 2>&1

    [ -e $INFODIR/fullauto.info ] && echo -e "Converting masternode.conf to one delineated line for mother" | tee -a "$LOGFILE"
    # convert masternode.conf to one delineated line separated using | and ||

    # echo -e "complete" > $INSTALLDIR/temp/complete
    echo -e "complete|${VPSAPI}|headless" > $INSTALLDIR/temp/complete

    # comment out lines that contain no txid or index
    # sed -i "s/.*collateral_output_txid tx/.*collateral_output_txid tx/" $INSTALLDIR/txid >> $INSTALLDIR/txid 2>&1

    # replace necessary spaces with + temporarily
    sed -i 's/ /+/g' $INSTALLDIR/temp/masternode.all
    # merge "complete" line with masternode.all file and remove line breaks (\n)
    paste -s $INSTALLDIR/temp/complete $INSTALLDIR/temp/masternode.all |  tr -d '\n' > $INSTALLDIR/temp/masternode.1
    tr -d '[:blank:]' < $INSTALLDIR/temp/masternode.1 > $INSTALLDIR/temp/masternode.return
    sed -i 's/+/ /g' $INSTALLDIR/temp/masternode.return

    # append masternode.conf file
    cat <<EOT >> $INSTALLDIR/masternode.conf
#######################################################
# This file was automatically generated by Node Valet #
#######################################################
EOT

    # round 2: cleanup and declutter
    echo -e "Cleaning up clutter and taking out trash... \n" | tee -a "$LOGFILE"
    # cp $INSTALLDIR/temp/txid $INFODIR/vps.mntxdata.info
    rm $INSTALLDIR/temp/complete --force        ;   rm $INSTALLDIR/temp/masternode.all --force
    rm $INSTALLDIR/temp/masternode.1 --force    ;   rm $INSTALLDIR/temp/masternode.l* --force
    rm $INSTALLDIR/temp/"${PROJECT}"Ds --force  ;   rm $INSTALLDIR/temp/MNPRIV* --force
    rm $INSTALLDIR/temp/ONLYNET --force         ;   rm $INSTALLDIR/temp/genkeys --force
    rm $INSTALLDIR/temp/txid --force            ;   rm $INFODIR/vps.mnaliases.info --force

    # log successful install
    #### check to see that the last masternode.conf file exists and if so call it a day --still need to add this!###
    TRANSMITMN=$(cat $INSTALLDIR/temp/masternode.return)
    echo -e "\033[1;37m $(date +%m.%d.%Y_%H:%M:%S) : Server successfully added $NNODES new masternodes \e[0m\n" | tee -a "/var/tmp/nodevalet/logs/maintenance.log"
    echo -e "\033[1;37m $(date +%m.%d.%Y_%H:%M:%S) : Server successfully added $NNODES new masternodes \e[0m\n" >> "/var/tmp/nodevalet/logs/silentinstall.log"
    curl -X POST https://www.nodevalet.io/status.php -H 'Content-Type: application/json-rpc' -d '{"hostname":"'"$HNAME"'","message": "'"$TRANSMITMN"'"}' ; echo " "

    echo -e " Your new masternode.conf is as follows \n"
    showconf
}

function remove_crons() {
    # disable the crons that could cause problems
    . /var/tmp/nodevalet/maintenance/remove_crons.sh
}

function restore_crons() {
    # restore maintenance crons that were previously disabled
    . /var/tmp/nodevalet/maintenance/restore_crons.sh
}

function update_rclocal() {
    # Update SmartStart and rc.local
    echo -e " Updating SmartStart and rc.local \n"
    sed -i '/smartstart.sh/d' /etc/rc.local
    echo -e "sudo bash /var/tmp/nodevalet/maintenance/smartstart.sh &" >> /etc/rc.local
    sed -i '/exit 0/d' /etc/rc.local
    echo -e "exit 0" >> /etc/rc.local
}

# This is where the script actually starts
remove_crons
collect_nnodes
collect_api
collect_addresses
create_genkeys
install_mns
sub_genkeys
change_vpsnumber
start_mns
restore_crons
make_newconf
update_rclocal

rm $INSTALLDIR/temp/updating --force

echo -e " $(date +%m.%d.%Y_%H:%M:%S) : Running addmn.sh"  >> /var/tmp/nodevalet/logs/maintenance.log
echo -e " ${lightcyan}User has added $NNODES new MN(s) to this VPS.${nocolor}\n"  >> /var/tmp/nodevalet/logs/maintenance.log

exit

