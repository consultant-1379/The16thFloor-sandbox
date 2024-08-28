#!/bin/bash

# This function performs a LOGIN via REST.
source "./utilities_consts.sh" || exit -1

# Cookie is stored in $3
login() {
        user=$1
        pwd=$2
        cookie=$3
        file=$4
        use_jwt=$5
        echo "`date '+%F %T.%3N'` Logging in as user ${user}, pwd ${pwd} using cookie file ${cookie}" >> $file
        rm -f ${cookie}

        r=$RANDOM
        if [ $((r % 2)) != 0 ]; then
          if ( "$use_jwt" ); then
            curl -s -L --insecure --request POST --cookie-jar ${cookie} "https://${HAPROXY_URL}/login?IDToken1=${user}&IDToken2=${pwd}" > /dev/null
          else
            curl -s --insecure --request POST --cookie-jar ${cookie} "https://${HAPROXY_URL}/login?IDToken1=${user}&IDToken2=${pwd}" > /dev/null
            loginSequenceMessage=" -> IDToken1=${user}&IDToken2=${pwd} sequence"
          fi
        else
          if ( "$use_jwt" ) ; then
            curl -s -L --insecure --request POST --cookie-jar ${cookie} "https://${HAPROXY_URL}/login?IDToken2=${pwd}&IDToken1=${user}" > /dev/null
          else
            curl -s --insecure --request POST --cookie-jar ${cookie} "https://${HAPROXY_URL}/login?IDToken2=${pwd}&IDToken1=${user}" > /dev/null
            loginSequenceMessage=" -> IDToken2=${pwd}&IDToken1=${user} sequence"
          fi
        fi

        result=1
        if ( "$use_jwt" ); then
          cat ${cookie} | grep ${JWT} > /dev/null
        else
          cat ${cookie} | grep ${IPLANETDIRECTORYPRO} > /dev/null
        fi
        result=$?

        if [ ${result} -eq 0 ]; then
                echo "Login successful for user: ${user} pwd: ${pwd} cookie: ${cookie}" >> $file
        else
                echo "`date '+%F %T.%3N'` Error login for user: ${user} pwd: ${pwd} cookie: ${cookie}" >> $file
                echo ${loginSequenceMessage} >> $file
        fi
        echo ${result}
}

# This function performs a LOGOUT via REST.
# Cookie is stored in $2
logout() {
        user=$1
        cookie=$2
        file=$3
        echo "`date '+%F %T.%3N'` Logging out as ${user} and cookie ${cookie}" >> ${file}

        status_code=$(curl --insecure --write-out %{http_code} --output /dev/null -s -L --request GET --cookie ${cookie} "https://${HAPROXY_URL}/logout")
        result=1
        if [ ${status_code} -ne 200 ]; then
                echo "`date '+%F %T.%3N'` Logout failed for user: ${user}, status_code = ${status_code}" >> ${file}
        else
                rm -f ${cookie}
                result=0
        fi
        echo $result
}

# Create user via REST
create_user() {
        username=$1
        pwd=$2
        authMode=$3
        cookie=$4
        echo "Create user ${username}, pwd ${pwd}, authMode ${authMode}"

        status_code=$(curl --write-out %{http_code} --output /dev/null  --insecure -s --request POST -H "Content-Type: application/json" -b ${cookie} "https://${HAPROXY_URL}/oss/idm/usermanagement/users" -d '{"privileges":[{"role":"Adaptation_cm_nb_integration_Administrator","targetGroup":"ALL"}],"status":"enabled","passwordResetFlag":false,"passwordAgeing":{"customizedPasswordAgeingEnable":false,"passwordAgeingEnable":false,"pwdMaxAge":"","pwdExpireWarning":"","graceLoginCount":0},"username":"'${username}'","name":"'${username}'","surname":"'${username}'","email":"aaa@bbb.com","password":"'${pwd}'", "authMode":"'${authMode}'"}')

        if [ ${status_code} -ne 201 ]; then
                echo "Error found, status_code ${status_code}"
                exit 1
        fi
}

# Delete user via REST
delete_user() {
        user_to_delete=$1
        cookie=$2
        echo "Delete user ${user_to_delete}"
        status_code=$(curl --write-out %{http_code} --output /dev/null --insecure -s --request DELETE -b ${cookie} "https://${HAPROXY_URL}/oss/idm/usermanagement/users/${user_to_delete}")

        if [ ${status_code} -ne 204 ] && [ ${status_code} -ne 404 ]; then
                echo "Error found, status_code ${status_code}"
                exit 1
        fi
}

