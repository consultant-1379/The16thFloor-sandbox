#!/bin/bash
# This script reads a 'users' file (gained from "./system.sh" file) and verify idle/max timeouts for user login session 
#

source "./system.sh" || exit -1
source "./utilities_library.sh" || exit -1

SESSION_IDLE_DEFAULT=60
SESSION_MAX_DEFAULT=600

users=$USER_FILE
session_cookie=./session_cookie.txt
tmp_logfile=./session_logfile.txt
old_logfile=./session_logfile_old.txt
iteration=$ITERATION 					# nr of iteration to be performed for each user


# setup tmp_logfile file
if [ -f ${tmp_logfile} ]; then
        rm -f ${old_logfile}
	cp ${tmp_logfile} ${old_logfile}
	rm -f ${tmp_logfile}
fi
echo "Log file for this test is ${tmp_logfile}"

SESSION_TIMEOUT_IDLE=$(($SESSION_TIMEOUT_MINUTE*60))

if [ ${SESSION_TIMEOUT_IDLE} -lt 60 ]; then
	echo "Session idle timeout is too low ${SESSION_TIMEOUT_IDLE}s, set at least 60s"
	exit 1
fi

SESSION_TIMEOUT_MAX_DURATION=$(($SESSION_TIMEOUT_MAX_DURATION_MINUTE*60))
ITERATIONS_TO_REACH_MAX_TIMEOUT_EXPIRATION=$(($SESSION_TIMEOUT_MAX_DURATION/$SESSION_TIMEOUT_IDLE))
echo "Iterations: $ITERATIONS_TO_REACH_MAX_TIMEOUT_EXPIRATION" >> ${tmp_logfile}
SLEEP_SESSION_TIMEOUT_IDLE=$(($SESSION_TIMEOUT_IDLE +3))
SLEEP_SESSION_TIMEOUT_MAX_DURATION=$(($SESSION_TIMEOUT_MAX_DURATION +3))
SLEEP_LOWER_THAN_SESSION_TIMEOUT_IDLE=$(($SESSION_TIMEOUT_IDLE -20))
echo "Starting session test" >> ${tmp_logfile}
echo "SESSION_TIMEOUT_IDLE set to ${SESSION_TIMEOUT_IDLE}s" >> ${tmp_logfile}
echo "SESSION_TIMEOUT_MAX_DURATION set to ${SESSION_TIMEOUT_MAX_DURATION}s" >> ${tmp_logfile}
echo "" >> ${tmp_logfile}

getsession() {
	cookie=$1

	getsessionvalue=`curl --insecure --request GET -s --cookie ${cookie} https://${HAPROXY_URL}/oss/sso/utilities/config`
	# REsponse example
	#{"timestamp":"1559805308278","idle_session_timeout":"65","session_timeout":"610"}
	echo "GET Session value is ${getsessionvalue}" >> $tmp_logfile
}

configsession() {
	cookie=$1
	idle=$2
	max=$3

	newsessionvalue=${sessionduration_timestamp},"\"idle_session_timeout\":\"${idle}\",\"session_timeout\":\"${max}\"}"
	echo "New session values to be set ${newsessionvalue}" >> ${tmp_logfile}
	setsession $cookie $newsessionvalue
}

setsession() {
	cookie=$1
	sessionvalue=$2

	echo "Setting sessions with values ${newsessionvalue}" >> $tmp_logfile
	curl --insecure --request PUT -s --cookie ${cookie} https://${HAPROXY_URL}/oss/sso/utilities/config -H "Content-Type: application/json" -d "${newsessionvalue}"
}

