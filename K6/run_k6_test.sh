#!/bin/bash

usage()
{
  cat << EOF
Usage: $(basename "$0") <k6 test filename>
The script execute a K6 test.

Parameters:
  -s <k6 test filename>: the test filename
  -d: use the K6 docker image to run the test

Example: $(basename "$0") -s sso-limit-benchmark.js

EOF
}

options='s:dh?'
while getopts "${options}" option
do
    case "$option" in
        s  ) TEST_FILENAME=$OPTARG;;
        d  ) RUN_DOCKER_IMAGE=TRUE;;
        h  ) usage; exit;;
        \?  ) usage; exit;;
    esac
done

# Check script parameter
if [ -z "${TEST_FILENAME}" ]; then
    echo -e "ERROR! No K6 script specified\n"
    usage
    exit 1
fi

# Remove script filename extension
TEST_NO_EXT_FILENAME=${TEST_FILENAME%.*}

# Define log filenames
K6_LOG="${TEST_NO_EXT_FILENAME}"-k6.log
CONSOLE_LOG="${TEST_NO_EXT_FILENAME}"-console.log
RESULT_LOG="${TEST_NO_EXT_FILENAME}"-result.log

# Remove log files
rm -f "${K6_LOG}" "${CONSOLE_LOG}" "${RESULT_LOG}"

if [ -z "${RUN_DOCKER_IMAGE}" ]; then
  # Run K6 test
  nohup k6 run --quiet --verbose --log-output=file="${K6_LOG}" --console-output "${CONSOLE_LOG}" "${TEST_FILENAME}" | tee "${RESULT_LOG}" &
else
  # Run K6 test using the docker image
  docker run --rm -i grafana/k6 run - < "${TEST_FILENAME}" > "${K6_LOG}"
fi