# Set the External IDP feature via REST
set_extidp() {
    extIdp_authn=$1
    profile=$2
    cookie=$3
        echo "SETTING ExtIDP ..."
        echo "extIdp_authn is $extIdp_authn"
        echo "profile is $profile"
        echo "HAPROXY_URL is $HAPROXY_URL"
        echo "extIdp_password is $EXTIDP_BIND_PASSWORD"
        echo "Primary server: ${EXTIDP_PRIMARY_SERVER}"
        echo "Secondary server: ${EXTIDP_SECONDARY_SERVER}"
        echo "Base DN: ${EXTIDP_BASE_DN}"
        echo "Bind DN Format: ${EXTIDP_USER_BIND_DN_FORMAT}"
        echo "Bind DN: ${EXTIDP_BIND_DN}"
        echo "Bind password: ${EXTIDP_BIND_PASSWORD}"

        status_code=$(curl --write-out %{http_code} --output /dev/null -s --insecure --request PUT --cookie ${cookie} "https://${HAPROXY_URL}/oss/idm/config/extidp/settings" -H "Content-Type: application/json" -d '{ "remoteAuthProfile":"'${profile}'", "authType":"'${extIdp_authn}'", "primaryServerAddress":"'${EXTIDP_PRIMARY_SERVER}'", "secondaryServerAddress":"'${EXTIDP_SECONDARY_SERVER}'", "baseDN":"'${EXTIDP_BASE_DN}'", "ldapConnectionMode":"LDAP", "userBindDNFormat":"'${EXTIDP_USER_BIND_DN_FORMAT}'", "bindDN":"'${EXTIDP_BIND_DN}'", "bindPassword": "'${EXTIDP_BIND_PASSWORD}'" }')

        if [ ${status_code} -ne 200 ]; then
                echo "Error found, status_code ${status_code}"
                exit 1
        else
                echo "ExtIdp configured !"
        fi
}


# This function is used to validate cookie in a rotary mode among 4 different REST
verifyCookieRotary () {
        cookie=$1               # user's cookie
        counter=$2              # iteration
        policy=$3               # it defines if session is valid or not
        failOnError=$4  #
        file=$5                 # file with log
        samples=$6              # file with samples
        user=$7                 # user
        # 4 different REST to be called
#       requestUrl_nscs="https://$HAPROXY_URL/node-security/pib/confparam/wfCongestionThreshold"
        requestUrl_alarm="https://$HAPROXY_URL/alarmcontroldisplayservice/alarmMonitoring/model/targetTypeInformation"
        requestUrl_webpush="https://$HAPROXY_URL/web-push/rest/oss/push/id"
        requestUrl_pki="https://$HAPROXY_URL/locales/en-us/pkicertificates/dictionary.json"
    requestUrl_secserv="https://$HAPROXY_URL/oss/idm/usermanagement/users/$user?username=true"

        # 4 different expected result
#       validationString_nscs="wfCongestionThreshold:"
        validationString_alarm="RBS"
        validationString_webpush="id"
        validationString_pki="popupDatePickerLabels"
    validationString_secserv="{\"username\": \"$user\"}"

        #r=$(($RANDOM % 5))
        r=$RANDOM
        s=$((r+counter))
        validationCase=$((s % 4))
        #validationCase=4
        if [ ${validationCase} -eq 3 ]; then
                #echo "Detected PKI case" >> ${file}
                requestUrl=${requestUrl_pki}
                validationString=${validationString_pki}
                validation_mode="PKI"
        elif [ ${validationCase} -eq 2 ]; then
                #echo "Detected ALARM case" >> ${file}
                requestUrl=${requestUrl_alarm}
                validationString=${validationString_alarm}
                validation_mode="ALR"
        elif [ ${validationCase} -eq 1 ]; then
                #echo "Detected WEBPUSH case" >> ${file}
                requestUrl=${requestUrl_webpush}
                validationString=${validationString_webpush}
                validation_mode="WPUSH"
#       elif [ ${validationCase} -eq 4 ]; then
#               #echo "Detected NSCS case" >> ${file}
#               requestUrl=${requestUrl_nscs}
#               validationString=${validationString_nscs}
#               validation_mode="NSCS"
        else
                #echo "Detected Default SECSERV case" >> ${file}
        requestUrl=${requestUrl_secserv}
        validationString=${validationString_secserv}
        validation_mode="SECSERV"
        fi

        if [ ! -z ${REDUCE_LOG} ]; then
                if [ ${REDUCE_LOG} = false ]; then
                        echo "- - requestUrl= ${requestUrl}" >> $file
                fi
        fi

        verifystart=$(echo $(($(date +%s%N)/1000000)))
        time=$(echo $(date '+%F %T.%3N'))
        verification_response=`curl --insecure --raw --request GET -s -i --cookie ${cookie} ${requestUrl}`
        verifyend=$(echo $(($(date +%s%N)/1000000)))
        verifyduration=$(( verifyend - verifystart ))

        sleep 0.5

        #echo "Time diff is: $verifyduration"
        http_validation_code=${verification_response:0:12}
        e2e_verification_message=`echo $verification_response | grep "${validationString}"`

        if [ ! -z ${REDUCE_LOG} ]; then
                if [ ${REDUCE_LOG} = false ]; then
                        echo "curl --insecure --raw --request GET -s -i --cookie $sesfolder/${usedCookie}.txt ${requestUrl}"
                        echo $verification_response >> $file
                fi
        fi

        if [ -z "${e2e_verification_message}" ]; then
                #Verification failed because no value returned in REST
                e2eMessage="- - Verification: NOT OK - ERROR code: ${http_validation_code}, type ${validation_mode}, duration: ${verifyduration}"
                echo "$time,$user,VERIFY,${validation_mode},FAILED,0" >> $samples

                if [ "${policy}" == "${SESSION_ISVALID}" ]; then
                        if [ ${failOnError} = true ]; then
                                exit 1
                        fi
                else
                        echo "Expected invalid scenario"
                fi

        else
                e2eMessage="- - Verification: OK, type ${validation_mode}, duration: ${verifyduration}"
                echo "$time,$user,VERIFY,${validation_mode},OK,$verifyduration" >> $samples

                if [ "${policy}" == "${SESSION_ISINVALID}" ]; then
                        if [ ${failOnError} = true ]; then
                                exit 1
                        fi
                else
                verifyarrayperfms+=($verifyduration)
                fi
        fi
        echo ${e2eMessage} >> $file
}