verify_token() {
	session_cookie=$1
	usr=$2
	policy=$3
        file=$4

	#URL to validate token towards specific SSO instance
	result=$(test_sso)
	sso_instance_1_available=`echo ${result} | cut -d',' -f1`
	sso_instance_2_available=`echo ${result} | cut -d',' -f2`
	echo "SSO availability result: - 1: ${sso_instance_1_available}, 2:  ${sso_instance_2_available}" >> $file
	
	sso=${SSO_INSTANCE1}
	sso_instance_1_available=`echo ${result} | cut -d',' -f1`
	echo "SSO-1 availability result: ${sso_instance_1_available}" >> $file
	if [ "${sso_instance_1_available}" = true ]; then
		echo "Verifying token using instance ${sso}" >> $file
		validateToken ${sso} ${session_cookie} ${policy}
		result=$?
		if [ $result -ne 0 ]; then
			echo "Error while validating token on ${sso}" >> $file
		else
			echo "Success while validating token on ${sso}" >> $file
		fi
	else
		echo "SSO instance ${sso} not available" >> $file
	fi	

	sso=${SSO_INSTANCE2}
	sso_instance_2_available=`echo ${result} | cut -d',' -f2`
	echo "SSO-2 availability result: ${sso_instance_2_available}" >> $file
	if [ "${sso_instance_2_available}" = true ]; then
		echo "Verifying token using instance ${sso}" >> $file
		validateToken ${sso} ${session_cookie} ${policy}
		result=$?
		if [ $result -ne 0 ]; then
			echo "Error while validating token on ${sso}" >> $file
		else
            echo "Success while validating token on ${sso}" >> $file
		fi
	else
		echo "SSO instance ${sso} not available" >> $file
	fi	
}

session_configuration_and_verify() {
        idle=$1
        max=$2

        echo "Session Configuration - start - idle= $idle - max: $max"

        login ${ENM_ADMINISTRATOR_USERNAME} ${ENM_ADMINISTRATOR_PWD} ${ENM_ADMINISTRATOR_COOKIE} ${tmp_logfile}
        getsession ${ENM_ADMINISTRATOR_COOKIE}
        sessiondurationoriginalconfig=${getsessionvalue}
        echo "Current configuration is ${sessiondurationoriginalconfig} minute(s)" >> ${tmp_logfile}
        sessionduration_timestamp=`echo ${sessiondurationoriginalconfig} | cut -d',' -f1`
        #echo ${sessionduration_timestamp} #Format: {"timestamp":"1559805308278"
        configsession ${ENM_ADMINISTRATOR_COOKIE} ${idle} ${max}
        sleep 3
        #echo "Getting session data after configuration" >> ${tmp_logfile}
        getsession ${ENM_ADMINISTRATOR_COOKIE}
        #logout ${ENM_ADMINISTRATOR_USERNAME} ${ENM_ADMINISTRATOR_COOKIE} ${tmp_logfile}
        echo "" >> ${tmp_logfile}

        sessiondurationnewconfig=${getsessionvalue}
        echo " - - - Check new config: ${sessiondurationnewconfig}" >> ${tmp_logfile}
        echo ${sessiondurationnewconfig} | grep -e "idle_session_timeout\":\"${idle}" | grep -e "session_timeout\":\"${max}\"" >> ${tmp_logfile}
        result=$?
        if [ ${result} -ne 0 ]; then
            echo "Error found in checking session configuration"
            exit 1
		else
			echo "Success in checking session configuration"
        fi
        logout ${ENM_ADMINISTRATOR_USERNAME} ${ENM_ADMINISTRATOR_COOKIE} ${tmp_logfile}
        echo "Session Configuration - finish"
}


# Read only 1st line of users file to get user credentials to perform session duration
line=`cat $users | head -1`

#echo "Text read from file: $line"
usr="$(cut -d',' -f1 <<<"$line")"
pwd="$(cut -d',' -f2 <<<"$line")"

echo "START test at `date`" >> ${tmp_logfile}

# for each iteration
for (( i=1;i<=$iteration;i++ ))
do

echo "===== LOGIN to be performed with credentials $usr at `date`" >> ${tmp_logfile}
login ${usr} ${pwd} ${session_cookie} ${tmp_logfile}
verify_token ${session_cookie} ${usr} ${SESSION_ISVALID} ${tmp_logfile}
echo "" >> ${tmp_logfile}

sleep 5

verifyCookieRotary ${session_cookie} 1 ${SESSION_ISINVALID} true ${tmp_logfile}
echo "" >> ${tmp_logfile}

done

echo "FINISH test at `date`" >> ${tmp_logfile}
