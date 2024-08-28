#!/bin/bash

IS_CLOUD=false
HAPROXY_URL=`cat /ericsson/tor/data/global.properties | grep UI_PRES_SERVER | cut -d= -f2` 
if [ -z $HAPROXY_URL ]; then
	echo "Empty HAPROXY_URL from global.properties, trying as on cloud"
	HAPROXY_URL=`/usr/bin/consul kv get -recurse enm | grep -i PRES_SERVER | cut -d: -f2`
	if [ -z $HAPROXY_URL ]; then
		echo "Empty HAPROXY_URL as on cloud. Exiting"
		exit 1
	else
		IS_CLOUD=true
	fi
else
	echo "HAPROXY_URL from global.properties is valid"
fi

enm_admin=administrator
enm_admin_pwd=TestPassw0rd
enm_admin_cookie=enm_admin_cookie.txt

#openam_admin_pwd=`cat /opt/ericsson/sso/config/access.bin`
openam_admin_pwd=h31md477R
openam_admin=amadmin
openam_admin_cookie=openam_admin_cookie.txt

enm_user_authmode_local=local
enm_user_authmode_remote=remote

extIdp_password=Externalldapadmin01
extIdp_profile_standard=STANDARD
extIdp_profile_nosearch=NOSEARCH
extIdp_REMOTEAUTHN=REMOTEAUTHN
extIdp_LOCAL=LOCAL

extIdp_primaryServerAddress=10.45.205.253:1389
extIdp_secondaryServerAddress=141.137.87.62:6389
extIdp_baseDN=dc=acme,dc=com
extIdp_ldapConnectionMode=LDAP
extIdp_userBindDNFormat_standard="uid=\$user" 
extIdp_userBindDNFormat_nosearch="uid=\$user,ou=pdu nam,dc=acme,dc=com"
extIdp_bindDN=cn=extldapadmin,ou=people,dc=acme,dc=com

enm_target_user=rememarccr
local_password=TestPassw0rd
remote_password=Rememarccr01
enm_user_cookie=enm_user_cookie.txt

sso_instance1=sso-instance-1
sso_instance2=sso-instance-2
sso_instance=${sso_instance1}

is_sso_instance1_available=false
is_sso_instance2_available=false

sleep_user_change=5
max_iteration=10

iPlanetDirectoryPro="iPlanetDirectoryPro"

rm -f ${openam_admin_cookie} ${enm_admin_cookie} ${enm_user_cookie}

login_and_logout() {
	user=$1
	pwd=$2
	cookie=$3
	status=$4
	login ${user} ${pwd} ${cookie} ${status}
	if [ "${status}" = true ]; then
		logout ${user} ${cookie}
	fi
}

logout() {
	user=$1
	cookie=$2
	echo "Logging out as ${user}"

	status_code=$(curl --insecure --write-out %{http_code} --output /dev/null -s -L --request GET --cookie ${cookie} "https://${HAPROXY_URL}/logout")
	if [ ${status_code} -ne 200 ]; then
		echo "Logout failed for user: ${user}, status_code = ${status_code}"
		exit 1
	fi

}


login() {
	user=$1
	pwd=$2
	cookie=$3
	status=$4
	echo "Logging in as ${user}, pwd: ${pwd}"
	rm -f ${cookie}
	curl --insecure -s --request POST --cookie-jar ${cookie} "https://${HAPROXY_URL}/login?IDToken1=${user}&IDToken2=${pwd}" > /dev/null

	result=1
	cat ${cookie} | grep ${iPlanetDirectoryPro} > /dev/null
	result=$?

	if [ "$status" = true ] && [ ${result} -eq 0 ]; then
		echo "Login successful as expected for user: ${user} pwd: ${pwd}"
	elif [ "$status" = false ] && [ ${result} -ne 0 ]; then
		echo "Login not successful as expected for user: ${user} pwd: ${pwd}"
	else
		echo "Error it was expected status=${status} but result=${result} for user: ${user} pwd: ${pwd}"
		exit 1
	fi
}


