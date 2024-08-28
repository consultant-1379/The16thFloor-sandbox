#!/bin/bash

# THIS SCRIPT TO BE RUN ON SVC-X SERVICE JUST EMULATE THE BEHAVIOR DURING UPGRADE
# SETTING OFFLINE/ONLINE EACH INSTANCE OF SPECIFIED SERVICE,
# EXECUTING VIRSH UNDEFINE FOR EACH SERVICE
# WAITING FOR EACH INSTANCE TO BE BACK ONLINE BEFORE PROCEEDING WITH THE NEXT ONE
my_version=3.0.0
my_command=$(basename $0)
my_isOnCloud=false

#HAPROXY
HAPROXY_URL=`cat /ericsson/tor/data/global.properties | grep UI_PRES_SERVER | cut -d= -f2` # to be used when run in MS-1


# The service to be handled
my_service=sso
CURR_DIR=`pwd`
file=${CURR_DIR}/${my_service}_svc_restart.log

# The mode to use. UPGRADE is currently the only one supported
my_mode=UPGRADE

# Once online performed, timeout in seconds to wait before proceeding with next offline on the other service instance
my_timeout_online_offline=30

# Once offline performed, timeout to wait before proceeding with next online on the same offlined service instance
my_timeout_offline_online=40

# Once offline performed, timeout to wait before executing virsh undefine
my_virsh_undefine_timeout=150

# Flag to indicate whenever use random/incremental timeout during tests
my_use_random_incremental_timeout=false

# Optional Timeout, in seconds, used for adding delay/desync per each iteration of the INITIAL_INSTALL and UPGRADE test when offlining one instance
my_sleepTimeForDesyncOffline=20

# Optional max number of iterations to be used for incrementing/using a random delay of the INITIAL_INSTALL and UPGRADE test when offlining one instance
my_max_iteration_for_random_delay=15

# Current iteration of test
current_iteration=0

#25 minutes max timeout
max_starting_timeout=1500

sleeping_timeout=5

stop_file=/tmp/stop_update_sso.stop

isPkillExecutedOnSvcA=false
isPkillExecutedOnSvcB=false

# To be present on EMP
keyFile=/tmp/KEY.pem

IPLANETDIRECTORYPRO="iPlanetDirectoryPro"
SSO_INSTANCE1=sso-instance-1
SSO_INSTANCE2=sso-instance-2

# Test users
user_administrator=administrator
user_administrator_pwd=TestPassw0rd

user_remote_testing=false
user_remote=PerfTest33
user_remote_pwd=RemPassw0rd

hostname=`hostname`

# Removing log file
rm -f ${file}

# Check if on cloud
consul members | grep sso > /dev/null
if [ $? -eq 0 ]; then
  my_isOnCloud=true
  echo "On cloud :) " >> ${file}
else
  echo "On physical :) " >> ${file}
fi


if [ ${my_isOnCloud} = true ]; then
  svcA=`consul members| grep ${my_service} | awk 'NR==1{print $1}'`
  svcB=`consul members| grep ${my_service} | awk 'NR==2{print $1}'`
else
  serviceGroupA=`hagrp -state | grep ${my_service} | awk 'NR==1{print $1}'`
  serviceGroupB=`hagrp -state | grep ${my_service} | awk 'NR==2{print $1}'`

  echo "serviceGroupA: ${serviceGroupA}" >> ${file}
  echo "serviceGroupB: ${serviceGroupB}" >> ${file}
  svcA=`hagrp -state | grep ${my_service} | awk 'NR==1{print $3}'`
  svcB=`hagrp -state | grep ${my_service} | awk 'NR==2{print $3}'`
fi

serviceToOnline=${svcA}

echo "SvcA: ${svcA}" >> ${file}
echo "SvcB: ${svcB}" >> ${file}



version() {
cat << EOF

`basename $0` $my_version

EOF
}

usage() {
cat << EOF

Usage: `basename $0` [<OPTIONS>]
where:
  <OPTIONS>:
    -h, --help                                This help
    --version                                 The script version
    -s=SERVICE, --service=SERVICE             The service under test
                                              [Default ${my_service}]
    -m=MODE, --mode=MODE                      The mode tobe used
                                              Supported value: INITIAL_INSTALL | UPGRADE
                                              Default [${my_mode}]
    --timeout_online_offline=X                Once a service becomes online, this is the timeout of X seconds to wait before
                                              proceeding with next offline on the other service instance
                                              [Default ${my_timeout_online_offline} sec]
    --timeout_offline_online=X                Once a service becomes offline, this is the timeout of X seconds to wait before
                                              proceeding with next online on the same offlined service instance
                                              [Default ${my_timeout_offline_online} sec]
    -e, --examples                            Show examples


The script will execute emulation of INITIAL_INSTALL or UPGRADE for a service.
If executed on PHYSICAL/VAPP, please put the script into SVC-X hosting the instance of target sso.
If executed on CLOUD, please put the script into LAF.

EOF
}

