#!/bin/sh
set -eu
cd /app
exec /opt/jdk/bin/java -cp "$(cat /app/classpath.txt)" dev.oreslang.launcher.OresMain \
  --no-core-log --permission-check=runtime --allow-net=127.0.0.1:5001,127.0.0.1:5002 \
  /app/sharkbench-web.atto
