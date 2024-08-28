#!/bin/bash
# This script reads a 'users' file (gained from "./system.sh" file) and verify idle/max timeouts for user login session 
#

source "./system.sh" || exit -1
source "./utilities_library.sh" || exit -1

users=$USER_FILE
session_cookie=./token_verification_cookie.txt
tmp_logfile=./token_verification_logfile.txt
old_logfile=./token_verification_logfile_old.txt
iteration=360 #$ITERATION 		# nr of iteration to be performed for each user
				# with a 10 secs 'waiting_interval, a 6 hours tests, for example, requires 360 iteration
waiting_interval=10			# in secs

# COUNTERS
successCounter=0
failCounter=0
verifyIndexPageCounter=0

# Read only 1st line of users file to get user credentials to perform session duration
line=`cat $users | head -1`
#echo "Text read from file: $line"
usr=efabpog #"$(cut -d',' -f1 <<<"$line")"
pwd=TestPassw0rd #"$(cut -d',' -f2 <<<"$line")"


# setup tmp_logfile file
if [ -f ${tmp_logfile} ]; then
        rm -f ${old_logfile}
	cp ${tmp_logfile} ${old_logfile}
	rm -f ${tmp_logfile}
fi
echo "Log file for this test is ${tmp_logfile}"


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
	successCounter=$5
	failCounter=$6

	#URL to validate token towards specific SSO instance
	result=$(test_sso)
        echo "Result: ${result}" >> $file
	sso_instance_1_available=`echo ${result} | cut -d',' -f1`
	sso_instance_2_available=`echo ${result} | cut -d',' -f2`
	echo "SSO availability result: - 1: ${sso_instance_1_available}, 2:  ${sso_instance_2_available}" >> $file
	
	sso=${SSO_INSTANCE1}
	if [ "${sso_instance_1_available}" = true ]; then
		echo "Verifying token using instance ${sso}" >> $file
		validateToken ${sso} ${session_cookie} ${policy}
		result=$?
		if [ $result -ne 0 ]; then
			echo "Error while validating token on ${sso}" >> $file
			let "failCounter+=1"
		else
			echo "Success while validating token on ${sso}" >> $file
			let "successCounter+=1"
		fi
	else
		echo "SSO instance ${sso} not available" >> $file
	fi	

	sso=${SSO_INSTANCE2}
	if [ "${sso_instance_2_available}" = true ]; then
		echo "Verifying token using instance ${sso}" >> $file
		validateToken ${sso} ${session_cookie} ${policy}
		result=$?
		if [ $result -ne 0 ]; then
			echo "Error while validating token on ${sso}" >> $file
			let "failCounter+=1"
		else
		        echo "Success while validating token on ${sso}" >> $file
			let "successCounter+=1"
		fi
	else
		echo "SSO instance ${sso} not available" >> $file
	fi

	echo ${fail_counter}, ${success_counter}
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


# This function performs a curl to Index.html page and verify the presence of a specific string .
verify_indexPage() {
	cookie=$1
	file=$2
	verifyIndexPageCounter=$3
	
	url="https://ieatenm5416-87.athtem.eei.ericsson.se/index.html"
	searchWord="eaContainer-applicationHolder"
	
	echo "`date` VerifyIndex using cookie file ${cookie}" >> $file
	echo "COOKIE: ${cookie}" >> $file
	echo "URL: ${url}" >> $file
	echo "" >> $file
	
	result=$(curl -k -X GET --cookie ${cookie} ${url} | grep ${searchWord}) > /dev/null
	echo ${result} >> $file

	if [ $? -eq 0 ]; then
		echo "verify_IndexPage success" >> $file
		let "verifyIndexPageCounter+=1"
	else
		echo "verify_IndexPage error" >> $file
	fi
	echo ${result}
}




echo "START test at `date`" >> ${tmp_logfile}

# for each iteration
for (( i=1;i<=$iteration;i++ ))
do

echo "===== LOGIN to be performed with credentials $usr at `date`" >> ${tmp_logfile}
login ${usr} ${pwd} ${session_cookie} ${tmp_logfile}
verify_token ${session_cookie} ${usr} ${SESSION_ISVALID} ${tmp_logfile} ${successCounter} ${failCounter}
echo "" >> ${tmp_logfile}

verify_indexPage ${session_cookie} ${tmp_logfile} ${verifyIndexPageCounter}

sleep ${waiting_interval}

#verifyCookieRotary ${session_cookie} 1 ${SESSION_ISINVALID} true ${tmp_logfile}
#echo "" >> ${tmp_logfile}

echo "===== LOGOUT to be performed with credentials $usr at `date`" >> ${tmp_logfile}
logout ${usr} ${session_cookie} ${tmp_logfile}
echo "" >> ${tmp_logfile}

echo "Iterations: ${i} - VerifyToken Success: ${successCounter} - VerifyToken Errors: ${failCounter} - - VerifyIndexPage Success: ${verifyIndexPageCounter}" >> ${tmp_logfile}

sleep ${waiting_interval}

done
echo "Summary:" >> ${tmp_logfile}
echo "Iterations: ${iteration} - Success: ${successCounter} - Errors: ${failCounter} - - VerifyIndexPage Success: ${verifyIndexPageCounter}" >> ${tmp_logfile}
echo "" >> ${tmp_logfile}

echo "FINISH test at `date`" >> ${tmp_logfile}