get_extidp() {
   	echo "#PHASE GETTING EXTERNAL IDP FEATURE"
    extIdp_authn=$1
    cookie=$2
    profile=$3
	value=$(curl -i -o - --insecure --request GET -s --cookie ${cookie} "https://${HAPROXY_URL}/oss/idm/config/extidp/settings")

	echo ${value} | grep "HTTP/1.1 200 OK" > /dev/null
	result=$?

	if [ ${result} -ne 0 ]; then
		echo "Error found in HTTP code"
		echo "${value}"
		exit 1
	fi

	if [ ${profile} == ${extIdp_profile_standard} ]; then
		userBindDNFormat=${extIdp_userBindDNFormat_standard}
	elif [ ${profile} == ${extIdp_profile_nosearch} ]; then
		userBindDNFormat=${extIdp_userBindDNFormat_nosearch}
	else
		echo "Unknown remoteAuthProfile ${profile}"
		exit 1
	fi

	echo ${value} | grep "\"isBindPasswordEmpty\":false" > /dev/null
	result=$?

	if [ ${result} -ne 0 ]; then
		echo "Error found in isBindPasswordEmpty"
		echo "${value}"
		exit 1
	fi

	echo ${value} | grep "\"authType\":\"${extIdp_authn}\"" > /dev/null
	result=$?

	if [ ${result} -ne 0 ]; then
		echo "Error found in authType"
		echo "${value}"
		exit 1
	fi

	echo ${value} | grep "\"remoteAuthProfile\":\"${profile}\"" > /dev/null
	result=$?

	if [ ${result} -ne 0 ]; then
		echo "Error found in remoteAuthProfile"
		echo "${value}"
		exit 1
	fi

	echo ${value} | grep "\"baseDN\":\"${extIdp_baseDN}\"" > /dev/null
	result=$?

	if [ ${result} -ne 0 ]; then
		echo "Error found in baseDN"
		echo "${value}"
		exit 1
	fi

	echo ${value} | grep "\"primaryServerAddress\":\"${extIdp_primaryServerAddress}\"" > /dev/null
	result=$?

	if [ ${result} -ne 0 ]; then
		echo "Error found in primaryServerAddress"
		echo "${value}"
		exit 1
	fi

	echo ${value} | grep "\"secondaryServerAddress\":\"${extIdp_secondaryServerAddress}\"" > /dev/null
	result=$?

	if [ ${result} -ne 0 ]; then
		echo "Error found in secondaryServerAddress"
		echo "${value}"
		exit 1
	fi

	echo ${value} | grep "\"ldapConnectionMode\":\"${extIdp_ldapConnectionMode}\"" > /dev/null
	result=$?

	if [ ${result} -ne 0 ]; then
		echo "Error found in ldapConnectionMode"
		echo "${value}"
		exit 1
	fi


	echo ${value} | grep "\"bindDN\":\"${extIdp_bindDN}\"" > /dev/null
	result=$?

	if [ ${result} -ne 0 ]; then
		echo "Error found in bindDN"
		echo "${value}"
		exit 1
	fi

	echo ${value} | grep "\"bindPassword\":\"\"" > /dev/null
	result=$?

	if [ ${result} -ne 0 ]; then
		echo "Error found in bindPassword"
		echo "${value}"
		exit 1
	fi

	echo ${value} | grep "\"userBindDNFormat\":\"${userBindDNFormat}\"" > /dev/null
	result=$?

	if [ ${result} -ne 0 ]; then
		echo "Error found in userBindDNFormat"
		echo "${value}"
		exit 1
	fi
	echo "External IDP got correctly"

}


