package main

import (
	"fmt"

	"github.com/gin-gonic/gin"
)

func main() {

	r := gin.Default()
	trying_to_rule := "Pratik Rocks"
	fmt.Println("Toh shuru karte hai, bina kissi Bakchodi ke, ", trying_to_rule)

	r.GET("/", func(c *gin.Context) {
		c.String(200, "Kem cho, Majama?")
	})

	r.GET("/health", func(c *gin.Context) {
		c.String(200, "Abhi hum jinda hai")
	})

	fmt.Println("Server is running on port 6969")

	r.Run(":6969")
}
