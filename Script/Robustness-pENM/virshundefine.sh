#!/bin/bash
service=sso
file=./${service}_virsh_undefine.txt
virsh undefine ${service}
echo "`date` virsh undefine ${service}" >> ${file}
