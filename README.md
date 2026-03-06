which nohup
  /usr/bin/nohup


nohup ./sync_git_auto.sh > sync_history.log 2>&1 &


ps -ef | grep sync_git_auto.sh


Debian os
sudo apt-get update
sudo apt-get install coreutils
