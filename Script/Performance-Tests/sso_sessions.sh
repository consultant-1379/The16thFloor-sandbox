#!/bin/bash
# This script reads a 'users' file (gained from "./system.sh" file) and verify idle/max timeouts for user login session 
#

source "./system.sh" || exit -1
source "./utilities_library.sh" || exit -1

users=$USER_FILE
session_cookie=./session_cookie.txt
tmp_logfile=./tmp_logfile.txt
use_jwt=${USE_JWT}
SESSION_TIMEOUT_IDLE=$(($SESSION_TIMEOUT_MINUTE*60))

if [ ${SESSION_TIMEOUT_IDLE} -lt 60 ]; then
	echo "Session idle timeout is too low ${SESSION_TIMEOUT_IDLE}s, set at least 60s"
	exit 1
fi

SESSION_TIMEOUT_MAX_DURATION=$(($SESSION_TIMEOUT_MAX_DURATION_MINUTE*60))
ITERATIONS_TO_REACH_MAX_TIMEOUT_EXPIRATION=$(($SESSION_TIMEOUT_MAX_DURATION/$SESSION_TIMEOUT_IDLE))
SLEEP_SESSION_TIMEOUT_IDLE=$(($SESSION_TIMEOUT_IDLE +3))
SLEEP_SESSION_TIMEOUT_MAX_DURATION=$(($SESSION_TIMEOUT_MAX_DURATION +3))
SLEEP_LOWER_THAN_SESSION_TIMEOUT_IDLE=$(($SESSION_TIMEOUT_IDLE -20))
echo "Starting session test"
echo "SESSION_TIMEOUT_IDLE set to ${SESSION_TIMEOUT_IDLE}s"
echo "SESSION_TIMEOUT_MAX_DURATION set to ${SESSION_TIMEOUT_MAX_DURATION}s"


getsession() {
	cookie=$1

	getsessionvalue=`curl --insecure --request GET -s --cookie ${cookie} https://${HAPROXY_URL}/oss/sso/utilities/config`
	# REsponse example
	#{"timestamp":"1559805308278","idle_session_timeout":"65","session_timeout":"610"}
	echo "getsessionvalue is ${getsessionvalue}"
}

configsession() {
	cookie=$1
	idle=$2
	max=$3
	newsessionvalue=${sessionduration_timestamp},"\"idle_session_timeout\":\"${idle}\",\"session_timeout\":\"${max}\"}"

	echo "New session values to be set ${newsessionvalue}"
	setsession $cookie $newsessionvalue
}

setsession() {
	cookie=$1
	sessionvalue=$2

	echo "Setting sessions with values ${newsessionvalue}"
	curl --insecure --request PUT -s --cookie ${cookie} https://${HAPROXY_URL}/oss/sso/utilities/config -H "Content-Type: application/json" -d "${newsessionvalue}"
}

verify_token() {
	session_cookie=$1
	usr=$2
	policy=$3

	#URL to validate token towards specific SSO instance
	result=$(test_sso)
	sso_instance_1_available=`echo ${result} | cut -d',' -f1`
	sso_instance_2_available=`echo ${result} | cut -d',' -f2`
	echo "Got result as $result - 1: ${sso_instance_1_available}, 2:  ${sso_instance_2_available}"
	
	sso=${SSO_INSTANCE1}
	if [ "${sso_instance_1_available}" = true ]; then
		echo "Verifying token using instance ${sso}"
		validateToken ${sso} ${session_cookie} ${policy}
		result=$?
		if [ $result -ne 0 ]; then
			echo "Error while validating token on ${sso}"
			exit 1
		fi
	else
		echo "SSO instance ${sso} not available"
	fi	

	sso=${SSO_INSTANCE2}
	if [ "${sso_instance_2_available}" = true ]; then
		echo "Verifying token using instance ${sso}"
		validateToken ${sso} ${session_cookie} ${policy}
		result=$?
		if [ $result -ne 0 ]; then
			echo "Error while validating token on ${sso}"
			exit 1
		fi
	else
		echo "SSO instance ${sso} not available"
	fi	

}

rm -f ${tmp_logfile}

login ${ENM_ADMINISTRATOR_USERNAME} ${ENM_ADMINISTRATOR_PWD} ${ENM_ADMINISTRATOR_COOKIE} ${tmp_logfile} ${use_jwt}

getsession ${ENM_ADMINISTRATOR_COOKIE}
sessiondurationoriginalconfig=${getsessionvalue}

