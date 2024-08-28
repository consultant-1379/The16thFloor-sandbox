#!/bin/bash

#
# This script collects and filters data results from files
# input:
# $1 = target_dir in which files are stored
# $2 = action on which performs data collection (login or logout)
#

# Preliminary check
if [ -z $1 ]; then
  echo "'Target dir' is not present !!"
  exit 1
fi
if [ -z $2 ]; then
  echo "'Action' is not present !!"
  exit 1
fi
target_dir=$1
action=$2


# File preparation
if [ -d $target_dir ]; then
  cd $target_dir
  resultFile=$action"_results.csv"
  if [ -f ${resultFile} ]; then
     cp ${resultFile} "${resultFile}-old"
     rm -f ${resultFile}
  fi
  echo "file = ${resultFile}"
  HEADERS="User;Sent;Success;Failed"     # Headers to be inserted in csv file
  echo $HEADERS > ${resultFile}
else
  echo "Target dir is not present !"
  exit 1
fi

# Data extract
files=$( ls -ltr | grep $action".txt" | awk '{print $9}')

for f in $files; do
  fail="-" success="-" sent="-"
  if [ $action = "login" ]; then
    fail=$(grep "Error login for user" $f | wc -l)
    success=$(grep "Login successful" $f | wc -l)
    sent=$(grep "Logging in as user" $f | wc -l)
  elif [ $action = "logout" ]; then
    success=$(grep "Logging out as " $f | wc -l)
    fail=$(grep "could not logout" $f | wc -l)
    sent=$(($success+$fail))
  fi
  u=$(echo $f | cut -d'-' -f2 | cut -d'_' -f1)
  echo "$u;$sent;$success;$fail" >> ${resultFile}
done

echo "Data collection for $target_dir with $action - FINISHED"
exit 0