set_extidp() {
    extIdp_authn=$1
    cookie=$2
    profile=$3

	if [ ${profile} == ${extIdp_profile_standard} ]; then
		profile=${extIdp_profile_standard}
		# curl --insecure -s --request PUT --cookie ${cookie} "https://${HAPROXY_URL}/oss/idm/config/extidp/settings" -H "Content-Type: application/json" -d '{ "remoteAuthProfile":"'${profile}'", "authType":"'${extIdp_authn}'", "primaryServerAddress":"10.45.205.253:1389", "secondaryServerAddress":"141.137.87.62:6389", "baseDN":"dc=acme,dc=com", "ldapConnectionMode":"LDAP", "userBindDNFormat":"uid=$user", "bindDN":"cn=extldapadmin,ou=people,dc=acme,dc=com", "bindPassword": "'${extIdp_password}'" }' > /dev/null
		
		status_code=$(curl --write-out %{http_code} --output /dev/null  --insecure -s --request PUT --cookie ${cookie} "https://${HAPROXY_URL}/oss/idm/config/extidp/settings" -H "Content-Type: application/json" -d '{ "remoteAuthProfile":"'${profile}'", "authType":"'${extIdp_authn}'", "primaryServerAddress":"10.45.205.253:1389", "secondaryServerAddress":"141.137.87.62:6389", "baseDN":"dc=acme,dc=com", "ldapConnectionMode":"LDAP", "userBindDNFormat":"uid=$user", "bindDN":"cn=extldapadmin,ou=people,dc=acme,dc=com", "bindPassword": "'${extIdp_password}'" }')


	elif [ ${profile} == ${extIdp_profile_nosearch} ]; then
		profile=${extIdp_profile_nosearch}
		#curl --insecure -s --request PUT --cookie ${cookie} "https://${HAPROXY_URL}/oss/idm/config/extidp/settings" -H "Content-Type: application/json" -d '{ "remoteAuthProfile":"'${profile}'", "authType":"'${extIdp_authn}'", "primaryServerAddress":"10.45.205.253:1389", "secondaryServerAddress":"141.137.87.62:6389", "baseDN":"dc=acme,dc=com", "ldapConnectionMode":"LDAP", "userBindDNFormat":"uid=$user,ou=pdu nam,dc=acme,dc=com", "bindDN":"cn=extldapadmin,ou=people,dc=acme,dc=com", "bindPassword": "'${extIdp_password}'" }' > /dev/null

		status_code=$(curl --write-out %{http_code} --output /dev/null  --insecure -s --request PUT --cookie ${cookie} "https://${HAPROXY_URL}/oss/idm/config/extidp/settings" -H "Content-Type: application/json" -d '{ "remoteAuthProfile":"'${profile}'", "authType":"'${extIdp_authn}'", "primaryServerAddress":"10.45.205.253:1389", "secondaryServerAddress":"141.137.87.62:6389", "baseDN":"dc=acme,dc=com", "ldapConnectionMode":"LDAP", "userBindDNFormat":"uid=$user,ou=pdu nam,dc=acme,dc=com", "bindDN":"cn=extldapadmin,ou=people,dc=acme,dc=com", "bindPassword": "'${extIdp_password}'" }')

	else
		echo "Unknown remoteAuthProfile ${profile}"
		exit 1
	fi
	echo "#PHASE SETTING EXTERNAL IDP FEATURE: authType = ${extIdp_authn}, remoteauthprofile = ${profile}"
	if [ ${status_code} -ne 200 ]; then
		echo "Error found, status_code ${status_code}"
		exit 1
	fi

}


delete_user() {
	user_to_delete=$1
	cookie=$2
	echo "#PHASE DELETE USER ${user_to_delete}"
	status_code=$(curl --write-out %{http_code} --output /dev/null --insecure -s --request DELETE -b ${cookie} "https://${HAPROXY_URL}/oss/idm/usermanagement/users/${user_to_delete}")

	if [ ${status_code} -ne 204 ] && [ ${status_code} -ne 404 ]; then
		echo "Error found, status_code ${status_code}"
		exit 1
	fi

}

create_user() {
	user_to_create=$1
	authMode=$2
	cookie=$3
	echo "#PHASE CREATE USER ${user_to_create} with authMode ${authMode}"
	#curl --insecure -s --request POST -H "Content-Type: application/json" -b ${cookie} "https://${HAPROXY_URL}/oss/idm/usermanagement/users" -d '{"privileges":[{"role":"Adaptation_cm_nb_integration_Administrator","targetGroup":"ALL"}],"status":"enabled","passwordResetFlag":false,"passwordAgeing":{"customizedPasswordAgeingEnable":false,"passwordAgeingEnable":false,"pwdMaxAge":"","pwdExpireWarning":"","graceLoginCount":0},"username":"'${user_to_create}'","name":"Lu","surname":"Bo","email":"aaa@bbb.com","password":"TestPassw0rd", "authMode":"'${authMode}'"}' > /dev/null


	status_code=$(curl --write-out %{http_code} --output /dev/null  --insecure -s --request POST -H "Content-Type: application/json" -b ${cookie} "https://${HAPROXY_URL}/oss/idm/usermanagement/users" -d '{"privileges":[{"role":"Adaptation_cm_nb_integration_Administrator","targetGroup":"ALL"}],"status":"enabled","passwordResetFlag":false,"passwordAgeing":{"customizedPasswordAgeingEnable":false,"passwordAgeingEnable":false,"pwdMaxAge":"","pwdExpireWarning":"","graceLoginCount":0},"username":"'${user_to_create}'","name":"Lu","surname":"Bo","email":"aaa@bbb.com","password":"TestPassw0rd", "authMode":"'${authMode}'"}')

	if [ ${status_code} -ne 201 ]; then
		echo "Error found, status_code ${status_code}"
		exit 1
	fi
}



