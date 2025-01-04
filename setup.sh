#!/bin/bash

# 检查是否以 root 权限运行
if [ "$EUID" -ne 0 ]; then 
  echo "请使用 root 权限运行此脚本"
  exit 1
fi

# 设置工作目录
WORK_DIR="/root/projects/order-system"
echo "工作目录: $WORK_DIR"

# 安装必要的系统包
echo "正在更新系统包..."
apt update

# 检查并安装 Caddy
if ! command -v caddy &> /dev/null; then
    echo "安装 Caddy..."
    apt install -y debian-keyring debian-archive-keyring apt-transport-https
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list
    apt update
    apt install -y caddy
fi

# 安装新版本的 Go
echo "安装新版本的 Go..."
apt install -y git sqlite3 build-essential gcc wget

# 下载并安装 Go 1.21
cd /tmp
wget https://go.dev/dl/go1.21.5.linux-amd64.tar.gz
rm -rf /usr/local/go
tar -C /usr/local -xzf go1.21.5.linux-amd64.tar.gz
ln -sf /usr/local/go/bin/go /usr/bin/go
rm go1.21.5.linux-amd64.tar.gz
cd -

# 清理旧的安装（如果存在）
echo "清理旧的安装..."
systemctl stop order-system 2>/dev/null
rm -rf $WORK_DIR
rm -f /etc/systemd/system/order-system.service
rm -f /var/log/order-system.log
rm -f /var/log/order-system.error.log

# 创建项目目录
echo "创建项目目录..."
mkdir -p $WORK_DIR
cd $WORK_DIR || exit 1

# 克隆项目代码
echo "克隆项目代码..."
git clone https://github.com/cannotenroll/order-system.git . || {
    echo "克隆代码失败"
    exit 1
}

# 更新 main.go 文件
echo "更新 main.go 文件..."
cat > $WORK_DIR/backend/main.go << EOF
package main

import (
	"github.com/cannotenroll/order-system/config"
	"github.com/cannotenroll/order-system/controllers"
	"github.com/cannotenroll/order-system/models"
	"github.com/cannotenroll/order-system/routes"
	"github.com/gin-gonic/gin"
)

func main() {
	// 初始化数据库
	db := config.InitDB()

	// 初始化控制器
	controllers.InitDB(db)

	// 自动迁移数据库表
	db.AutoMigrate(&models.User{}, &models.Order{})

	// 创建默认管理员账号
	var adminUser models.User
	if db.Where("username = ?", "admin").First(&adminUser).RowsAffected == 0 {
		adminUser = models.User{
			Username: "admin",
			Password: "admin1234",
			IsAdmin:  true,
		}
		db.Create(&adminUser)
	}

	// 初始化 Gin
	r := gin.Default()

	// 设置路由
	routes.SetupRoutes(r)

	// 启动服务器
	r.Run(":8080")
}
EOF

# 创建前端目录和页面
echo "创建前端基础页面..."
mkdir -p $WORK_DIR/frontend/dist
# 设置前端目录权限
chown -R www-data:www-data $WORK_DIR/frontend
chmod -R 755 $WORK_DIR/frontend

# 创建临时前端页面
cat > $WORK_DIR/frontend/dist/index.html << EOF
<!DOCTYPE html>
<html lang="zh">
<head>
    <meta charset="UTF-8">
    <title>订餐系统</title>
</head>
<body>
    <h1>测试页面</h1>
    <p>如果你能看到这个页面，说明静态文件服务正常工作。</p>
</body>
</html>
EOF
chmod 644 $WORK_DIR/frontend/dist/index.html

# 创建认证控制器
echo "创建认证控制器..."
mkdir -p $WORK_DIR/backend/controllers
cat > $WORK_DIR/backend/controllers/auth.go << 'EOF'
package controllers

import (
	"github.com/gin-gonic/gin"
	"github.com/cannotenroll/order-system/models"
	"gorm.io/gorm"
	"net/http"
)

var db *gorm.DB

func InitDB(database *gorm.DB) {
	db = database
}

func Login(c *gin.Context) {
	var loginData struct {
		Username string `json:"username" binding:"required"`
		Password string `json:"password" binding:"required"`
	}

	if err := c.ShouldBindJSON(&loginData); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "请输入用户名和密码"})
		return
	}

	var user models.User
	if err := db.Where("username = ?", loginData.Username).First(&user).Error; err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "用户名或密码错误"})
		return
	}

	if !user.CheckPassword(loginData.Password) {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "用户名或密码错误"})
		return
	}

	// TODO: 生成 JWT token
	token := "temporary-token"

	c.JSON(http.StatusOK, gin.H{
		"token": token,
		"user": gin.H{
			"username": user.Username,
			"isAdmin": user.IsAdmin,
		},
	})
}
EOF

# 更新路由配置
echo "更新路由配置..."
cat > $WORK_DIR/backend/routes/routes.go << EOF
package routes

import (
	"github.com/gin-gonic/gin"
	"github.com/cannotenroll/order-system/controllers"
)

func SetupRoutes(r *gin.Engine) {
	// 基础路由组
	api := r.Group("/api")

	// 健康检查
	api.GET("/health", func(c *gin.Context) {
		c.JSON(200, gin.H{
			"status": "ok",
		})
	})

	// 认证路由
	auth := api.Group("/auth")
	{
		auth.POST("/login", controllers.Login)
	}
}
EOF

