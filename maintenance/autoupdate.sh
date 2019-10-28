#!/bin/bash
# to be added to crontab to updatebinaries using any means necessary
LOGFILE='/var/tmp/nodevalet/logs/maintenance.log'
INSTALLDIR='/var/tmp/nodevalet'
INFODIR='/var/tmp/nvtemp'
PROJECT=$(cat $INFODIR/vpscoin.info)
PROJECTl=${PROJECT,,}
PROJECTt=${PROJECTl~}

# update .gitstring binary search string variable
cd $INSTALLDIR/nodemaster/config/$PROJECT
echo -e " \n$(date +%m.%d.%Y_%H:%M:%S) : Downloading current $PROJECT.gitstring"
curl -LJO https://raw.githubusercontent.com/nodevalet/nodevalet/master/nodemaster/config/$PROJECT/$PROJECT.gitstring

# set mnode daemon name from project.env
MNODE_DAEMON=$(grep ^MNODE_DAEMON $INSTALLDIR/nodemaster/config/${PROJECT}/${PROJECT}.env)
echo -e "$MNODE_DAEMON" > $INSTALLDIR/temp/MNODE_DAEMON
sed -i "s/MNODE_DAEMON=\${MNODE_DAEMON:-\/usr\/local\/bin\///" $INSTALLDIR/temp/MNODE_DAEMON  >> log 2>&1
cat $INSTALLDIR/temp/MNODE_DAEMON | tr -d '[}]' > $INSTALLDIR/temp/MNODE_DAEMON1
MNODE_DAEMON=$(<$INSTALLDIR/temp/MNODE_DAEMON1)
cat $INSTALLDIR/temp/MNODE_DAEMON1 > $INSTALLDIR/temp/MNODE_DAEMON ; rm $INSTALLDIR/temp/MNODE_DAEMON1

# Pull GITAPI_URL from $PROJECT.env
GIT_API=$(grep ^GITAPI_URL $INSTALLDIR/nodemaster/config/${PROJECT}/${PROJECT}.env)
echo "$GIT_API" > $INSTALLDIR/temp/GIT_API
sed -i "s/GITAPI_URL=//" $INSTALLDIR/temp/GIT_API
GITAPI_URL=$(<$INSTALLDIR/temp/GIT_API)

# Pull GIT URL from $PROJECT.env
GIT_URL=$(grep ^GIT_URL $INSTALLDIR/nodemaster/config/${PROJECT}/${PROJECT}.env)
echo "$GIT_URL" > $INSTALLDIR/temp/GIT_URL
sed -i "s/GIT_URL=//" $INSTALLDIR/temp/GIT_URL
GIT_URL=$(<$INSTALLDIR/temp/GIT_URL)

# Pull GITSTRING from $PROJECT.env
GITSTRING=$(cat $INSTALLDIR/nodemaster/config/${PROJECT}/${PROJECT}.gitstring)

if [ -e $INSTALLDIR/temp/updating ]
	then echo -e "$(date +%m.%d.%Y_%H:%M:%S) : Running autoupdate.sh" | tee -a "$LOGFILE"
		echo -e " Removing maintenance flag that was leftover from previous activity.\n"  | tee -a "$LOGFILE"
		rm -f $INSTALLDIR/temp/updating
fi

function update_binaries() {
#check for updates and install binaries if necessary
echo -e "$(date +%m.%d.%Y_%H:%M:%S) : Running update_binaries function"
echo -e "$(date +%m.%d.%Y_%H:%M:%S) : Autoupdate is looking for new $PROJECTt tags"

if [ ! -d $INSTALLDIR/temp/bin ]; then mkdir $INSTALLDIR/temp/bin ; fi
cd $INSTALLDIR/temp/bin
rm -r -f $PROJECT*
CURVERSION=$(cat $INSTALLDIR/temp/currentversion)
NEWVERSION="$(curl -s $GITAPI_URL | grep tag_name)"
if [ "$CURVERSION" != "$NEWVERSION" ]
then echo -e " $(date +%m.%d.%Y_%H:%M:%S) : Autoupdate detected new $PROJECTt tags" | tee -a "$LOGFILE"
	echo -e " Installed version is : $CURVERSION" | tee -a "$LOGFILE"
	echo -e " New version detected : $NEWVERSION" | tee -a "$LOGFILE"
	echo -e " ** Attempting to install new $PROJECTt binaries ** \n" | tee -a "$LOGFILE"
		touch $INSTALLDIR/temp/updating
		systemctl stop $PROJECT*
		if [ ! -d /usr/local/bin/backup ]; then mkdir /usr/local/bin/backup ; fi
		mkdir 2>/dev/null
		# echo -e " Backing up existing binaries to /usr/local/bin/backup" | tee -a "$LOGFILE"
		
        cp /usr/local/bin/${PROJECT}* /usr/local/bin/backup
		rm /usr/local/bin/${PROJECT}*
		
            curl -s "$GITAPI_URL" \
            | grep browser_download_url \
            | grep "$GITSTRING" \
            | cut -d '"' -f 4 \
            | wget -qi -
        TARBALL="$(find . -type f -printf '%T@ %p\n' | sort -n | tail -1 | cut -f2- -d" ")"

        if [[ $TARBALL == *.gz ]]
        then tar -xzf "$TARBALL"
        else unzip "$TARBALL"
        fi
        rm -f "$TARBALL"
        cd  "$(\ls -1dt ./*/ | head -n 1)"
        find . -mindepth 2 -type f -print -exec mv {} . \;
        cp ${PROJECT}* '/usr/local/bin'
        cd ..
        rm -r -f *
        cd
        cd /usr/local/bin
        chmod 777 ${PROJECT}*
		
        echo -e " Starting masternodes after installation of new ${PROJECTt} binaries" >> "$LOGFILE"
		activate_masternodes_${PROJECT}
		sleep 2
		check_project

else echo -e " No new version is detected \n"
exit
fi
}

