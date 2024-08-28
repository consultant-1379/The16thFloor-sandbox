#!/bin/bash
# This script works with 'system.sh' and 'sso_test_parallel.sh'
#
# This script performs logout requests and shall be used in conjunction with sso_test_benchmarking_async.sh
# It check presence of cookie in file system and logout it
#
#

# from source-file "./system.sh"
source "./system.sh" || exit -1 
source "./utilities_library.sh" || exit -1

# default
INSTANCE=1 #default value for Instance; generally it is passed from sso_login_logout_parallel.sh file
USER=${ENM_ADMINISTRATOR_USERNAME}

# check input values
if [ -z $1 ]; then
	user=$USER
else
	user=$1
fi
if [ -z $2 ]; then
	instance=$INSTANCE
else
	instance=$2
fi

# log files setup
#if [ ! -d $TARGET_DIR ]; then
	#mkdir -p $TARGET_DIR
#fi

file="./$TARGET_DIR/${instance}-${user}_logout.txt"
file_old="./$TARGET_DIR/${instance}-${user}_logoutOLD.txt"
if [ -f $file ]; then
	cp $file $file_old
	rm -f $file
fi
sesfolder="./$TARGET_DIR/Cookies"

# nr of iteration to be performed for each user
iteration=${ITERATION}

#initial sleep to be shifted wrt the login script
sleep ${LOGOUT_TIMEOUT_SEC}
starttest=`date`

echo "User: $user - -> $instance - Start Logout at : $(date '+%F %T.%3N')"
echo "WAIT FOR FINISH. There are ${iteration} sessions to be logged out."
echo ""

echo "User: $user - Pswd: $pswd" >> $file
echo "Number of login per second: $ASYNC_NO_LOGIN_PER_SECOND_PER_USER" >> $file
echo "Test Duration (sec): $ASYNC_TEST_DURATION" >> $file
echo "Total Number of login expected: ${iteration}" >> $file
echo "sleep time: ${sleep_time_sec}" >> $file
echo "" >> $file
echo "System under test: ${HAPROXY_URL}" >> $file
echo "" >> $file

i=1
max_attempt=0
while [ $i -le $iteration ]
do
	usedCookie="cookie-${instance}-${i}.txt"
	if [ $max_attempt -le 3 ]; then
		if [ -f "${sesfolder}/${usedCookie}" ]; then
			logout ${user} $sesfolder/${usedCookie} ${file} > /dev/null &
			max_attempt=0
			i=$(( $i + 1 ))
		else
			echo "attempt to logout cookie: $sesfolder/${usedCookie} failed. Retrying" >> ${file}
			max_attempt=$(( $max_attempt + 1 ))
		fi
	else
		echo "could not logout cookie: $sesfolder/${usedCookie}. Skipping" >> ${file}
		max_attempt=0
		i=$(( $i + 1 ))
	fi
	sleep $sleep_time_sec
done


# average computations 

#testStop=$(echo $(($(date +%s%N)/1000000)))
endtest=`date`
echo "FINISH test at ${endtest}" >> $file
echo " - duration:" >> $file
echo " - - START: ${starttest}" >> $file
echo " - -   END: ${endtest}" >> $file
echo "Logout routine for user $user - finished"
