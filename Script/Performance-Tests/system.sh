# System under test

HAPROXY_URL=`cat /ericsson/tor/data/global.properties | grep UI_PRES_SERVER | cut -d= -f2` # to be used when run in MS-1
#HAPROXY_URL="ieatenm5416-87.athtem.eei.ericsson.se"                             # in case test has to be launched against vApp
#HAPROXY_URL="ieatenm5267-1.athtem.eei.ericsson.se"                             # in case test has to be launched against phy env
#HAPROXY_URL="ieatenmc15a004.athtem.eei.ericsson.se"                             # in case test has to be launched against phy env
#HAPROXY_URL="enmapache.athtem.eei.ericsson.se"                             # in case test has to be launched against phy env
#HAPROXY_URL="ieatenmc15a004.athtem.eei.ericsson.se"                             # in case test has to be launched against cENM env
#HAPROXY_URL="ieatenmc6b04-9.athtem.eei.ericsson.se"
#HAPROXY_URL="ieatENM5344-13.athtem.eei.ericsson.se"
#HAPROXY_URL="ieatenmc200.athtem.eei.ericsson.se"
#HAPROXY_URL="ieatenmc10a012.athtem.eei.ericsson.se"

# Error configuration
TEST_ERROR_THRESHOLD=2   # % Threshold of errors for any login/verify/logout operation - failed/total must be less [default: 5]
TEST_ERROR_FILE=./.error_file.txt # Flag file to be used to mark test failed

#
# Type of test to be configured in #General Parameters
# ASYNC means to perform a series of Login/Logout actions ensuring a specific Login/sec rate ASYNC_NO_LOGIN_PER_SECOND_PER_USER
#       per user, for an overall intervall ASYNC_TEST_DURATION in seconds.
#
# SYNC means to perform a series of Login/Verify/Logout actions waiting and evaluating HTTP response for each action.
#      Test duration depends on #Delay configuration and HTTP response time due to the system/network.
# 

# General Parameters
CREATE_USERS=true      # to create users
USERS=5
ASYNC=false            # will perform a test where login are executed asynchronously so without waiting for response for true parallel stress
USE_JWT=false          # Cookie - JWT HAS BEEN REMOVED !!!
                       # With introduction of AM 6.5.4, JWT HAS BEEN REMOVED


# SYNC CONFIGURATION ##########
ITERATION=50            #nr of serial login for each user to be performed subsequently one another - [default: 10]
SESSIONS=1              #nr of sessions for each user - [default: 1]
VERIFY_PER_SESSION=0    #nr of validation per iteration - [default: 0]
# Delay
DELAY_BETWEEN_USERS=0   # delay in secs between launching of two different users during sso_test_parallel.sh [Default=0]
LOGIN_VERIFY=2          # delay in secs between Login and Verification phases for each user [Default=1]
VERIFY_VERIFY=0         # delay in secs between two consecutive Verification for each user [Default=0.5]
VERIFY_LOGOUT=2         # delay in secs between Verification and Logout phases for each user [Default=1]
# Actions
LOGIN=true                      # login is enabled - default=true
VERIFICATION=false               # Verification is enabled - default=false
LOGOUT=true                     # logout is enabled - default=true
# Logging
HEADERS="User;Min [ms];Avg [ms];Max [ms];Count;Result"     # Headers to be inserted in csv file
GLOBAL_LOGIN=SummaryFile_Login.csv      # csv file for Login data
GLOBAL_LOGOUT=SummaryFile_Logout.csv    # csv file for Logout data
GLOBAL_VERIFY=SummaryFile_Verify.csv    # csv file for Verify data
REDUCE_LOG=true                         # this flag allows log files to reduce the space stored [Default: true]


#ASYNC=true                             # will perform a test where login are executed asynchronously so without waiting for response for true parallel stress.
# ASYNC CONFIGURATION ##########
ASYNC_NO_LOGIN_PER_SECOND_PER_USER=4    # number of login request per second done by every single user - used in async test
ASYNC_TEST_DURATION=25                  # duration of async test in seconds
DO_LOGOUT=true							# to perform logout activity after login
LOGOUT_TIMEOUT_SEC=10					# timeout interval, from starting of login, after that logout activity will be started
# interval time
sleep_time_sec=$(echo "scale=3;1/$ASYNC_NO_LOGIN_PER_SECOND_PER_USER" | bc )
echo "sleep time : ${sleep_time_sec}"


# Logging
if [ ${ASYNC} = false ]; then
  TARGET_DIR=${USERS}u_${ITERATION}i_${SESSIONS}s_${VERIFY_PER_SESSION}v_SYNC
else
  ITERATION=$(( ${ASYNC_NO_LOGIN_PER_SECOND_PER_USER} * ${ASYNC_TEST_DURATION} ))
  TARGET_DIR=${USERS}u_${ITERATION}i_${ASYNC_NO_LOGIN_PER_SECOND_PER_USER}s_${ASYNC_TEST_DURATION}d_ASYNC
fi


# Additional configuration
ENABLE_EXTIDP=false     # this flag to enable external idp setting              
LMT_STABILITY=false     # this flag allows to use remote users to test external idp [Default: false]
USER_FILE=./PerfTest_Users_${USERS}.txt

if [ "${LMT_STABILITY}" = true ]; then
	echo "LMT mode is ON, using user file ${USER_FILE}"
    USER_FILE=./PerfTest_Users_LMT_stability.txt
    USERS=2
    LOGIN_VERIFY=60
    VERIFY_LOGOUT=60
    ITERATION=150 # 120s sleep per iteration (60s login/verification and 60s verification/logout), 150 iterations => approx 5h test duration
    SESSIONS=2
    ENABLE_EXTIDP=true  # external idp setting forced to enable         
fi

# Session duration test is enable
PERFORM_SESSION_TEST=false
# How long the session idle time will last [in minutes]
SESSION_TIMEOUT_MINUTE=1
# How long the session will last for max time [in minutes]  
SESSION_TIMEOUT_MAX_DURATION_MINUTE=$(($SESSION_TIMEOUT_MINUTE +2))


if [ "${LOGIN}" = false ] && [ "${VERIFICATION}" = true ]; then
    CREATE_USERS=false
    echo "User creation forcibly set to ${CREATE_USERS} since no login perfomed and verification check enabled"
fi


