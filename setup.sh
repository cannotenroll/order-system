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

# 创建项目目录
echo "创建项目目录..."
mkdir -p $WORK_DIR/frontend/dist

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

# 设置权限
echo "设置权限..."
chown -R caddy:caddy $WORK_DIR
chmod -R 755 $WORK_DIR
chmod 644 $WORK_DIR/frontend/dist/index.html

# 配置 Caddy
echo "配置 Caddy..."
cat > /etc/caddy/Caddyfile << EOF
order.076095598.xyz {
    root * /root/projects/order-system/frontend/dist
    file_server browse
}
EOF

# 设置 Caddy 配置权限
chown caddy:caddy /etc/caddy/Caddyfile
chmod 644 /etc/caddy/Caddyfile

# 重启 Caddy
echo "重启 Caddy..."
systemctl restart caddy

# 显示调试信息
echo "
调试信息：
"
echo "1. 目录内容："
ls -la $WORK_DIR/frontend/dist/

echo "
2. Caddy 配置："
cat /etc/caddy/Caddyfile

echo "
3. Caddy 状态："
systemctl status caddy --no-pager

echo "
4. Caddy 日志："
journalctl -u caddy -n 20 --no-pager

echo "
测试说明：

1. 访问网站：
   https://order.076095598.xyz

2. 如果出现问题，查看日志：
   journalctl -u caddy -f
" 