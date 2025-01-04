package models

import (
	"time"

	"gorm.io/gorm"
)

type MealType string

const (
	Breakfast MealType = "breakfast"
	Lunch     MealType = "lunch"
)

type Order struct {
	gorm.Model
	UserID       uint      `json:"user_id"`
	User         User      `gorm:"foreignKey:UserID" json:"user"`
	Date         time.Time `json:"date"`
	MealType     MealType  `json:"meal_type"`
	IsNormal     bool      `json:"is_normal"`     // true: 正常用餐, false: 停餐
	GuestCount   int       `json:"guest_count"`   // 客餐人数
	GuestCompany string    `json:"guest_company"` // 客餐人员单位
}
