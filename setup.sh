#!/bin/bash

# 检查是否以 root 权限运行
if [ "$EUID" -ne 0 ]; then 
  echo "请使用 root 权限运行此脚本"
  exit 1
fi

# 设置工作目录
WORK_DIR="/root/projects/order-system"
echo "工作目录: $WORK_DIR"

# 清理旧的安装
echo "清理旧的安装..."
systemctl stop order-system 2>/dev/null || true
rm -rf $WORK_DIR
rm -f /etc/systemd/system/order-system.service

# 创建项目目录
echo "创建项目目录..."
mkdir -p $WORK_DIR/frontend/dist
mkdir -p $WORK_DIR/backend

# 创建测试页面
echo "创建测试页面..."
cat > $WORK_DIR/frontend/dist/index.html << EOF
<!DOCTYPE html>
<html>
<head>
    <title>测试页面</title>
</head>
<body>
    <h1>测试页面</h1>
    <p>当前时间: <span id="time"></span></p>
    <script>
        document.getElementById('time').textContent = new Date().toLocaleString();
    </script>
</body>
</html>
EOF

# 创建简单的后端服务
echo "创建后端服务..."
cat > $WORK_DIR/backend/main.go << EOF
package main

import "github.com/gin-gonic/gin"

func main() {
    r := gin.Default()
    r.GET("/api/health", func(c *gin.Context) {
        c.JSON(200, gin.H{
            "status": "ok",
            "message": "服务正常运行",
        })
    })
    r.Run(":8080")
}
EOF

# 初始化 Go 模块
cd $WORK_DIR/backend
go mod init backend
go get github.com/gin-gonic/gin
go mod tidy

# 编译后端
go build -o server

# 创建系统服务
echo "创建系统服务..."
cat > /etc/systemd/system/order-system.service << EOF
[Unit]
Description=Order System Backend Service
After=network.target

[Service]
Type=simple
WorkingDirectory=/root/projects/order-system/backend
ExecStart=/root/projects/order-system/backend/server
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# 配置 Caddy
echo "配置 Caddy..."
cat > /etc/caddy/Caddyfile << EOF
order.076095598.xyz {
    # API 转发
    handle /api/* {
        reverse_proxy localhost:8080
    }

    # 静态文件
    handle {
        root * /root/projects/order-system/frontend/dist
        file_server
    }
}
EOF

# 设置权限
chown -R caddy:caddy /etc/caddy
chmod 644 /etc/caddy/Caddyfile

# 启动服务
echo "启动服务..."
systemctl daemon-reload
systemctl restart order-system
systemctl restart caddy

# 等待服务启动
sleep 2

echo "
测试说明：

1. 访问网站：
   https://order.076095598.xyz

2. 测试健康检查：
   curl https://order.076095598.xyz/api/health

3. 查看日志：
   systemctl status order-system
   systemctl status caddy
" 