# 进入后端目录并初始化 Go 模块
echo "初始化 Go 模块..."
cd backend || exit 1

# 删除可能存在的旧 go.mod 文件
rm -f ../go.mod ../go.sum
rm -f go.mod go.sum

# 清理旧文件
rm -f order-system go.mod go.sum

# 初始化新的 go.mod
cat > go.mod << EOF
module github.com/cannotenroll/order-system

go 1.21

require (
	github.com/gin-gonic/gin v1.9.1
	github.com/mattn/go-sqlite3 v1.14.19
	golang.org/x/crypto v0.16.0
	gorm.io/driver/sqlite v1.5.4
	gorm.io/gorm v1.25.5
)
EOF

# 下载依赖并整理
go mod tidy

# 编译（添加详细输出）
CGO_ENABLED=1 GOOS=linux GOARCH=amd64 go build -v -x -o order-system

# 检查编译结果
ls -l order-system

# 设置执行权限
chmod +x order-system

# 停止正在运行的服务（如果有）
systemctl stop order-system 2>/dev/null || true

# 创建日志目录和文件
echo "创建日志文件..."
touch /var/log/order-system.log
touch /var/log/order-system.error.log
chmod 644 /var/log/order-system.log
chmod 644 /var/log/order-system.error.log

# 创建系统服务
echo "创建系统服务..."
BINARY_PATH="$(pwd)/order-system"
echo "二进制文件路径: $BINARY_PATH"

cat > /etc/systemd/system/order-system.service << EOF
[Unit]
Description=Order System Backend Service
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/root/projects/order-system/backend
ExecStart=$BINARY_PATH
Restart=on-failure
RestartSec=5
StandardOutput=append:/var/log/order-system.log
StandardError=append:/var/log/order-system.error.log
Environment=GIN_MODE=release

[Install]
WantedBy=multi-user.target
EOF

# 更新 Caddy 配置
echo "更新 Caddy 配置..."
mkdir -p /etc/caddy
chown -R caddy:caddy /etc/caddy
chmod 755 /etc/caddy

# 备份旧的配置文件（如果存在）
if [ -f "/etc/caddy/Caddyfile" ]; then
    mv /etc/caddy/Caddyfile /etc/caddy/Caddyfile.bak
fi

cat > /etc/caddy/Caddyfile << EOF
order.076095598.xyz {
    # API 请求转发到后端
    handle /api/* {
        reverse_proxy localhost:8080
    }

    # 静态文件服务
    handle {
        root * /root/projects/order-system/frontend/dist
        file_server
    }

    # 启用 gzip 压缩
    encode gzip
}
EOF

# 确保 Caddy 配置文件权限正确
chown caddy:caddy /etc/caddy/Caddyfile
chmod 644 /etc/caddy/Caddyfile

# 验证配置文件是否正确更新
if [ ! -f "/etc/caddy/Caddyfile" ]; then
    echo "错误：Caddyfile 未能成功创建"
    exit 1
fi

echo "Caddy 配置文件更新时间：$(stat -c %y /etc/caddy/Caddyfile)"

# 重新加载系统服务
echo "重新加载系统服务..."
systemctl daemon-reload

# 启动并设置开机自启
echo "启动服务..."
if [ ! -x "$BINARY_PATH" ]; then
    echo "错误：程序文件不存在或不可执行"
    ls -l "$BINARY_PATH"
    exit 1
fi

systemctl enable order-system
systemctl start order-system

# 等待服务启动
sleep 2

# 检查服务状态
echo "检查服务状态..."
if ! systemctl is-active --quiet order-system; then
    echo "服务启动失败，查看错误日志："
    tail -n 20 /var/log/order-system.error.log
    journalctl -u order-system -n 50 --no-pager
    exit 1
fi

# 重启 Caddy
echo "重启 Caddy..."
systemctl restart caddy

# 检查 Caddy 状态
if ! systemctl is-active --quiet caddy; then
    echo "Caddy 服务启动失败，查看错误日志："
    journalctl -u caddy -n 50 --no-pager
    exit 1
fi

# 检查服务是否正常运行
echo "测试服务..."
curl -s http://localhost:8080/api/health || {
    echo "服务测试失败"
    exit 1
}

echo "
安装完成！请使用以下命令测试系统：

1. 检查本地访问：
   curl http://localhost:8080/api/health

2. 检查域名访问：
   curl https://order.076095598.xyz/api/health

如果返回 {\"status\":\"ok\"} 则表示系统运行正常。

查看日志：
- 应用日志：tail -f /var/log/order-system.log
- 错误日志：tail -f /var/log/order-system.error.log
- 系统日志：journalctl -u order-system -f
- Caddy日志：journalctl -u caddy -f
"

# 创建日志快捷方式
echo 'alias order-logs="tail -f /var/log/order-system.log"' >> /root/.bashrc
echo 'alias order-errors="tail -f /var/log/order-system.error.log"' >> /root/.bashrc
echo 'alias order-journal="journalctl -u order-system -f"' >> /root/.bashrc
echo 'alias caddy-logs="journalctl -u caddy -f"' >> /root/.bashrc

# 应用新的别名
source /root/.bashrc

echo "脚本执行完成" 