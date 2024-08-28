#!/bin/bash
# This script works with 'system.sh' and 'sso_test_parallel.sh'
#
# This script performs login request for a single user
# requests are executed asynchrounously and returned cookie is stored on file.
# Another script (sso_test_logout_async.sh) will perform logout to avoid session growth
#
#

# from source-file "./system.sh"
source "./system.sh" || exit -1 
source "./utilities_library_async.sh" || exit -1

iPlanetDirectoryPro=$IPLANETDIRECTORYPRO

use_jwt=${USE_JWT}


# default
INSTANCE=1 #default value for Instance; generally it is passed from sso_login_logout_parallel.sh file
USER=${ENM_ADMINISTRATOR_USERNAME}
PSWD=${ENM_ADMINISTRATOR_PWD}

# check input values
if [ -z $1 ]; then
	user=$USER
else
	user=$1
fi
if [ -z $2 ]; then
	pswd=$PSWD
else
	pswd=$2
fi
if [ -z $3 ]; then
	instance=$INSTANCE
else
	instance=$3
fi


# log files setup
#if [ ! -d $TARGET_DIR ]; then
#	mkdir -p $TARGET_DIR
#fi
file="./$TARGET_DIR/${instance}-${user}_login.txt" # from source "./system.sh"
file_old="./$TARGET_DIR/${instance}-${user}_loginOLD.txt" # from source "./system.sh"
if [ -f $file ]; then
	cp $file $file_old
	rm -f $file
fi

# nr of iteration to be performed for each user
iteration=${ITERATION}

echo "User: $user - -> $instance - Start Login at : $(date '+%F %T.%3N')"
echo ""

echo "User: $user - Pswd: $pswd" >> $file
echo "Number of login per second: $ASYNC_NO_LOGIN_PER_SECOND_PER_USER" >> $file
echo "Test Duration (sec): $ASYNC_TEST_DURATION" >> $file
echo "Total Number of login expected: ${iteration}" >> $file
echo "sleep time: ${sleep_time_sec}" >> $file
echo "" >> $file
echo "System under test: ${HAPROXY_URL}" >> $file
echo "" >> $file

starttest=`date`

echo "START test at ${starttest}" >> $file
echo "" >> $file

sesfolder="./$TARGET_DIR/Cookies" 	
if [ ! -d $sesfolder ]; then 
	mkdir -p $sesfolder
fi

# for each iteration
for (( i=1;i<=$iteration;i++ ))
do
	echo "Iteration - User: ${instance} - iteration: ${i}"
	 
	usedCookie="cookie-${instance}-${i}.txt"
	logintime=$(echo $(date '+%F %T.%3N'))
	#echo "Login sent at: ${logintime}, cookie stored in: $sesfolder/${usedCookie}" >> ${file}
	login ${user} ${pswd} $sesfolder/${usedCookie} ${file} ${use_jwt} > /dev/null &
	#echo "" >> $file
	sleep $sleep_time_sec
done

echo -e "\n- - -\nTEST for user $user\n" 

# average computations 

#testStop=$(echo $(($(date +%s%N)/1000000)))
endtest=`date`
echo "FINISH test at ${endtest}" >> $file
echo " - duration:" >> $file
echo " - - START: ${starttest}" >> $file
echo " - -   END: ${endtest}" >> $file
echo -e "TEST for user $user - finished"
echo -e "Wait for Logout ... if has been configured."
