 apt-get install rsync

which nohup
  /usr/bin/nohup


nohup ./sync_git_auto.sh > /opt/sync_history.log 2>&1 &


ps -ef | grep sync_git_auto.sh


Debian os
sudo apt-get update
sudo apt-get install coreutils


systemctl status sync-git
systemctl stop sync-git

systemctl restart sync-git
