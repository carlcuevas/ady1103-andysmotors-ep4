#!/usr/bin/env bash
# =============================================================================
# AndysMotors EP4 - Etiquetado segun la taxonomia (Resource Groups Tagging API)
# Usa la misma API que Tag Editor (tag-resources). Deja SIN etiquetar a
# proposito el Log Group /andysmotors/agente-debug (hallazgo de la auditoria).
# Ejecutar en CloudShell:   bash etiquetar.sh
# =============================================================================
set -euo pipefail
REGION="${AWS_REGION:-us-east-1}"
export AWS_DEFAULT_REGION="$REGION"
CUENTA=$(aws sts get-caller-identity --query Account --output text)

etiquetar() {  # $1 = descripcion, $2 = Responsable, $3 = CentroDeCostos, $4 = Proyecto, $5 = Plataforma, resto = ARNs
  local desc="$1" resp="$2" cc="$3" proy="$4" plat="$5"; shift 5
  [ "$#" -eq 0 ] && { echo "  (sin recursos para: $desc)"; return; }
  echo "  -> $desc: $resp | $cc | $proy | $plat"
  aws resourcegroupstaggingapi tag-resources --resource-arn-list "$@" \
    --tags "Entorno=laboratorio,Responsable=$resp,CentroDeCostos=$cc,Proyecto=$proy,Plataforma=$plat" \
    --query 'FailedResourcesMap' --output json
}

INSTANCIA=$(aws ec2 describe-instances \
  --filters Name=tag:Name,Values=andys-motors Name=instance-state-name,Values=pending,running,stopped \
  --query 'Reservations[].Instances[].InstanceId' --output text)
ARN_EC2=()
for i in $INSTANCIA; do
  ARN_EC2+=("arn:aws:ec2:$REGION:$CUENTA:instance/$i")
  for v in $(aws ec2 describe-volumes --filters Name=attachment.instance-id,Values="$i" --query 'Volumes[].VolumeId' --output text); do
    ARN_EC2+=("arn:aws:ec2:$REGION:$CUENTA:volume/$v")
  done
done

LG="arn:aws:logs:$REGION:$CUENTA:log-group:/andysmotors/plataformas"
SNS_OPS="arn:aws:sns:$REGION:$CUENTA:andysmotors-alertas"
SNS_FIN="arn:aws:sns:$REGION:$CUENTA:andysmotors-finops-alertas"
ALARMA() { echo "arn:aws:cloudwatch:$REGION:$CUENTA:alarm:$1"; }

echo "Etiquetando recursos de AndysMotors en $REGION (cuenta $CUENTA)"
etiquetar "EC2 y volumen EBS" equipo-desarrollo CC-1002 andysmotors-plataforma transversal "${ARN_EC2[@]}"
etiquetar "Log Group y SNS operativo" equipo-sre CC-1001 andysmotors-observabilidad transversal "$LG" "$SNS_OPS"
etiquetar "SNS de Finanzas y alarma de costo" finanzas CC-3001 andysmotors-observabilidad transversal \
  "$SNS_FIN" "$(ALARMA AndysMotors-FinOps-CostoPutMetricData)"
etiquetar "Alarma de agenda" equipo-sre CC-1001 andysmotors-observabilidad agenda "$(ALARMA AndysMotors-AgendaSilenciosa)"
etiquetar "Alarma de pagos" equipo-sre CC-1001 andysmotors-observabilidad pagos "$(ALARMA AndysMotors-PagosLentos)"
echo "Listo. /andysmotors/agente-debug queda sin etiquetas a proposito y los dashboards no admiten etiquetas."
echo "Un FailedResourcesMap vacio ({}) significa que todo se etiqueto bien."
