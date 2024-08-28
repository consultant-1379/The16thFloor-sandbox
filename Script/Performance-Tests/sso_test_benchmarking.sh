#!/bin/bash
# This script works with 'system.sh' and 'sso_test_parallel.sh'
#
# This script performs three main action: Login, Verify and Logout,
# Performing Verify and Logout actions is conditional to VERIFICATION and LOGOUT paramenets defined in system.sh.
# It receives in INPUT username, userpswd and a progressive number (the instance) associated to the user (used also to create a cookie directory).
# Each user repeats for a number equal to 'iteration', Login, Verify and Logout.
# For each action, the pertinant duration is gained and stored in '_traces.txt' file.
# This database will be used to obtain a Min, Avg, Max values for the action (Login, Verify and Logout).
# Verify action is made ina rotary way, using one of the 4 possible REST and verifying the expected result.
#
# OUTPUT: '_data.txt' and '_traces.txt' file
#

# from source-file "./system.sh"
source "./system.sh" || exit -1 
source "./utilities_library.sh" || exit -1


globalLogin=$TARGET_DIR/$GLOBAL_LOGIN	# csv file for Login data reporting
globalLogout=$TARGET_DIR/$GLOBAL_LOGOUT	# csv file for Logout data reporting
globalVerify=$TARGET_DIR/$GLOBAL_VERIFY	# csv file for Verify data reporting
sessions=$SESSIONS 						# number of contemporary login sent in a period
login=$LOGIN							# if Login action is required
verification=$VERIFICATION 				# if Verify action is required
logout=$LOGOUT 							# if Logout action is required
iteration=$ITERATION 					# nr of iteration to be performed for each user
verify_per_session=$VERIFY_PER_SESSION 					# nr of validate iteration to be performed for each user
iPlanetDirectoryPro=$IPLANETDIRECTORYPRO
delayLoginVerify=$LOGIN_VERIFY
delayVerifyVerify=$VERIFY_VERIFY        # delay between two different verify operations for the same session
delayVerifyLogout=$VERIFY_LOGOUT
reduceLog=$REDUCE_LOG
test_error_threshold=${TEST_ERROR_THRESHOLD}
test_error_file=${TEST_ERROR_FILE}
use_jwt=${USE_JWT}

#LOGIN
num_of_operation_login=$((${iteration}*${sessions}))
#num_of_max_error_operations_allowed_login=$((${num_of_operation_login}*${test_error_threshold}/100))

#VERIFY
num_of_operation_verify=$((${iteration}*${sessions}*${verify_per_session}))
#num_of_max_error_operations_allowed_verify=$((${num_of_operation_verify}*${test_error_threshold}/100))

#LOGOUT
num_of_operation_logout=$((${iteration}*${sessions}))
#num_of_max_error_operations_allowed_logout=$((${num_of_operation_logout}*${test_error_threshold}/100))



# default
INSTANCE=1 #default value for Instance; generally it is passed from sso_login_logout_parallel.sh file
maxDuration=5000 #max waiting time in msecs for the REST response after that the response is logged
USER=${ENM_ADMINISTRATOR_USERNAME}
PSWD=${ENM_ADMINISTRATOR_PWD}

# constants
login_s="Login"
logout_s="Logout"
verify_s="Verify"

# setup
loginarrayperfms=()
verifyarrayperfms=()
logoutarrayperfms=()
averageLogin=0
averageVerify=0
avegageLogout=0

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

echo "User: $user - -> $instance"
echo ""

# log files setup
if [ ! -d $TARGET_DIR ]; then
	mkdir -p $TARGET_DIR
fi
file="./$TARGET_DIR/${instance}-${user}_traces.txt" # from source "./system.sh"
if [ -f $file ]; then
	cp $file "$file-old"
	rm -f $file
fi
perflog="./$TARGET_DIR/${instance}-${user}_data.txt"
if [ -f $perflog ]; then
	cp $perflog "$perflog-old"
	rm -f $perflog
fi
samples="./$TARGET_DIR/${instance}-${user}_samples.csv" # from source "./system.sh"
if [ -f $samples ]; then
	cp $samples "$samples-old"
	rm -f $samples
fi

echo "User: $user - sessions: $sessions - Pswd: $pswd" >> $file
echo "Number of Iterations: $iteration" >> $file
echo "Number of LOGIN: ${num_of_operation_login}" >> $file
echo "Number of VERIFY: ${num_of_operation_verify}" >> $file
echo "Number of LOGOUT: ${num_of_operation_logout}" >> $file
echo "Error threshold: ${test_error_threshold} %" >> $file
echo "" >> $file
echo "System under test: ${HAPROXY_URL}" >> $file
echo "" >> $file
#testStart=$(echo $(($(date +%s%N)/1000000)))

