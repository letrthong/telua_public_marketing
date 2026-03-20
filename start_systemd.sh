
cp -fv sync-git.service /etc/systemd/system/
systemctl daemon-reload
systemctl start sync-git
systemctl enable sync-git # Tự chạy khi khởi động máy