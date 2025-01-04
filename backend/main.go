package main

import (
	"github.com/cannotenroll/order-system/config"
	"github.com/cannotenroll/order-system/models"
	"github.com/cannotenroll/order-system/routes"
	"github.com/gin-gonic/gin"
)

func main() {
	// 初始化数据库
	db := config.InitDB()

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
