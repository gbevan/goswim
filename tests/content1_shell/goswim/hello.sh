#!/bin/sh
LANG=C.UTF-8

echo "Hello World!"
env
ps -efl

ls -laR /goswim /secrets*
cat /secrets.yml

ping -c 3 www.google.com