function update_from_source() {
#check for updates and build from source if installing binaries failed. 

echo -e "$(date +%m.%d.%Y_%H:%M:%S) : Running update_from_source function" | tee -a "$LOGFILE"
cd $INSTALLDIR/temp
rm -r -f $PROJECT*

CURVERSION=$(cat $INSTALLDIR/temp/currentversion)
NEWVERSION="$(curl -s $GITAPI_URL | grep tag_name)"
if [ "$CURVERSION" != "$NEWVERSION" ]
then 	echo -e " I couldn't download the new binaries, so I am now"
	echo -e " attempting to build new wallet version from source"
	sleep 3
	add-apt-repository -yu ppa:bitcoin/bitcoin
	apt-get -qq -o=Dpkg::Use-Pty=0 -o=Acquire::ForceIPv4=true update
	apt-get -qqy -o=Dpkg::Use-Pty=0 -o=Acquire::ForceIPv4=true install build-essential \
	libcurl4-gnutls-dev protobuf-compiler libboost-all-dev autotools-dev automake \
	libboost-all-dev libssl-dev make autoconf libtool git apt-utils g++ \
	libprotobuf-dev pkg-config libudev-dev libqrencode-dev bsdmainutils \
	pkg-config libgmp3-dev libevent-dev jp2a pv virtualenv libdb4.8-dev libdb4.8++-dev
	systemctl stop ${PROJECT}*
	git clone $GIT_URL
	cd $PROJECT
	
	# this will compile wallet using directions from project.compile if it exists, if not use generic process
	if [ -s $INSTALLDIR/nodemaster/config/${PROJECT}/${PROJECT}.compile ]
	then echo -e " ${PROJECT}.compile found, building wallet from source instructions \n"  | tee -a "$LOGFILE"
	bash $INSTALLDIR/nodemaster/config/${PROJECT}/${PROJECT}.compile
	else echo -e " ${PROJECT}.compile not found, building wallet from generic instructions \n"  | tee -a "$LOGFILE"
	./autogen.sh
	./configure --disable-dependency-tracking --enable-tests=no --without-gui --without-miniupnpc --with-incompatible-bdb CFLAGS="-march=native" LIBS="-lcurl -lssl -lcrypto -lz"
	make
	make install
	fi
	
	cd /usr/local/bin && rm -f !"("activate_masternodes_$PROJECT")"
	cp $INSTALLDIR/temp/$PROJECT/src/{"$PROJECT"-cli,"$PROJECT"d,"$PROJECT"-tx} /usr/local/bin/
	rm -rf $INSTALLDIR/temp/$PROJECT
	cd $INSTALLDIR/temp
	echo -e " Starting masternodes after building ${PROJECTt} from source" >> "$LOGFILE"
	activate_masternodes_$PROJECT
	sleep 2
	check_project
	echo -e " It looks like we couldn't rebuild ${PROJECTt} from source, either" >> "$LOGFILE"
	echo -e " Restoring original binaries from /usr/local/bin/backup" | tee -a "$LOGFILE"
	cp /usr/local/bin/backup/${PROJECT}* /usr/local/bin/
	activate_masternodes_$PROJECT
	sleep 2
	check_restore
    reboot
	exit
fi
}

function check_project() {
    # check if binaries already exist, skip installing crypto packages if they aren't needed
    dEXIST=$(ls /usr/local/bin | grep "${MNODE_DAEMON}")

    if [[ "${dEXIST}" ]]
    then echo -e "${lightcyan} $(date +%m.%d.%Y_%H:%M:%S) : SUCCESS : ${MNODE_DAEMON} exists..." | tee -a "$LOGFILE"
    	echo -e " New version installed : $NEWVERSION" | tee -a "$LOGFILE"
		echo -e "  --> ${PROJECTt}d was successfully updated, restarting VPS \n" | tee -a "$LOGFILE"
            curl -s $GITAPI_URL | grep tag_name > $INSTALLDIR/temp/currentversion
            	rm -f $INSTALLDIR/temp/updating
        reboot
	    exit

    else echo -e "${lightred} $(date +%m.%d.%Y_%H:%M:%S) : ERROR : ${MNODE_DAEMON} does not exist..." | tee -a "$LOGFILE"
        echo -e " ** This update step failed, trying to autocorrect ... \n" | tee -a "$LOGFILE"
    fi
}

function check_restore() {
	    # check if binaries already exist, skip installing crypto packages if they aren't needed
    dEXIST=$(ls /usr/local/bin | grep "${MNODE_DAEMON}")

    if [[ "${dEXIST}" ]]
    then echo -e "${lightcyan} ** ${MNODE_DAEMON} is running...original binaries were restored${nocolor}" | tee -a "$LOGFILE"
    	echo -e "  --> We will try to install this update again next time, rebooting... \n" | tee -a "$LOGFILE"
    	rm -f $INSTALLDIR/temp/updating
	    reboot
	    exit

    else echo -e "${lightred} Restoring the original binaries failed, ${MNODE_DAEMON} is not running... " | tee -a "$LOGFILE"
        echo -e " This shouldn't happen unless your source is unwell.  Make a fuss in Discord.${nocolor}" | tee -a "$LOGFILE"
	    echo -e "  --> I'm all out of options; your VPS may need service \n " | tee -a "$LOGFILE"
	    rm -f $INSTALLDIR/temp/updating
	    reboot
	fi
}

# this is where the current update sequence begins
update_binaries
update_from_source
exit