examples() {
cat << EOF

Examples:

Execute UPGRADE emulator with default timeout
./${my_command} --mode=UPGRADE


EOF
}

error() {
cat << EOF

Try './${my_command} --help' for more information.

EOF
}

# Cleanstart check on vcs engineA
checkCleanstart() {

  #Check il /var/VRTSvcs/log/engine_A.log dal svc e verifica se non trovi errori del tipo...

  ERROR.*clean.*_sso
  oppure
  ERROR.*clean.*_httpd
}


# MonitorOffline check on vcs engineA
checkMonitorOffline() {

  #Check il /var/VRTSvcs/log/engine_A.log dal svc e verifica se non trovi errori del tipo...

  "_httpd) has reported unexpected OFFLINE.* times"
  "_sso) has reported unexpected OFFLINE.* times"
}





# Parse parameters

while [ "$1" != "" ] ; do
    case $1 in
        -h | --help )
            usage
            exit 0
            ;;
        --version )
            version
            exit 0
            ;;
        -s=* | --service=* )
            my_service=$1
            my_service=${my_service#--service=}
            my_service=${my_service#-s=}
            ;;
        -m=* | --mode=* )
            my_mode=$1
            my_mode=${my_mode#--mode=}
            my_mode=${my_mode#-m=}
            ;;
        --timeout_online_offline=* )
            my_timeout_online_offline=$1
            my_timeout_online_offline=${my_timeout_online_offline#--timeout_online_offline=}
            ;;
        --timeout_offline_online=* )
            my_timeout_offline_online=$1
            my_timeout_offline_online=${my_timeout_offline_online#--timeout_offline_online=}
            ;;
        -* )
            echo
            echo $1: unknown option
            error
            exit 1
            ;;
#        * )
#            case $param_index in
#                * )
#                    my_nes=$1
#                    MY_NES_ARRAY+=($my_nes)
#                    param_index=$(($param_index + 1))
#                    ;;
#            esac
#            ;;
    esac
    shift
done

echo "Value for my_service is ${my_service}" >> ${file}
echo "Value for my_mode is ${my_mode}" >> ${file}
echo "Value for my_timeout_online_offline is ${my_timeout_online_offline}" >> ${file}
echo "Value for my_timeout_offline_online is ${my_timeout_offline_online}" >> ${file}
echo "Value for my_virsh_undefine_timeout is ${my_virsh_undefine_timeout}" >> ${file}
echo "Value for my_use_random_incremental_timeout is ${my_use_random_incremental_timeout}" >> ${file}
echo "Value for my_sleepTimeForDesyncOffline is ${my_sleepTimeForDesyncOffline}" >> ${file}

# Perform virsh undefine
perform_virsh_undefine() {

  serviceOnline=$1
  echo "Hostname: ${hostname}, service to set online ${serviceOnline}"
  if [ ${serviceOnline} == ${hostname} ]; then
      check_stop_condition
      echo "I can virsh undefine ${my_service} locally on this host ${hostname}" >> ${file}
      virsh undefine ${my_service}
  else
      echo "I will virsh undefine ${my_service} on remote host ${serviceOnline}" >> ${file}

	  which expect
	  if [ $? -ne 0 ]; then
        echo "expect not detected, installing it" >> ${file}
	    yum -y install expect
        if [ $? -ne 0 ]; then
        	echo "expect installation failed. Abort" >> ${file}
        	exit 1
        fi
      else
      	echo "expect has been detected, no need to install it." >> ${file}
      fi
      which sshpass
      if [ $? -ne 0 ]; then
        echo "sshpass not detected, installing it" >> ${file}
        wget https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm
        sudo rpm -Uvh epel-release-latest-7.noarch.rpm
        yum -y install sshpass
#		yum -y install --noplugins sshpass
        if [ $? -ne 0 ]; then
        	echo "sshpass installation failed. Abort" >> ${file}
        	exit 1
        fi        
      else
      	echo "sshpass has been detected, no need to install it." >> ${file}
      fi
      check_stop_condition
      sshpass -p 12shroot ssh -tt ${serviceOnline} -o StrictHostKeyChecking=no -o CheckHostIP=no -l litp-admin /tmp/suandrun.sh /tmp/virshundefine.sh root 12shroot
      if [ $? -eq 0 ]; then
      	echo "SSH pass - Remote virsh undefine completed" >> ${file}
      else
      	echo "ERROR SSH pass - Remote virsh undefine completed. Abort" >> ${file}
      	exit 1
      fi
  fi
  sleep 2
}


# Manage ENM on physical env
manage_env_physical() {
  stateA=`hagrp -state | grep ${my_service} | awk 'NR==1{print $4}'`
  stateB=`hagrp -state | grep ${my_service} | awk 'NR==2{print $4}'`

  echo "Status: ${my_service} on ${svcA} is ${stateA}, ${my_service} on ${svcB} is ${stateB}" >> ${file}
  if [ ${my_mode} == "UPGRADE" ]; then
     echo "UPGRADE mode is on" >> ${file}

      if [[ ${stateA} == *"STARTING"* ]] || [[ ${stateB} == *"STARTING"* ]]; then
          echo "`date` Detected starting condition"
		  
          echo "Login as administrator" >> ${file}
          result=$(login ${user_administrator} ${user_administrator_pwd})
          echo "value $result" >> ${file}
		  if [ ${result} -eq 0 ]; then
            echo "`date` Administrator LOGIN TEST PASSED" >> ${file}
          else
            echo "`date` Administrator LOGIN TEST FAILED" >> ${file}
            #exit 1
          fi
          
		  if [ user_remote_testing = true ];then 
			  echo "Login as remote user ${user_remote}" >> ${file}
			  result2=$(login ${user_remote} ${user_remote_pwd})
			  echo "value $result2" >> ${file}
			  if [ ${result2} -eq 0 ]; then
				echo "`date` ${user_remote} LOGIN TEST PASSED" >> ${file}
			  else
				echo "`date` ${user_remote} LOGIN TEST FAILED" >> ${file}
				#exit 1
			  fi
		  fi

      elif [[ ${stateA} == *"STOPPING"* ]] || [[ ${stateB} == *"STOPPING"* ]]; then
        echo "`date` Detected stopping condition"
		  
		echo "Login as administrator" >> ${file}
        result=$(login ${user_administrator} ${user_administrator_pwd})
        echo "value $result" >> ${file}
		if [ ${result} -eq 0 ]; then
			echo "`date` Administrator LOGIN TEST PASSED" >> ${file}
		else
			echo "`date` Administrator LOGIN TEST FAILED" >> ${file}
			#exit 1
		fi
          
		if [ user_remote_testing = true ];then 
		  echo "Login as remote user ${user_remote}" >> ${file}
		  result2=$(login ${user_remote} ${user_remote_pwd})
		  echo "value $result2" >> ${file}
		  if [ ${result2} -eq 0 ]; then
			echo "`date` ${user_remote} LOGIN TEST PASSED" >> ${file}
		  else
			echo "`date` ${user_remote} LOGIN TEST FAILED" >> ${file}
			#exit 1
		  fi
		fi  
		
      else
        current_iteration=$((current_iteration+1))
        echo "`date` Iteration ${current_iteration} started" >> ${file}

        if [ "${my_use_random_incremental_timeout}" = true ]; then
          sleepIterationIndex=$((current_iteration-1))
          echo "Random incremental timeout is active, sleepIterationIndex is ${sleepIterationIndex}, current_iteration is ${current_iteration}" >> ${file}
          if [ ${current_iteration} -eq ${my_max_iteration_for_random_delay} ]; then
            echo "${my_max_iteration_for_random_delay} iterations reached. Resetting current_iteration" >> ${file}
            current_iteration=0
          fi
          sleepTime=$((my_timeout_online_offline+sleepIterationIndex*my_sleepTimeForDesyncOffline))
          echo "Incremementing time to wait before offline to ${sleepTime}" >> ${file}
        else
          sleepTime=${my_timeout_online_offline}
        fi

        if [ ${stateA} == "|ONLINE|" ] && [ ${stateB} == "|ONLINE|" ]; then
          echo "`date` Status: ${my_service} on ${svcA} is ${stateA}, ${my_service} on ${svcB} is ${stateB}" >> ${file}

          echo "Login as administrator" >> ${file}
          result=$(login ${user_administrator} ${user_administrator_pwd})
          echo "value $result" >> ${file}
		  echo "Login as administrator to instance $SSO_INSTANCE1" >> ${file}
          result3=$(login_instance ${user_administrator} ${user_administrator_pwd} $SSO_INSTANCE1)
          echo "value $result3" >> ${file}
          echo "Login as administrator to instance $SSO_INSTANCE2" >> ${file}
          result4=$(login_instance ${user_administrator} ${user_administrator_pwd} $SSO_INSTANCE2)
          echo "value $result4" >> ${file}
		  
		  if [ ${result} -eq 0 ] && [ ${result3} -eq 0 ] && [ ${result4} -eq 0 ]; then
            echo "`date` administrator LOGIN TEST PASSED" >> ${file}
          else
            echo "`date` administrator LOGIN TEST FAILED" >> ${file}
            #exit 1
          fi
		  
		  if [ user_remote_testing = true ];then 
			  echo "Login as remote user ${user_remote}" >> ${file}
			  result2=$(login ${user_remote} ${user_remote_pwd})
			  echo "value $result2" >> ${file}
			  echo "Login as remote user ${user_remote} to instance $SSO_INSTANCE1" >> ${file}
			  result5=$(login_instance ${user_remote} ${user_remote_pwd} $SSO_INSTANCE1)
			  echo "value $result5" >> ${file}
			  echo "Login as remote user ${user_remote} to instance $SSO_INSTANCE2" >> ${file}
			  result6=$(login_instance ${user_remote} ${user_remote_pwd} $SSO_INSTANCE2)
			  echo "value $result6" >> ${file}
			  
			  if [ ${result2} -eq 0 ] && [ ${result5} -eq 0 ] && [ ${result6} -eq 0 ]; then
				echo "`date` ${user_remote} LOGIN TEST PASSED" >> ${file}
			  else
				echo "`date` ${user_remote} LOGIN TEST FAILED" >> ${file}
				#exit 1
			  fi
		  fi
		  
          if [ ${current_iteration} -ge 2 ]; then
              duration=$SECONDS
              echo "Online procedure completed in approx. $(($duration / 60)) min $(($duration % 60)) sec" >> ${file}
              if [ ${duration} -gt $((${max_starting_timeout} + ${sleeping_timeout})) ]; then
                  echo "# # # DETECTED POSSIBLE TIMEOUT ISSUE, STARTUP PHASE TOOK $(($duration / 60)) min $(($duration % 60)) sec TO COMPLETE # # #" >> ${file}
              fi

              echo "Sleeping for ${sleepTime} s before proceeding with next offline" >> ${file}
              sleep ${sleepTime}
          fi
          if [ ${serviceToOnline} == ${svcA} ]; then
            check_stop_condition
            echo "`date` Offlining ${serviceGroupA} on ${svcA}" >> ${file}
            hagrp -offline ${serviceGroupA} -sys ${svcA}
          elif [ ${serviceToOnline} == ${svcB} ]; then
            check_stop_condition
            echo "`date` Offlining ${serviceGroupB} on ${svcB}" >> ${file}
            hagrp -offline ${serviceGroupB} -sys ${svcB}
          fi

        elif [ ${stateA} == "|ONLINE|" ] && [ ${stateB} == "|OFFLINE|" ]; then
			echo "Login as administrator" >> ${file}
			result=$(login ${user_administrator} ${user_administrator_pwd})
			echo "value $result" >> ${file}
			if [ ${result} -eq 0 ]; then
				echo "`date` Administrator LOGIN TEST PASSED" >> ${file}
			else
				echo "`date` Administrator LOGIN TEST FAILED" >> ${file}
				#exit 1
			fi
          
			if [ user_remote_testing = true ];then 
				echo "Login as remote user ${user_remote}" >> ${file}
				result2=$(login ${user_remote} ${user_remote_pwd})
				echo "value $result2" >> ${file}
				if [ ${result2} -eq 0 ]; then
					echo "`date` ${user_remote} LOGIN TEST PASSED" >> ${file}
				else
					echo "`date` ${user_remote} LOGIN TEST FAILED" >> ${file}
					#exit 1
				fi
			fi  
	
          serviceToOnline=${svcB}
          perform_virsh_undefine ${serviceToOnline}
          echo "ONLINE/OFFLINE "
          echo "Sleeping for ${my_timeout_offline_online} sec before proceeding with online command" >> ${file}
          sleep ${my_timeout_offline_online}
          echo "`date` Onlining ${serviceGroupB} on ${svcB}" >> ${file}
          check_stop_condition
          hagrp -online ${serviceGroupB} -sys ${svcB}
          SECONDS=0
          serviceToOnline=${svcA}
          echo "Next service to be set online: ${serviceToOnline}"


        elif [ ${stateA} == "|OFFLINE|" ] && [ ${stateB} == "|ONLINE|" ]; then
			echo "Login as administrator" >> ${file}
			result=$(login ${user_administrator} ${user_administrator_pwd})
			echo "value $result" >> ${file}
			if [ ${result} -eq 0 ]; then
				echo "`date` Administrator LOGIN TEST PASSED" >> ${file}
			else
				echo "`date` Administrator LOGIN TEST FAILED" >> ${file}
				#exit 1
			fi
          
			if [ user_remote_testing = true ];then 
				echo "Login as remote user ${user_remote}" >> ${file}
				result2=$(login ${user_remote} ${user_remote_pwd})
				echo "value $result2" >> ${file}
				if [ ${result2} -eq 0 ]; then
					echo "`date` ${user_remote} LOGIN TEST PASSED" >> ${file}
				else
					echo "`date` ${user_remote} LOGIN TEST FAILED" >> ${file}
					#exit 1
				fi
			fi

          serviceToOnline=${svcA}
          perform_virsh_undefine ${serviceToOnline}
          echo "OFFLINE/ONLINE"
          echo "Sleeping for ${my_timeout_offline_online} sec before proceeding with online command" >> ${file}
          sleep ${my_timeout_offline_online}
          echo "`date` Onlining ${serviceGroupA} on ${svcA}" >> ${file}
          check_stop_condition
          hagrp -online ${serviceGroupA} -sys ${svcA}
          SECONDS=0
          serviceToOnline=${svcB}
          echo "Next service to be set online: ${serviceToOnline}" >> ${file}


        elif [ ${stateA} == "|OFFLINE|" ] && [ ${stateB} == "|OFFLINE|" ]; then
            echo "Both ${my_service} are OFFLINE...I will exit with error" >> ${file}
            exit 1
        fi

      fi

  elif [ ${my_mode} == "INITIAL_INSTALL" ]; then
    echo "INITIAL_INSTALL mode is on" >> ${file}
      if [[ ${stateA} == *"STARTING"* ]] || [[ ${stateB} == *"STARTING"* ]]; then
        echo "`date` Detected starting condition"
      elif [[ ${stateA} == *"STOPPING"* ]] || [[ ${stateB} == *"STOPPING"* ]]; then
        echo "`date` Detected stopping condition"
      else
        if [ ${stateA} == "|ONLINE|" ] && [ ${stateB} == "|ONLINE|" ]; then

          echo "Sleeping for ${my_timeout_online_offline} s before proceeding with next offline" >> ${file}
          sleep ${my_timeout_online_offline}

          #check_stop_condition
          echo "`date` Offlining ${serviceGroupA} on ${svcA}" >> ${file}
          hagrp -offline ${serviceGroupA} -sys ${svcA}

          current_iteration=$((current_iteration+1))
          echo "`date` Iteration ${current_iteration} started" >> ${file}

          if [ "${my_use_random_incremental_timeout}" = true ];then
            sleepIterationIndex=$((current_iteration-1))
            if [ ${current_iteration} -eq ${my_max_iteration_for_random_delay} ]; then
              echo "${my_max_iteration_for_random_delay} iterations reached. Resetting current_iteration" >> ${file}
              current_iteration=0
            fi
            currentSleepTimeout=$((sleepIterationIndex*my_sleepTimeForDesyncOffline))
            echo "Sleeping for additional ${currentSleepTimeout} before offlining ${serviceGroupB} on ${svcB}" >> ${file}
            sleep ${currentSleepTimeout}
          fi

          echo "`date` Offlining ${serviceGroupB} on ${svcB}" >> ${file}
          hagrp -offline ${serviceGroupB} -sys ${svcB}

          echo "Sleeping for ${my_virsh_undefine_timeout} sec before perform virsh undefine command" >> ${file}
          sleep ${my_virsh_undefine_timeout}

          echo "`date` I virsh undefine ${my_service} on both services" >> ${file}
          virsh undefine ${my_service}

          which sshpass
          if [ $? -ne 0 ]; then
            echo "sshpass not detected" >> ${file}
            echo "Installing sshpass..." >> ${file}
            wget https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm
            sudo rpm -Uvh epel-release-latest-7.noarch.rpm
            yum -y install sshpass
#			yum -y install --noplugins sshpass
          fi

          otherServiceToOffline=${svcB}
          if [ ${svcB} == ${hostname} ]; then
            otherServiceToOffline=${svcA}
          fi
          echo "Executing remote command to virsh undefine ${my_service} on ${otherServiceToOffline}"
          sshpass -p 12shroot ssh -tt ${otherServiceToOffline} -o StrictHostKeyChecking=no -o CheckHostIP=no -l litp-admin /tmp/suandrun.sh /tmp/virshundefine.sh root 12shroot

        elif [ ${stateA} == "|OFFLINE|" ] && [ ${stateB} == "|OFFLINE|" ]; then
          echo "`date` Iteration ${current_iteration} started"
          echo "`date` Onlining any ${serviceGroupA}" >> ${file}
          hagrp -online ${serviceGroupA} -any
        fi
      fi
  else
    echo "Unknown mode detected: ${my_mode}" >> ${file}
    exit 1
  fi
}


# Login via HAPROXY
login() {
  user=$1
  pwd=$2
  cookie=${CURR_DIR}/mycookie.txt
  echo "`date` Logging via HAPROXY in as user ${user}, pwd ${pwd} using cookie file ${cookie}" >> $file
  rm -f ${cookie}

  r=$RANDOM

  if [ $((r % 2)) != 0 ]; then
    curl -s --insecure --request POST --cookie-jar ${cookie} "https://${HAPROXY_URL}/login?IDToken1=${user}&IDToken2=${pwd}" > /dev/null
    loginSequenceMessage=" -> IDToken1=${user}&IDToken2=${pwd} sequence"
  else
    curl -s --insecure --request POST --cookie-jar ${cookie} "https://${HAPROXY_URL}/login?IDToken2=${pwd}&IDToken1=${user}" > /dev/null
    loginSequenceMessage=" -> IDToken2=${pwd}&IDToken1=${user} sequence"
  fi

  result=1
  cat ${cookie} | grep ${IPLANETDIRECTORYPRO} > /dev/null
  result=$?

  if [ ${result} -eq 0 ]; then
    echo "`date` Success login via HAPROXY for user: ${user} pwd: ${pwd}" >> $file
    curl --insecure --output /dev/null -s -L --request GET --cookie ${cookie} "https://${HAPROXY_URL}/logout" > /dev/null
  else
    echo "`date` Error login via HAPROXY for user: ${user} pwd: ${pwd}" >> $file
    echo ${loginSequenceMessage} >> $file
  fi
  echo $result
}


# Login via specific SSO instance
login_instance() {
  user=$1
  pwd=$2
  instance=$3
  cookie=${CURR_DIR}/mycookie_instance.txt
  echo "`date` Logging via SSO instance ${instance} in as user ${user}, pwd ${pwd} using cookie file ${cookie}" >> $file
  rm -f ${cookie}

  r=$RANDOM

  if [ $((r % 2)) != 0 ]; then
    curl -s --insecure --request POST --cookie-jar ${cookie} "https://${instance}:8443/singlesignon/2.0/login?IDToken1=${user}&IDToken2=${pwd}" > /dev/null
    loginSequenceMessage=" -> IDToken1=${user}&IDToken2=${pwd} sequence"
  else
    curl -s --insecure --request POST --cookie-jar ${cookie} "https://${instance}:8443/singlesignon/2.0/login?IDToken2=${pwd}&IDToken1=${user}" > /dev/null
    loginSequenceMessage=" -> IDToken2=${pwd}&IDToken1=${user} sequence"
  fi

  result=1
  cat ${cookie} | grep ${IPLANETDIRECTORYPRO} > /dev/null
  result=$?

  if [ ${result} -eq 0 ]; then
    echo "`date` Success login via specific SSO instance ${instance} for user: ${user} pwd: ${pwd}" >> $file
    curl --insecure --output /dev/null -s -L --request GET --cookie ${cookie} "https://${HAPROXY_URL}/logout" > /dev/null
  else
    echo "`date` Error login via specific SSO instance ${instance} for user: ${user} pwd: ${pwd}" >> $file
    echo ${loginSequenceMessage} >> $file
  fi

  echo $result

}

# Manage ENM on virtual env
manage_env_cloud() {

  if [ ! -f "${keyFile}" ]; then
    echo "ERROR. Key file ${keyFile} does not exist. Exiting." >> ${file}
    exit 1
  fi

  consulStateA=`consul members| grep ${my_service} | awk 'NR==1{print $3}'`
  consulStateB=`consul members| grep ${my_service} | awk 'NR==2{print $3}'`

  if [ ${my_mode} == "UPGRADE" ]; then

    echo "`date` UPGRADE mode is on" >> ${file}
    echo "Status: ${my_service} on ${svcA} is ${consulStateA}, ${my_service} on ${svcB} is ${consulStateB}" >> ${file}

    if [ ${consulStateA} == "alive" ] && [ ${consulStateB} == "alive" ]; then
      #Both instances are alive, but need to check existence of file 'service.running' on each instace
      echo "`date`Both ${my_service} instances are alive" >> ${file}

      fileExistsOnSvcA=1
      fileExistsOnSvcB=1
      if [ ${isPkillExecutedOnSvcA} = false ]; then
        ssh -i ${keyFile} -o StrictHostKeyChecking=no cloud-user@${svcA} 'ls /ericsson/simple_availability_manager_agents/service.running'
        fileExistsOnSvcA=`echo $?`
        echo "Eval fileExistsOnSvcA as ${fileExistsOnSvcA} on ${svcA}" >> ${file}
      fi

      if [ ${isPkillExecutedOnSvcB} = false ]; then
        ssh -i ${keyFile} -o StrictHostKeyChecking=no cloud-user@${svcB} 'ls /ericsson/simple_availability_manager_agents/service.running'
        fileExistsOnSvcB=`echo $?`
        echo "Eval fileExistsOnSvcB as ${fileExistsOnSvcB} on ${svcB}" >> ${file}
      fi

      current_iteration=$((current_iteration+1))
      echo "`date` Iteration ${current_iteration} started" >> ${file}

      echo "`date` fileExistsOnSvcA is ${fileExistsOnSvcA}, fileExistsOnSvcB is ${fileExistsOnSvcB}" >> ${file}
      if [ ${fileExistsOnSvcA} -eq 0 ] && [ ${fileExistsOnSvcB} -eq 0 ]; then

        if [ "${my_use_random_incremental_timeout}" = true ];then
          sleepIterationIndex=$((current_iteration-1))
          if [ ${current_iteration} -eq ${my_max_iteration_for_random_delay} ]; then
            echo "${my_max_iteration_for_random_delay} iterations reached. Resetting current_iteration" >> ${file}
            current_iteration=0
          fi
          sleepTime=$((my_timeout_online_offline+sleepIterationIndex*my_sleepTimeForDesyncOffline))
          echo "Incremementing time to wait before offline to ${sleepTime}" >> ${file}
        else
          sleepTime=${my_timeout_online_offline}
        fi


		echo "Login as administrator" >> ${file}
        result=$(login ${user_administrator} ${user_administrator_pwd})
        echo "value $result" >> ${file}
	    echo "Login as administrator to instance $SSO_INSTANCE1" >> ${file}
        result3=$(login_instance ${user_administrator} ${user_administrator_pwd} $SSO_INSTANCE1)
        echo "value $result3" >> ${file}
        echo "Login as administrator to instance $SSO_INSTANCE2" >> ${file}
        result4=$(login_instance ${user_administrator} ${user_administrator_pwd} $SSO_INSTANCE2)
        echo "value $result4" >> ${file}
		  
	    if [ ${result} -eq 0 ] && [ ${result3} -eq 0 ] && [ ${result4} -eq 0 ]; then
            echo "`date` administrator LOGIN TEST PASSED" >> ${file}
        else
            echo "`date` administrator LOGIN TEST FAILED" >> ${file}
            #exit 1
        fi
		  
		if [ user_remote_testing = true ];then 
		  echo "Login as remote user ${user_remote}" >> ${file}
		  result2=$(login ${user_remote} ${user_remote_pwd})
		  echo "value $result2" >> ${file}
		  echo "Login as remote user ${user_remote} to instance $SSO_INSTANCE1" >> ${file}
		  result5=$(login_instance ${user_remote} ${user_remote_pwd} $SSO_INSTANCE1)
		  echo "value $result5" >> ${file}
		  echo "Login as remote user ${user_remote} to instance $SSO_INSTANCE2" >> ${file}
		  result6=$(login_instance ${user_remote} ${user_remote_pwd} $SSO_INSTANCE2)
		  echo "value $result6" >> ${file}
		  
		  if [ ${result2} -eq 0 ] && [ ${result5} -eq 0 ] && [ ${result6} -eq 0 ]; then
			echo "`date` ${user_remote} LOGIN TEST PASSED" >> ${file}
		  else
			echo "`date` ${user_remote} LOGIN TEST FAILED" >> ${file}
			#exit 1
		  fi
		fi


        if [ ${current_iteration} -ge 2 ]; then
          duration=$SECONDS
          echo "`date` Online procedure completed in approx. $(($duration / 60)) min $(($duration % 60)) sec" >> ${file}
          if [ ${duration} -gt $((${max_starting_timeout} + ${sleeping_timeout})) ]; then
              echo "# # # DETECTED POSSIBLE TIMEOUT ISSUE, STARTUP PHASE TOOK $(($duration / 60)) min $(($duration % 60)) sec TO COMPLETE # # #" >> ${file}
          fi

          echo "`date` Sleeping for ${sleepTime} s before proceeding" >> ${file}
          isPkillExecutedOnSvcA=false
          isPkillExecutedOnSvcB=false
          sleep ${sleepTime}
        fi

        if [ ${serviceToOnline} == ${svcA} ]; then
          echo "`date` Killing service on ${svcA}" >> ${file}
          ssh -i ${keyFile} -o StrictHostKeyChecking=no cloud-user@${svcA} 'sudo /usr/lib/ocf/pre_shutdown/shutdown_sso.bsh &'
          #ssh -i ${keyFile} -o StrictHostKeyChecking=no cloud-user@${svcA} 'sudo pkill consul'
          if [ $? -ne 0 ]; then
              echo "ERROR when killing service on ${serviceToOnline}. Exiting" >> ${file}
              exit 1
          else
              SECONDS=0
              isPkillExecutedOnSvcA=true
              echo "`date` Pkilled service on ${serviceToOnline}" >> ${file}
          fi

        elif [ ${serviceToOnline} == ${svcB} ]; then
          echo "`date` Killing service on ${svcB}" >> ${file}
          ssh -i ${keyFile} -o StrictHostKeyChecking=no cloud-user@${svcB} 'sudo /usr/lib/ocf/pre_shutdown/shutdown_sso.bsh &'
          #ssh -i ${keyFile} -o StrictHostKeyChecking=no cloud-user@${svcB} 'sudo pkill consul'
          if [ $? -ne 0 ]; then
              echo "ERROR when killing service on ${serviceToOnline}. Exiting" >> ${file}
              exit 1
          else
              SECONDS=0
              isPkillExecutedOnSvcB=true
              echo "`date` Pkilled service on ${serviceToOnline}" >> ${file}
          fi
        fi

      else
        echo "`date` Mixed mode detected. Consul pkill on a service has been previously executed, wait for left event" >> ${file}
        
		echo "Login as administrator" >> ${file}
		result=$(login ${user_administrator} ${user_administrator_pwd})
		echo "value $result" >> ${file}
		if [ ${result} -eq 0 ]; then
			echo "`date` Administrator LOGIN TEST PASSED" >> ${file}
		else
			echo "`date` Administrator LOGIN TEST FAILED" >> ${file}
			#exit 1
		fi
          
		if [ user_remote_testing = true ];then 
			echo "Login as remote user ${user_remote}" >> ${file}
			result2=$(login ${user_remote} ${user_remote_pwd})
			echo "value $result2" >> ${file}
			if [ ${result2} -eq 0 ]; then
				echo "`date` ${user_remote} LOGIN TEST PASSED" >> ${file}
			else
				echo "`date` ${user_remote} LOGIN TEST FAILED" >> ${file}
				#exit 1
			fi
		fi
		
      fi

    elif [ ${consulStateA} == "alive" ] && [ ${consulStateB} != "alive" ]; then
      echo "`date` The ${svcA} is ${consulStateA}, while ${svcB} is ${consulStateB}, NOT alive Waiting..." >> ${file}
      isPkillExecutedOnSvcB=false
      serviceToOnline=${svcA}

        echo "Login as administrator" >> ${file}
		result=$(login ${user_administrator} ${user_administrator_pwd})
		echo "value $result" >> ${file}
		if [ ${result} -eq 0 ]; then
			echo "`date` Administrator LOGIN TEST PASSED" >> ${file}
		else
			echo "`date` Administrator LOGIN TEST FAILED" >> ${file}
			#exit 1
		fi
          
		if [ user_remote_testing = true ];then 
			echo "Login as remote user ${user_remote}" >> ${file}
			result2=$(login ${user_remote} ${user_remote_pwd})
			echo "value $result2" >> ${file}
			if [ ${result2} -eq 0 ]; then
				echo "`date` ${user_remote} LOGIN TEST PASSED" >> ${file}
			else
				echo "`date` ${user_remote} LOGIN TEST FAILED" >> ${file}
				#exit 1
			fi	
		fi

    elif [ ${consulStateA} != "alive" ] && [ ${consulStateB} == "alive" ]; then
      echo "`date` The ${svcA} is ${consulStateA}, NOT alive while ${svcB} is ${consulStateB}. Waiting..." >> ${file}
      isPkillExecutedOnSvcA=false
      serviceToOnline=${svcB}

      echo "Login as administrator" >> ${file}
		result=$(login ${user_administrator} ${user_administrator_pwd})
		echo "value $result" >> ${file}
		if [ ${result} -eq 0 ]; then
			echo "`date` Administrator LOGIN TEST PASSED" >> ${file}
		else
			echo "`date` Administrator LOGIN TEST FAILED" >> ${file}
			#exit 1
		fi
          
		if [ user_remote_testing x= true ];then 
			echo "Login as remote user ${user_remote}" >> ${file}
			result2=$(login ${user_remote} ${user_remote_pwd})
			echo "value $result2" >> ${file}
			if [ ${result2} -eq 0 ]; then
				echo "`date` ${user_remote} LOGIN TEST PASSED" >> ${file}
			else
				echo "`date` ${user_remote} LOGIN TEST FAILED" >> ${file}
				#exit 1
			fi	
		fi

    else
      echo "`date` Both ${my_service} are not alive. Abort" >> ${file}
      exit 1
    fi

  else
    echo "Unknown mode detected: ${my_mode}. Abort" >> ${file}
    exit 1
  fi

}

check_stop_condition() {
  if [ -f ${stop_file} ]; then
    echo "Terminating script due to stop condition detected..." >> ${file}
    break
  fi
}



### MAIN ###
while [ 1 > 0 ]
do
  #Check if any file flag set to stop/suspend the process
  check_stop_condition

  if [ ${my_isOnCloud} = true ]; then
    manage_env_cloud
  else
    manage_env_physical
  fi

  echo "Sleeping ${sleeping_timeout} s"
  sleep ${sleeping_timeout}

done

echo "Completed" >> ${file}