update_user() {
	user=$1
	authMode=$2
	cookie=$3
	echo "Updating user ${user} with authMode ${authMode}"
	curl --insecure -s --request PUT -H "Content-Type: application/json" -b ${cookie} "https://${HAPROXY_URL}/oss/idm/usermanagement/users/${user}" -d  '{"privileges":[{"role":"Adaptation_cm_nb_integration_Administrator","targetGroup":"ALL"}],"status":"enabled","passwordResetFlag":false,"username":"'${user}'","name":"Lu","surname":"Bo","email":"aaa@bbb.com","description":null,"passwordChangeTime":"20181030141037+0000","maxSessionTime":null,"maxIdleTime":null,"authMode":"'${authMode}'","passwordAgeing":{"customizedPasswordAgeingEnable":false,"passwordAgeingEnable":false,"pwdMaxAge":"","pwdExpireWarning":"","graceLoginCount":0}}' > /dev/null
}

verify_cookie() {
	cookie_file=$1
	cat ${cookie_file} | grep ${iPlanetDirectoryPro} > /dev/null
	if [ $? -ne 0 ]; then
	    echo "Invalid login for cookie ${cookie_file}"
	    exit 1
	fi	
}

test_sso() {
	sso=${sso_instance1}
	echo "#PHASE TESTING SSO CONNECTIVITY ON ${sso}.${HAPROXY_URL}"
	ping ${sso}.${HAPROXY_URL} -c 3 > /dev/null
	result=$?
	echo "Result of ping is ${result}"
	if [ ${result} -ne 0 ]; then
		echo "CONNECTION ERROR - ${sso}.${HAPROXY_URL} not responding."
		is_sso_instance1_available=false
	else
		is_sso_instance1_available=true
	fi

	sso=${sso_instance2}
	echo "#PHASE TESTING SSO CONNECTIVITY ON ${sso}.${HAPROXY_URL}"
	ping ${sso}.${HAPROXY_URL} -c 3 > /dev/null
	result=$?
	echo "Result of ping is ${result}"
	if [ ${result} -ne 0 ]; then
		echo "CONNECTION ERROR - ${sso}.${HAPROXY_URL} not responding."
		is_sso_instance2_available=false
	else
		is_sso_instance2_available=true
	fi
	echo "Setting is_sso_instance1_available to ${is_sso_instance1_available}"
	echo "Setting is_sso_instance2_available to ${is_sso_instance2_available}"
}

verify_singleDatastore() {
	sso=$1
	user=$2
	expected_remote_auth=$3
	expected_dataToBeFound=$4

	datastore_result=`curl -s --header "iPlanetdirectorypro: ${openam_admin_token}" --header "Content-Type: application/json" http://${sso}.${HAPROXY_URL}:8080/heimdallr/json/users/${user}`
	
	echo ${datastore_result} | grep -e "ericssonAuthMode\":\[\"${expected_remote_auth}\"" > /dev/null
	result=$?

	if [ ${expected_dataToBeFound}=true ]; then
		if [ ${result} -eq 0 ]; then
			echo "Datastore on ${sso} successfully returns ericssonAuthMode = ${expected_remote_auth}"
		else
			echo "ERROR - Datastore on ${sso} has invalid content."
			echo "Expected ericssonAuthMode = ${expected_remote_auth}"
			echo "Actual Datastore = ${datastore_result}"
			exit 1
		fi
	else
		echo "NOT IMPLEMENTED YET"
	fi


}
 
verify_datastores() {
	user=$1
	expected_remote_auth=$2
	expected_dataToBeFound=$3

	if [ "${is_sso_instance1_available}" = true ]; then
		sso=${sso_instance1}
		echo "Single datastore check for sso ${sso}"
		verify_singleDatastore ${sso} ${user} ${expected_remote_auth} ${expected_dataToBeFound}
	fi
	if [ "${is_sso_instance2_available}" = true ]; then
		sso=${sso_instance2}
		echo "Single datastore check for sso ${sso}"
		verify_singleDatastore ${sso} ${user} ${expected_remote_auth} ${expected_dataToBeFound}
	fi

}