echo "Current original configuration is ${sessiondurationoriginalconfig} minute(s)"

sessionduration_timestamp=`echo ${sessiondurationoriginalconfig} | cut -d',' -f1`
echo ${sessionduration_timestamp}
#Format: 
#{"timestamp":"1559805308278"

configsession ${ENM_ADMINISTRATOR_COOKIE} ${SESSION_TIMEOUT_MINUTE} ${SESSION_TIMEOUT_MAX_DURATION_MINUTE}

sleep 3
echo "Getting session data after configuration"
getsession ${ENM_ADMINISTRATOR_COOKIE}
logout ${ENM_ADMINISTRATOR_USERNAME} ${ENM_ADMINISTRATOR_COOKIE} ${tmp_logfile}

sessiondurationnewconfig=${getsessionvalue}
echo "Session data read after setting ${sessiondurationnewconfig}"

echo ${sessiondurationnewconfig} | grep -e "idle_session_timeout\":\"${SESSION_TIMEOUT_MINUTE}" | grep -e "session_timeout\":\"${SESSION_TIMEOUT_MAX_DURATION_MINUTE}\""
result=$?

if [ ${result} -ne 0 ]; then
	echo "Error found in checking session data"
	exit 1
fi


# Read only 1st line of users file to get user credentials to perform session duration
line=`cat $users | head -1`

#echo "Text read from file: $line"
usr="$(cut -d',' -f1 <<<"$line")"
pwd="$(cut -d',' -f2 <<<"$line")"

echo "===== Idle Session test to be performed with credentials $usr at `date`"
login ${usr} ${pwd} ${session_cookie} ${tmp_logfile} ${use_jwt}
verify_token ${session_cookie} ${usr} ${SESSION_ISVALID}

echo "Sleeping for ${SLEEP_SESSION_TIMEOUT_IDLE}s to test session idle timeout of ${SESSION_TIMEOUT_IDLE}s for user $usr"
sleep ${SLEEP_SESSION_TIMEOUT_IDLE}
verify_token ${session_cookie} ${usr} ${SESSION_ISINVALID}

echo "===== Max Session test to be performed with credentials $usr at `date`"
login ${usr} ${pwd} ${session_cookie} ${tmp_logfile} ${use_jwt}
verify_token ${session_cookie} ${usr} ${SESSION_ISVALID}

COUNTER=1
while [  $COUNTER -le ${ITERATIONS_TO_REACH_MAX_TIMEOUT_EXPIRATION} ]; do
    echo "============== Iteration $COUNTER of ${ITERATIONS_TO_REACH_MAX_TIMEOUT_EXPIRATION} =============="

	echo "Sleeping for ${SLEEP_LOWER_THAN_SESSION_TIMEOUT_IDLE}s in order to progress through the max timeout of ${SESSION_TIMEOUT_MAX_DURATION}s but keep the session active"
	sleep ${SLEEP_LOWER_THAN_SESSION_TIMEOUT_IDLE}
	verifyCookieRotary ${session_cookie} 1 ${SESSION_ISVALID} true ${tmp_logfile}
	verify_token ${session_cookie} ${usr} ${SESSION_ISVALID}

    COUNTER=$(($COUNTER+1)) 
done
COUNTER=$(($COUNTER-1)) 

echo "Completed after ${COUNTER} iterations==="
finalTimeToWait=$((${SLEEP_SESSION_TIMEOUT_MAX_DURATION} - $COUNTER*${SLEEP_LOWER_THAN_SESSION_TIMEOUT_IDLE}))
echo "It's needed to wait final extra ${finalTimeToWait}s to get the session expired by max time ${SESSION_TIMEOUT_MAX_DURATION}"
sleep ${finalTimeToWait}

verify_token ${session_cookie} ${usr} ${SESSION_ISINVALID}
verifyCookieRotary ${session_cookie} 1 ${SESSION_ISINVALID} true ${tmp_logfile}

#New session as admin to restore previous session settings
login ${ENM_ADMINISTRATOR_USERNAME} ${ENM_ADMINISTRATOR_PWD} ${ENM_ADMINISTRATOR_COOKIE} ${tmp_logfile} ${use_jwt}
setsession ${ENM_ADMINISTRATOR_COOKIE} ${sessiondurationoriginalconfig}
logout ${ENM_ADMINISTRATOR_USERNAME} ${ENM_ADMINISTRATOR_COOKIE} ${tmp_logfile}
