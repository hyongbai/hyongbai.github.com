#!/bin/bash

if [ ! ${1} ]; then
    echo "input comment!!!"
    exit
fi

#
base_url=$(cat CNAME)

#
cp _config.yml _config.bkup
echo "baseurl: \"http://${base_url}\"" >> _config.yml
mv _config.bkup _config.yml

# publish
gitsh . "${1}"