echo "time,user,action,type,result,duration [msec]" > $samples

# Get average, min, max value of perf time data for login logout and verify operations 
getaverageminmax () {
	local arrname=$1[@]
    local array=("${!arrname}")
    #echo "array=${array[@]}"
    local arraylen=${#array[@]}
    #echo " $arraylen"
    local arraysum=0
    local max=${array[0]}
    local min=${array[0]}
    local local_num_of_operation_per_type=num_of_operation_per_type
    local local_num_of_max_error_operations_allowed_per_type=num_of_max_error_operations_allowed_per_type

    for arrayel in "${array[@]}"
    do
        arraysum=$(( arraysum + arrayel ))
        (( arrayel > max )) && max=$arrayel
        (( arrayel < min )) && min=$arrayel
    done
    local average=$(( arraysum / arraylen ))

    echo "$1 = ${array[@]}" >> $perflog
    echo "arrayname:$1; arraylen:$arraylen; arraysum:$arraysum; average:$average; min:$min;  max:$max;" >> $perflog
	
	file_csv=
	if [ $2 -eq 1 ]; then
		file_csv=${globalLogin}
		type_csv="LOGIN"
		local_num_of_operation_per_type=num_of_operation_login
		#local_num_of_max_error_operations_allowed_per_type=$((${local_num_of_operation_per_type}*${test_error_threshold}/100))
	elif [ $2 -eq 2 ]; then
		file_csv=${globalVerify}
		#local_num_of_operation_per_type=num_of_operation_per_type_with_multi_validation
        #local_num_of_max_error_operations_allowed_per_type=num_of_max_error_operations_allowed_per_type_valid_case
		type_csv="VERIFY"
		local_num_of_operation_per_type=num_of_operation_verify
		#local_num_of_max_error_operations_allowed_per_type=$((${local_num_of_operation_per_type}*${test_error_threshold}/100))
	elif [ $2 -eq 3 ]; then
		file_csv=${globalLogout}
		type_csv="LOGOUT"
		local_num_of_operation_per_type=num_of_operation_logout
		#local_num_of_max_error_operations_allowed_per_type=$((${local_num_of_operation_per_type}*${test_error_threshold}/100))
	fi

    local_num_of_max_error_operations_allowed_per_type=$((${local_num_of_operation_per_type}*${test_error_threshold}/100))
	min_allowed_successful_operations=$((${local_num_of_operation_per_type}-${local_num_of_max_error_operations_allowed_per_type}))
	
	# ${arraylen} counts successful attempts
	result="NOT PASSED"
	if [ "${arraylen}" -lt "${min_allowed_successful_operations}" ]; then
		echo "Test for ${type_csv} is ${result}, since ${arraylen} < ${min_allowed_successful_operations} [min allowed successful operations]" >> ${file}
		echo "Touching error flag file ${test_error_file}" >> ${file}
		touch ${test_error_file}
	else
		result="PASSED"
		echo "Test for ${type_csv} is ${result}, since ${arraylen} >= ${min_allowed_successful_operations} [min allowed successful operations]" >> ${file}
	fi
	echo "${instance}-${user};$min;$average;$max;$arraylen;${result}" >> ${file_csv}

}

# Report excessive duration of Login, Verify or Logout. Threshold set to 5000 msces
checkDuration() {
	#maxDuration=5000 #max waiting time in seconds for the REST response after that the response is logged
	if [ "$1" -ge $maxDuration ]; then
		echo "`date` : "$2" n. ${c} curl took more than $maxDuration msecs !! - "$1" msecs" >> $file
	fi
}
starttest=`date`
echo "START test at ${starttest}" >> $file
echo "" >> $file
# for each iteration
for (( i=1;i<=$iteration;i++ ))
do
	echo "Iteration - User: ${instance} - iteration: ${i}"
	sesfolder="./$TARGET_DIR/Cookies" 	#$iteration "./$TARGET_DIR/UserNr${instance}/Iteration${i}"
	#if [ -d $sesfolder ]; then 
	#	rm -rf $sesfolder
	#fi
	mkdir -p $sesfolder

# for each session for a single user - conditionally run on the basis of system.sh config
	for (( c=1; c<=${sessions}; c++ ))
	do
		if $login; then 
			usedCookie="cookie-${instance}-${i}-${c}.txt"
			loginstart=$(echo $(($(date +%s%N)/1000000)))
				echo "Cookie =  $sesfolder/${usedCookie}" >> ${file}
			logintime=$(echo $(date '+%F %T.%3N'))
			result=$(login ${user} ${pswd} $sesfolder/${usedCookie} ${file} ${use_jwt})
			echo "Result =  ${result}"
			
			w=$((${#result}-1))
			result2=${result:$w:1}
			#echo "Result2 = ${result2}"
			#echo "Result2 = ${result2}" >> ${file}
			loginend=$(echo $(($(date +%s%N)/1000000)))
			loginduration=$(( loginend - loginstart ))
            if [ ${result2} -eq 0 ]; then
                loginarrayperfms+=($loginduration)
				echo "- login: OK : duration: $loginduration" >> $file
				echo "$logintime,$user,LOGIN,login,OK,$loginduration" >> $samples
            else
                echo "- login: NOT OK - Invalid Login" >> $file
				echo "$logintime,$user,LOGIN,login,FAILED,0" >> $samples
            fi

			#checkDuration $loginduration login_s
		fi
	done
	
	if $verification; then
	  sleep ${delayLoginVerify}
	fi
	
# for each session for a single user - conditionally run on the basis of system.sh config
	for (( c=1; c<=${sessions}; c++ ))
	do
		if $verification; then
# for verify_per_session times repeats the nested session validation loop 
	    for (( v=1; v<=verify_per_session; v++ ))
          do		
		    usedCookie="cookie-${instance}-${i}-${c}"
		    echo "VERIFY - Used Cookie : ${usedCookie}" >> $file
		    echo "- - Verify: ${user} - `date` - iteration: ${i} - session: ${c} - verification: ${v}" >> $file
		    ls -la $sesfolder/${usedCookie}.txt > /dev/null
		    if [ $? -eq 0 ]; then
		  	  cat $sesfolder/${usedCookie}.txt | grep ${IPLANETDIRECTORYPRO} > /dev/null
			  if [ $? -eq 0 ]; then
				verifyCookieRotary $sesfolder/${usedCookie}.txt ${i} ${SESSION_ISVALID} false ${file} ${samples} ${user}
			  else
				echo "`date` : NOT OK - ERROR: No ${IPLANETDIRECTORYPRO} found"  >> $file
			  fi
		    else
			  echo "`date` - NOT OK - ERROR: No cookie found"  >> $file
			  echo -n "HTTP Status: " >> $file
			  echo "$req_cmd" | grep HTTP | awk '{print $2}' >> $file
		    fi
			
		  #checkDuration $verifyduration verify_s
		  sleep ${delayVerifyVerify}
	      done
	    fi
    done
	
	if $logout; then
	  sleep ${delayVerifyLogout}
    fi
	
# for each session for a single user - conditionally run on the basis of system.sh config
	for (( c=1; c<=${sessions}; c++ ))
	do
		if $logout; then
			usedCookie="cookie-${instance}-${i}-${c}"
			logoutstart=$(echo $(($(date +%s%N)/1000000)))
			logouttime=$(echo $(date '+%F %T.%3N'))
			result=$(logout ${user} $sesfolder/${usedCookie}.txt ${file})
			logoutend=$(echo $(($(date +%s%N)/1000000)))
			logoutduration=$(( logoutend - logoutstart ))
			if [ $result -eq 0 ]; then
				echo "- - - Logout: OK - duration: $logoutduration" >> $file
				echo "$logouttime,$user,LOGOUT,logout,OK,$loginduration" >> $samples
			        logoutarrayperfms+=($logoutduration)
			else
				echo "- - - Logout: NOT OK - duration: $logoutduration" >> $file
				echo "$logouttime,$user,LOGOUT,logout,FAILED,0" >> $samples
			fi
            rm -rf $sesfolder/${usedCookie}.txt
			
			#checkDuration $logoutduration logout_s
		fi
	done
echo "" >> $file
echo "" >> $file
done

echo -e "\n- - -\nTEST for user $user\n" 

# average computations 

#echo "loginarrayperfms=${loginarrayperfms[@]}"
if $login; then
	getaverageminmax loginarrayperfms 1
fi

if $verification; then
#echo "verifyarrayperfms=${verifyarrayperfms[@]}"
	getaverageminmax verifyarrayperfms 2
fi

if $logout; then
#echo "logoutarrayperfms=${logoutarrayperfms[@]}"
	getaverageminmax logoutarrayperfms 3
fi

#testStop=$(echo $(($(date +%s%N)/1000000)))
endtest=`date`
echo "FINISH test at ${endtest}" >> $file
echo " - duration:" >> $file
echo " - - START: ${starttest}" >> $file
echo " - -   END: ${endtest}" >> $file
echo -e "TEST for user $user - finished"
