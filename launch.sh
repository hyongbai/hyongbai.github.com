#!/bin/bash

# config
_blog_c_name="blog.yourbay.me"
_blog_work_dir=$(cd "$(dirname "$0")"; pwd)
cid=`docker ps -a | grep "${_blog_c_name}" | awk '{print $1}'`

# start docker container
[[ "${cid}" ]] && docker start ${cid}
[[ ! "${cid}" ]] && docker run --name ${_blog_c_name} -p 4000:4000 -v \
"${_blog_work_dir}":/srv -w /srv -d jekyll/jekyll:3.5.2 \
/bin/sh -c "jekyll clean && jekyll build && jekyll serve"