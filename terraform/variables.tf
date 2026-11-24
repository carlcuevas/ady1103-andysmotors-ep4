variable "region" {
  description = "Region de AWS del caso"
  type        = string
  default     = "us-east-1"
}

variable "correo_alertas" {
  description = "Correo que recibe las alertas operativas y de costo (SNS)"
  type        = string
  default     = "carl.cuevasn@duocuc.cl"
}

variable "tipo_instancia" {
  description = "Tipo de la instancia que aloja las seis plataformas (8 contenedores)"
  type        = string
  default     = "t3.small"
}

variable "repo_url" {
  description = "Repositorio del docente con el caso AndysMotors"
  type        = string
  default     = "https://github.com/asanchezo-duoc/ADY1103-Activities.git"
}

# -----------------------------------------------------------------------------
# Umbral de la alarma de presupuesto (seccion 7 del informe)
# Derivado de la Estimacion B (diseno optimizado):
#   30 instancias x 1 llamada PutMetricData por minuto (batching de 20 metricas)
#   = 150 llamadas por periodo de 5 minutos
#   costo esperado = (150 / 1000) x 0,01 = USD 0,0015 por periodo
#   margen de tolerancia del 50 % -> umbral = USD 0,00225 (225 llamadas / 5 min)
# -----------------------------------------------------------------------------
variable "umbral_costo_usd" {
  description = "Umbral de la alarma de costo de PutMetricData por periodo de 5 minutos (USD)"
  type        = number
  default     = 0.00225
}

variable "duracion_trafico_seg" {
  description = "Segundos que corre el generador de trafico del docente al arrancar la instancia"
  type        = number
  default     = 14400
}