# PHASE TEST SSO CONNECTIVITY
test_sso

# PHASE OPENAM ADMIN REST LOGIN
echo "#PHASE OPENAM ADMIN REST LOGIN"
curl -s --insecure --request POST --cookie-jar ${openam_admin_cookie} "http://${sso_instance}.${HAPROXY_URL}:8080/heimdallr/UI/Login?IDToken1=${openam_admin}&IDToken2=${openam_admin_pwd}&service=datastore"

verify_cookie ${openam_admin_cookie}

# PHASE GET USER FROM OPENAM DATASTORE
echo "#PHASE GET USER FROM OPENAM DATASTORE"
openam_admin_token=`cat ${openam_admin_cookie} | grep ${iPlanetDirectoryPro} | awk {'print $7'}`

# PHASE LOGIN as ENM ADMIN
echo "#PHASE LOGIN as ENM ADMIN"
login ${enm_admin} ${enm_admin_pwd} ${enm_admin_cookie} true
verify_cookie ${enm_admin_cookie}


# PHASE DELETE USER
delete_user ${enm_target_user} ${enm_admin_cookie}

echo "Sleeping for ${sleep_user_change} sec"
sleep ${sleep_user_change}

COUNTER=1
while [  $COUNTER -le ${max_iteration} ]; do
    echo "============== Iteration $COUNTER of ${max_iteration} =============="


    profile=${extIdp_profile_standard}
    if ! (($COUNTER % 2)); then
   	    profile=${extIdp_profile_nosearch}
   	    echo "Switching to profile ${profile}"
    fi
	# PHASE CONFIGURE EXTERNAL IDP TO REMOTE
	set_extidp ${extIdp_REMOTEAUTHN} ${enm_admin_cookie} ${profile}
	get_extidp ${extIdp_REMOTEAUTHN} ${enm_admin_cookie} ${profile}
	
	# PHASE CREATE USER [LOCAL]
	enm_user_authmode=${enm_user_authmode_local}
	create_user ${enm_target_user} ${enm_user_authmode} ${enm_admin_cookie}
	echo "Sleeping for ${sleep_user_change} sec"
	sleep ${sleep_user_change}
	verify_datastores ${enm_target_user} ${enm_user_authmode} true

	login_and_logout ${enm_target_user} ${local_password} ${enm_user_cookie} true
	login_and_logout ${enm_target_user} ${remote_password} ${enm_user_cookie} false

	# PHASE UPDATE USER [REMOTE]
	enm_user_authmode=${enm_user_authmode_remote}
	update_user ${enm_target_user} ${enm_user_authmode} ${enm_admin_cookie}
	echo "Sleeping for ${sleep_user_change} sec"
	sleep ${sleep_user_change}
	verify_datastores ${enm_target_user} ${enm_user_authmode} true

	login_and_logout ${enm_target_user} ${local_password} ${enm_user_cookie} false
	login_and_logout ${enm_target_user} ${remote_password} ${enm_user_cookie} true

	# PHASE UPDATE USER [LOCAL]
	enm_user_authmode=${enm_user_authmode_local}
	update_user ${enm_target_user} ${enm_user_authmode} ${enm_admin_cookie}

	echo "Sleeping for ${sleep_user_change} sec"
	sleep ${sleep_user_change}
	verify_datastores ${enm_target_user} ${enm_user_authmode} true

	login_and_logout ${enm_target_user} ${local_password} ${enm_user_cookie} true
	login_and_logout ${enm_target_user} ${remote_password} ${enm_user_cookie} false


	#PHASE UPDATE USER [REMOTE]
	enm_user_authmode=${enm_user_authmode_remote}
	update_user ${enm_target_user} ${enm_user_authmode} ${enm_admin_cookie}

	echo "Sleeping for ${sleep_user_change} sec"
	sleep ${sleep_user_change}
	verify_datastores ${enm_target_user} ${enm_user_authmode} true

	login_and_logout ${enm_target_user} ${local_password} ${enm_user_cookie} false
	login_and_logout ${enm_target_user} ${remote_password} ${enm_user_cookie} true


	#PHASE DELETE USER
	delete_user ${enm_target_user} ${enm_admin_cookie}

    let COUNTER=COUNTER+1 
done

echo "===Completed successfully after ${max_iteration} iterations==="

logout ${enm_admin} ${enm_admin_cookie}
logout ${openam_admin} ${openam_admin_cookie}l