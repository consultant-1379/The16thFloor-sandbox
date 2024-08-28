#!/bin/bash
# This script reads a 'users' file (gained from "./system.sh" file) and for each user, launch the user related script in background.
#

source "./system.sh" || exit -1
source "./utilities_library.sh" || exit -1

mkdir -p $TARGET_DIR
globalLogin=$TARGET_DIR/$GLOBAL_LOGIN
globalLogout=$TARGET_DIR/$GLOBAL_LOGOUT
globalVerify=$TARGET_DIR/$GLOBAL_VERIFY
headers=$HEADERS
users=USERS_FILES/$USER_FILE
enm_administrator=$ENM_ADMINISTRATOR_USERNAME
enm_administrator_pwd=$ENM_ADMINISTRATOR_PWD
enm_administrator_cookie=$ENM_ADMINISTRATOR_COOKIE
test_error_file=${TEST_ERROR_FILE}
logfile=./.parallel_log_file.txt
use_jwt=$USE_JWT

#Remove any error flag file if present
rm -f ${TEST_ERROR_FILE} ${logfile}

log_files_creation ${ASYNC}

if [[ -e $users ]]; then
    echo "$users file is present !!"
	echo "Haproxy: $HAPROXY_URL"
	echo "Users: $USERS"
	echo "Iteration: $ITERATION"
	echo "Sessions: $SESSIONS"
	echo "Verifications: $VERIFY_PER_SESSION"
	echo "Do verify: $VERIFICATION"
	echo "Do logout: $LOGOUT"
	echo ""
	
	if [[ "${CREATE_USERS}" = true || "${ENABLE_EXTIDP}" = true ]]; then
		#Logging in as administrator
		echo "Logging in as administrator"
		login ${enm_administrator} ${enm_administrator_pwd} ${enm_administrator_cookie} ${logfile} ${use_jwt}
	fi

    #Manage users creation
    if [ "${CREATE_USERS}" = true ]; then
    	echo "Creating users..."
	    while IFS=',' read -r line || [[ -n "$line" ]]; 
	    do
			usr="$(cut -d',' -f1 <<<"$line")"
			#pwd="$(cut -d',' -f2 <<<"$line")"
			authMode="$(cut -d',' -f3 <<<"$line")"
			#verify 'remote' user has a local pswd to be used for creation
			if [ ${authMode} == "remote" ]; then
			   pwd="$(cut -d',' -f4 <<<"$line")"
			else
			   pwd="$(cut -d',' -f2 <<<"$line")"
			fi
			echo "user: ${usr}"
			echo "pswd: ${pwd}"
			[ -z "$usr" ] && echo "Empty usr variable, exiting" && exit 1
			[ -z "$pwd" ] && echo "Empty pwd variable, exiting" && exit 1
			[ -z "$authMode" ] && echo "Empty authMode variable, exiting" && exit 1

			if [ "${enm_administrator}" == "${usr}" ]; then
				echo "User ${usr} will not be created"
			else
				echo "Creating new user ${usr}"
	        	# Creating new user
	         	delete_user $usr ${enm_administrator_cookie}
	         	sleep 1
	         	create_user $usr $pwd $authMode ${enm_administrator_cookie}
	         	sleep 1
			fi
	    done < "$users" 
		echo "Extra sleep after user creation"
	   	sleep 10
	else
		echo "No users to be created"
	fi

    #Manage Ext IDP
    if [ "${ENABLE_EXTIDP}" = true ]; then
		echo "External IDP to be configured"
		set_extidp ${EXTIDP_REMOTEAUTHN} ${EXTIDP_PROFILE_DEFAULT} ${enm_administrator_cookie}
		sleep 5
	else
		echo "No External Idp to be configured"
    fi

    i=0
    while IFS=',' read -r line || [[ -n "$line" ]]; 
    do
        i=$(( i + 1 ))
        #echo "Text read from file: $line"
		usr="$(cut -d',' -f1 <<<"$line")"
		pwd="$(cut -d',' -f2 <<<"$line")"

        # launch single user script
        if [ "${ASYNC}" = true ]; then
        	./sso_test_login_async.sh  $usr $pwd $i &
			if [ ${DO_LOGOUT} ]; then
				./sso_test_logout_async.sh $usr $i &
			fi
        else
        	./sso_test_benchmarking.sh  $usr $pwd $i &
        fi
	sleep ${DELAY_BETWEEN_USERS}
    done < "$users" 
    wait

    if [ -f ${test_error_file} ]; then
    	echo "TEST NOT PASSED. Found error flag file at ${test_error_file}"
    	exit 1
    else
	if [ ${ASYNC} = false ]; then
    		echo "TEST PASSED"
	else
		echo "TEST COMPLETED"
		./sso_test_collectResult_async.sh $TARGET_DIR "login"
		./sso_test_collectResult_async.sh $TARGET_DIR "logout"
	fi
    fi

    if [ "${PERFORM_SESSION_TEST}" = true ]; then 
    	./sso_sessions.sh
    else
    	echo "Session duration test skipped"
    fi
    
    if [ "${ASYNC}" = false ]; then
	makeAllSamplesFile $TARGET_DIR
	echo "Create 'allSamples.csv' file with cronological samples list"
    fi
else
    echo "$users file is NOT present !!"
    exit 1
fi

exit 0


