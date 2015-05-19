#!/bin/bash

host="yourbay.me"

cp _config.yml _config.bkup
echo "baseurl: \"http://${host}\"" >> _config.yml
cat _config.yml
jekyll b
mv _config.bkup _config.yml

