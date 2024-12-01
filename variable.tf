variable "dynamodb_table_name" {
  description = "El nombre de la tabla de DynamoDB"
  type        = string
  default     = "SupportTable"
}

variable "region" {
  description = "Region"
  type        = string
  default     = "us-east-1"
}
