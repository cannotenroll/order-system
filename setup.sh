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

# 进入后端目录并初始化 Go 模块
echo "初始化 Go 模块..."
cd backend || exit 1

# 删除可能存在的旧 go.mod 文件
rm -f ../go.mod ../go.sum
rm -f go.mod go.sum

go mod init github.com/cannotenroll/order-system

# 安装 Go 依赖
echo "安装 Go 依赖..."
cat > go.mod << EOF
module github.com/cannotenroll/order-system

go 1.21.5

require (
	github.com/gin-gonic/gin v1.9.1
	github.com/mattn/go-sqlite3 v1.14.19
	golang.org/x/crypto v0.16.0
	gorm.io/driver/sqlite v1.5.4
	gorm.io/gorm v1.25.5
)
EOF

# 下载依赖
go mod download
go mod tidy

# 编译后端程序
echo "编译后端程序..."
echo "当前目录: $(pwd)"
echo "Go 版本: $(go version)"
echo "Go 环境: $(go env GOPATH)"

# 确保 go.sum 文件存在
go mod download
go mod tidy

CGO_ENABLED=1 GOOS=linux GOARCH=amd64 \
go build -v -x -o order-system || {
    echo "编译失败"
    echo "编译错误日志："
    cat /var/log/order-system.error.log
    exit 1
}

# 检查编译结果
echo "检查编译结果..."
if [ ! -f "order-system" ]; then
    echo "编译后的程序不存在"
    ls -la
    exit 1
fi

echo "编译成功，程序大小: $(ls -lh order-system)"

# 设置可执行权限
chmod +x order-system

# 验证程序是否可执行
echo "验证程序..."
file order-system
ldd order-system || true

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
cat > /etc/caddy/Caddyfile << EOF
order.076095598.xyz {
    reverse_proxy localhost:8080
}
EOF

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