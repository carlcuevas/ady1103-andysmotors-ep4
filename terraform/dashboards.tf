# =============================================================================
# Dashboards. Nota para la auditoria: los dashboards de CloudWatch NO admiten
# etiquetas, por lo que su costo no se puede asignar por tag (hallazgo).
# =============================================================================

locals {
  usage_putmetricdata = ["AWS/Usage", "CallCount", "Service", "CloudWatch", "Type", "API", "Resource", "PutMetricData", "Class", "None"]
}

resource "aws_cloudwatch_dashboard" "infraestructura" {
  dashboard_name = "AndysMotors-Infraestructura"
  dashboard_body = jsonencode({
    widgets = [
      {
        type = "metric", x = 0, y = 0, width = 12, height = 6
        properties = {
          title = "CPU de la instancia (%)", region = var.region, view = "timeSeries", stat = "Average", period = 60
          metrics = [["AWS/EC2", "CPUUtilization", "InstanceId", aws_instance.andys.id]]
        }
      },
      {
        type = "metric", x = 12, y = 0, width = 12, height = 6
        properties = {
          title = "Memoria y disco usados (%)", region = var.region, view = "timeSeries", stat = "Average", period = 60
          metrics = [
            ["CWAgent", "mem_used_percent", "InstanceId", aws_instance.andys.id],
            ["CWAgent", "disk_used_percent", "InstanceId", aws_instance.andys.id]
          ]
        }
      }
    ]
  })
}

resource "aws_cloudwatch_dashboard" "negocio" {
  dashboard_name = "AndysMotors-Negocio"
  dashboard_body = jsonencode({
    widgets = [
      {
        type = "metric", x = 0, y = 0, width = 12, height = 6
        properties = {
          title = "Metricas de negocio inyectadas (AndysMotors/Negocio, por minuto)", region = var.region,
          view = "timeSeries", stat = "Sum", period = 60
          metrics = [
            ["AndysMotors/Negocio", "AgendamientosRegistrados", "Plataforma", "agenda"],
            ["AndysMotors/Negocio", "OportunidadesCreadas", "Plataforma", "crm"],
            ["AndysMotors/Negocio", "PagosProcesados", "Plataforma", "pagos"],
            ["AndysMotors/Negocio", "PagosRechazados", "Plataforma", "pagos"]
          ]
        }
      },
      {
        type = "metric", x = 12, y = 0, width = 12, height = 6
        properties = {
          title = "Eventos derivados de logs (AndysMotors, por 5 min)", region = var.region,
          view = "timeSeries", stat = "Sum", period = 300
          metrics = [
            ["AndysMotors", "AgendamientosDescartados"],
            ["AndysMotors", "OportunidadesSinCliente"],
            ["AndysMotors", "PagosLentos"],
            ["AndysMotors", "ErroresAplicacion"]
          ]
        }
      },
      {
        type = "alarm", x = 0, y = 6, width = 24, height = 3
        properties = {
          title  = "Estado de las alarmas"
          alarms = [
            aws_cloudwatch_metric_alarm.agenda_silenciosa.arn,
            aws_cloudwatch_metric_alarm.pagos_lentos.arn,
            aws_cloudwatch_metric_alarm.costo_putmetricdata.arn
          ]
        }
      }
    ]
  })
}

resource "aws_cloudwatch_dashboard" "finops" {
  dashboard_name = "AndysMotors-FinOps"
  dashboard_body = jsonencode({
    widgets = [
      {
        type = "metric", x = 0, y = 0, width = 12, height = 7
        properties = {
          title  = "Costo simulado de PutMetricData (USD por 5 min) = (m1/1000)*0.01"
          region = var.region, view = "timeSeries", period = 300, stat = "Sum"
          metrics = [
            ["AWS/Usage", "CallCount", "Service", "CloudWatch", "Type", "API", "Resource", "PutMetricData", "Class", "None", { id = "m1", visible = false }],
            [{ expression = "(m1/1000)*0.01", label = "Costo PutMetricData (USD)", id = "e1" }]
          ]
          annotations = {
            horizontal = [{ label = "Umbral (Estimacion B + 50 %)", value = var.umbral_costo_usd }]
          }
        }
      },
      {
        type = "metric", x = 12, y = 0, width = 12, height = 7
        properties = {
          title  = "Llamadas PutMetricData por 5 min (AWS/Usage CallCount)"
          region = var.region, view = "timeSeries", period = 300, stat = "Sum"
          metrics = [local.usage_putmetricdata]
        }
      },
      {
        type = "metric", x = 0, y = 7, width = 12, height = 6
        properties = {
          title  = "Ingesta de logs (bytes por hora) por Log Group"
          region = var.region, view = "timeSeries", period = 3600, stat = "Sum"
          metrics = [
            ["AWS/Logs", "IncomingBytes", "LogGroupName", aws_cloudwatch_log_group.plataformas.name],
            ["AWS/Logs", "IncomingBytes", "LogGroupName", aws_cloudwatch_log_group.agente_debug.name]
          ]
        }
      },
      {
        type = "metric", x = 12, y = 7, width = 12, height = 6
        properties = {
          title  = "Costo de ingesta de logs (USD por hora) = (bytes/1e9)*0.50"
          region = var.region, view = "timeSeries", period = 3600, stat = "Sum"
          metrics = [
            ["AWS/Logs", "IncomingBytes", "LogGroupName", aws_cloudwatch_log_group.plataformas.name, { id = "l1", visible = false }],
            ["AWS/Logs", "IncomingBytes", "LogGroupName", aws_cloudwatch_log_group.agente_debug.name, { id = "l2", visible = false }],
            [{ expression = "((l1+l2)/1000000000)*0.50", label = "Ingesta de logs (USD)", id = "e2" }]
          ]
        }
      },
      {
        type = "alarm", x = 0, y = 13, width = 24, height = 3
        properties = {
          title  = "Alarma de presupuesto"
          alarms = [aws_cloudwatch_metric_alarm.costo_putmetricdata.arn]
        }
      }
    ]
  })
}
