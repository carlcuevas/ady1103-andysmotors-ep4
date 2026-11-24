# =============================================================================
# Logs, filtros metricos, SNS y alarmas (continuidad EP3 + alarma de costo EP4)
# Ningun recurso trae etiquetas de negocio: se etiquetan con Tag Editor.
# =============================================================================

# ----------------------------------------------------------------- Log Groups
resource "aws_cloudwatch_log_group" "plataformas" {
  name              = "/andysmotors/plataformas"
  retention_in_days = 7

  lifecycle {
    ignore_changes = [tags, tags_all]
  }
}

# Log Group "de depuracion" creado sin politica de retencion (Nunca expira).
# Representa un hallazgo tipico de la auditoria: logs que crecen sin limite.
resource "aws_cloudwatch_log_group" "agente_debug" {
  name = "/andysmotors/agente-debug"

  lifecycle {
    ignore_changes = [tags, tags_all, retention_in_days]
  }
}

# ---------------------------------------------------- filtros metricos (EP3)
locals {
  filtros = {
    AgendamientosDescartados = "{ $.mensaje = \"agendamiento descartado sin persistir\" }"
    OportunidadesSinCliente  = "{ $.mensaje = \"oportunidad creada sin cliente asociado\" }"
    PagosRechazados          = "{ ($.servicio = \"pagos\") && ($.status = 402) }"
    PagosLentos              = "{ ($.servicio = \"pagos\") && ($.duracion_ms > 3000) }"
    ErroresAplicacion        = "{ $.nivel = \"error\" }"
  }
}

resource "aws_cloudwatch_log_metric_filter" "negocio" {
  for_each       = local.filtros
  name           = "andysmotors-${each.key}"
  log_group_name = aws_cloudwatch_log_group.plataformas.name
  pattern        = each.value

  metric_transformation {
    name          = each.key
    namespace     = "AndysMotors"
    value         = "1"
    default_value = "0"
  }
}

# ------------------------------------------------------------------- SNS
resource "aws_sns_topic" "alertas" {
  name = "andysmotors-alertas"

  lifecycle {
    ignore_changes = [tags, tags_all]
  }
}

resource "aws_sns_topic_subscription" "alertas_correo" {
  topic_arn = aws_sns_topic.alertas.arn
  protocol  = "email"
  endpoint  = var.correo_alertas
}

# Topico separado para Finanzas: el dueno del gasto recibe la alerta de costo.
resource "aws_sns_topic" "finops" {
  name = "andysmotors-finops-alertas"

  lifecycle {
    ignore_changes = [tags, tags_all]
  }
}

resource "aws_sns_topic_subscription" "finops_correo" {
  topic_arn = aws_sns_topic.finops.arn
  protocol  = "email"
  endpoint  = var.correo_alertas
}

# ------------------------------------------------- alarmas operativas (EP3)
resource "aws_cloudwatch_metric_alarm" "agenda_silenciosa" {
  alarm_name          = "AndysMotors-AgendaSilenciosa"
  alarm_description   = "Agendamientos confirmados al cliente pero no persistidos (falla silenciosa)."
  namespace           = "AndysMotors"
  metric_name         = "AgendamientosDescartados"
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  datapoints_to_alarm = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alertas.arn]

  lifecycle {
    ignore_changes = [tags, tags_all]
  }
}

resource "aws_cloudwatch_metric_alarm" "pagos_lentos" {
  alarm_name          = "AndysMotors-PagosLentos"
  alarm_description   = "Cinco o mas pagos sobre 3000 ms en 5 minutos."
  namespace           = "AndysMotors"
  metric_name         = "PagosLentos"
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  datapoints_to_alarm = 1
  threshold           = 5
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alertas.arn]

  lifecycle {
    ignore_changes = [tags, tags_all]
  }
}

# ------------------------------------------- alarma de presupuesto (EP4)
# Costo simulado de la API: (CallCount de PutMetricData / 1000) x USD 0,01
resource "aws_cloudwatch_metric_alarm" "costo_putmetricdata" {
  alarm_name          = "AndysMotors-FinOps-CostoPutMetricData"
  alarm_description   = "Costo de PutMetricData por 5 min sobre lo esperado en la Estimacion B (USD 0,0015) + 50 % de margen."
  comparison_operator = "GreaterThanThreshold"
  threshold           = var.umbral_costo_usd
  evaluation_periods  = 1
  datapoints_to_alarm = 1
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.finops.arn]
  ok_actions          = [aws_sns_topic.finops.arn]

  metric_query {
    id          = "e1"
    expression  = "(m1/1000)*0.01"
    label       = "Costo PutMetricData (USD por 5 min)"
    return_data = true
  }

  metric_query {
    id = "m1"
    metric {
      namespace   = "AWS/Usage"
      metric_name = "CallCount"
      period      = 300
      stat        = "Sum"
      dimensions = {
        Service  = "CloudWatch"
        Type     = "API"
        Resource = "PutMetricData"
        Class    = "None"
      }
    }
  }

  lifecycle {
    ignore_changes = [tags, tags_all]
  }
}