# Check whenever sso instance is alive and return string comma separated,
# referring to status of sso-instance-1 and sso-instance-2 availability status
test_sso() {
        sso=${SSO_INSTANCE1}
        # echo "#PHASE TESTING SSO CONNECTIVITY ON ${sso}.${HAPROXY_URL}"
        ping ${sso}.${HAPROXY_URL} -c 3 > /dev/null
        result=$?
        # echo "Result of ping is ${result}"
        if [ ${result} -ne 0 ]; then
                #echo "CONNECTION ERROR - ${sso}.${HAPROXY_URL} not responding."
                is_sso_instance1_available=false
        else
                is_sso_instance1_available=true
        fi

        sso=${SSO_INSTANCE2}
        # echo "#PHASE TESTING SSO CONNECTIVITY ON ${sso}.${HAPROXY_URL}"
        ping ${sso}.${HAPROXY_URL} -c 3 > /dev/null
        result=$?
        # echo "Result of ping is ${result}"
        if [ ${result} -ne 0 ]; then
                #echo "CONNECTION ERROR - ${sso}.${HAPROXY_URL} not responding."
                is_sso_instance2_available=false
        else
                is_sso_instance2_available=true
        fi
        # echo "Setting is_sso_instance1_available to ${is_sso_instance1_available}"
        # echo "Setting is_sso_instance2_available to ${is_sso_instance2_available}"

        echo "${is_sso_instance1_available},${is_sso_instance2_available}"

}


# Validate the token using internal REST, returing string as
#Case of invalid token: {"valid":false}
#Case of valid token: {"valid":true,"uid":"administrator","realm":"/"}
validateToken() {

        sso_instance=$1
        cookie=$2
        expected=$3

        token=`cat ${cookie} | grep ${IPLANETDIRECTORYPRO} | awk '{print $7}' | cut -d'~' -f2`
        # Cookie format for validation is
        #From:
        #iPlanetDirectoryPro=S1~AQIC5wM2LY4Sfcy0pO8roRjVWBmET6M5OPOz4_8kVFljtmc.*AAJTSQACMDIAAlNLABQtNTU4NjA0OTU0NjM1MjYxOTM1OQACUzEAAjAz*
        #
        #To:
        #AQIC5wM2LY4Sfcy0pO8roRjVWBmET6M5OPOz4_8kVFljtmc.*AAJTSQACMDIAAlNLABQtNTU4NjA0OTU0NjM1MjYxOTM1OQACUzEAAjAz*

        validate=`curl -X POST --header "Content-Type: application/json" "http://${sso_instance}.${HAPROXY_URL}:8080/heimdallr/json/sessions/${token}?_action=validate"`

        echo ${validate} | grep -e "\"valid\":true"
        result=$?

        finalresult=0
        if [ "${expected}" == "${SESSION_ISVALID}" ]; then
                echo "Token must be valid"
                if [ ${result} -ne 0 ]; then
                        echo "Error in token validation, returned value ${validate}"
                        finalresult=1
                fi
        else
                echo "Token must be not valid"
                if [ ${result} -eq 0 ]; then
                        echo "Error token expected to be invalid but returned value ${validate}"
                        finalresult=1
                fi
        fi

        return $finalresult
}

makeAllSamplesFile() {
# $1 represents test TARGET DIR in which all file are saved
        finale="$1/allSamples.csv"
        temp="$1/tmp.csv"
        for element in $1/*samples.csv; do

          #read each *samples.csv files and concatenate in a single file
          tail -n +2 $element >> $temp
          #read HEADER
          header=$(head -n 1 $element)

        done

        #insert HEADER
        sed -i "1s/^/$header\n/" $temp
        #remove blank lines
        sed -e "/^$/d" $temp > $finale
        rm -f $temp

                #lines=$( wc -l < $finale )
        #echo "Create 'allSamples.csv' file with $lines cronological samples"
}
