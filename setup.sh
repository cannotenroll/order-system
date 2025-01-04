#!/bin/bash

# 检查是否以 root 权限运行
if [ "$EUID" -ne 0 ]; then 
  echo "请使用 root 权限运行此脚本"
  exit 1
fi

# 设置工作目录
WORK_DIR="/root/projects/order-system"

# 安装必要的系统包
apt update
apt install -y git golang-go sqlite3

# 创建项目目录
mkdir -p $WORK_DIR
cd $WORK_DIR

# 克隆项目代码
git clone https://github.com/cannotenroll/order-system.git .

# 进入后端目录并初始化 Go 模块
cd backend
go mod init github.com/cannotenroll/order-system

# 安装 Go 依赖
go get -u github.com/gin-gonic/gin
go get -u gorm.io/gorm
go get -u gorm.io/driver/sqlite
go get -u golang.org/x/crypto/bcrypt

# 编译后端程序
go build -o order-system

# 创建系统服务
cat > /etc/systemd/system/order-system.service << EOF
[Unit]
Description=Order System Backend Service
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/root/projects/order-system/backend
ExecStart=/root/projects/order-system/backend/order-system
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# 更新 Caddy 配置
cat > /etc/caddy/Caddyfile << EOF
order.076095598.xyz {
    reverse_proxy localhost:8080
}
EOF

# 重新加载系统服务
systemctl daemon-reload

# 启动并设置开机自启
systemctl enable order-system
systemctl start order-system

# 重启 Caddy
systemctl restart caddy

# 检查服务状态
echo "检查服务状态..."
systemctl status order-system
systemctl status caddy

# 输出测试说明
echo "
安装完成！请使用以下命令测试系统：

1. 检查本地访问：
   curl http://localhost:8080/api/health

2. 检查域名访问：
   curl https://order.076095598.xyz/api/health

如果返回 {\"status\":\"ok\"} 则表示系统运行正常。

查看日志：
- 后端日志：journalctl -u order-system -f
- Caddy日志：journalctl -u caddy -f
"

# 创建日志快捷方式
echo 'alias order-logs="journalctl -u order-system -f"' >> /root/.bashrc
echo 'alias caddy-logs="journalctl -u caddy -f"' >> /root/.bashrc

# 应用新的别名
source /root/.bashrc 