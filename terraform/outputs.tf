output "instancia_id" {
  value = aws_instance.andys.id
}

output "ip_publica" {
  value = aws_instance.andys.public_ip
}

output "log_groups" {
  value = [aws_cloudwatch_log_group.plataformas.name, aws_cloudwatch_log_group.agente_debug.name]
}

output "topicos_sns" {
  value = [aws_sns_topic.alertas.arn, aws_sns_topic.finops.arn]
}

output "alarmas" {
  value = [
    aws_cloudwatch_metric_alarm.agenda_silenciosa.alarm_name,
    aws_cloudwatch_metric_alarm.pagos_lentos.alarm_name,
    aws_cloudwatch_metric_alarm.costo_putmetricdata.alarm_name
  ]
}

output "dashboards" {
  value = [
    aws_cloudwatch_dashboard.infraestructura.dashboard_name,
    aws_cloudwatch_dashboard.negocio.dashboard_name,
    aws_cloudwatch_dashboard.finops.dashboard_name
  ]
}

output "siguiente_paso" {
  value = "Confirma las 2 suscripciones SNS en tu correo. Espera ~5 min y conectate con EC2 Instance Connect: tail -f /var/log/andys-bootstrap.log"
}
