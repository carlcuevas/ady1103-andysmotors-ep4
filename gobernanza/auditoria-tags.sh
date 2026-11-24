#!/usr/bin/env bash
# =============================================================================
# AndysMotors EP4 - Auditoria de etiquetas con la Resource Groups Tagging API
# Ejecutar en AWS CloudShell (us-east-1):   bash auditoria-tags.sh
# =============================================================================
# 1. Consulta la Resource Groups Tagging API (get-resources) para obtener las
#    etiquetas de todos los recursos de la region.
# 2. Arma el inventario de recursos del caso con la CLI de cada servicio
#    (get-resources solo devuelve recursos que tienen o tuvieron etiquetas, por
#    eso un recurso nunca etiquetado no aparece en la API y hay que cruzarlo).
# 3. Valida cada recurso contra la taxonomia: 5 claves obligatorias y valores
#    permitidos. Resultado: CUMPLE / NO CUMPLE / NO ETIQUETABLE.
# =============================================================================
set -uo pipefail
REGION="${AWS_REGION:-us-east-1}"
export AWS_DEFAULT_REGION="$REGION"
SALIDA="auditoria-tags-$(date -u +%Y%m%dT%H%M%SZ).txt"

# --------------------------------------------------------------- taxonomia
TAXONOMIA='{
  "Entorno":        ["produccion","qa","desarrollo","laboratorio"],
  "Responsable":    ["equipo-sre","equipo-desarrollo","equipo-comercial","finanzas"],
  "CentroDeCostos": ["CC-1001","CC-1002","CC-2001","CC-3001"],
  "Proyecto":       ["andysmotors-observabilidad","andysmotors-plataforma","andysmotors-expansion"],
  "Plataforma":     ["web","stock","agenda","crm","pagos","gateway","transversal"]
}'

{
echo "=============================================================================="
echo " AUDITORIA DE ETIQUETAS - AndysMotors | Region: $REGION | $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
echo " Cuenta: $(aws sts get-caller-identity --query Account --output text 2>/dev/null)"
echo "=============================================================================="

# ---------------------------------------------- 1. Resource Groups Tagging API
echo
echo "[1] aws resourcegroupstaggingapi get-resources --tag-filters Key=CentroDeCostos"
echo "    (recursos que declaran un centro de costos)"
aws resourcegroupstaggingapi get-resources --tag-filters Key=CentroDeCostos \
  --query 'ResourceTagMappingList[].[ResourceARN, Tags[?Key==`CentroDeCostos`]|[0].Value]' \
  --output table

TAGS_JSON=$(aws resourcegroupstaggingapi get-resources --output json)

# ---------------------------------------------------- 2. inventario del caso
INSTANCIAS=$(aws ec2 describe-instances \
  --filters Name=instance-state-name,Values=pending,running,stopping,stopped \
  --query 'Reservations[].Instances[].InstanceId' --output text)
CUENTA=$(aws sts get-caller-identity --query Account --output text)

INVENTARIO=$(
  for i in $INSTANCIAS; do
    echo "ec2-instancia|arn:aws:ec2:$REGION:$CUENTA:instance/$i"
    for v in $(aws ec2 describe-volumes --filters Name=attachment.instance-id,Values="$i" \
               --query 'Volumes[].VolumeId' --output text); do
      echo "ec2-volumen|arn:aws:ec2:$REGION:$CUENTA:volume/$v"
    done
  done
  for a in $(aws logs describe-log-groups --log-group-name-prefix /andysmotors \
             --query 'logGroups[].arn' --output text); do
    echo "logs-log-group|${a%:\*}"
  done
  for t in $(aws sns list-topics --query 'Topics[].TopicArn' --output text | tr '\t' '\n' | grep -i andysmotors); do
    echo "sns-topico|$t"
  done
  for a in $(aws cloudwatch describe-alarms --alarm-name-prefix AndysMotors \
             --query 'MetricAlarms[].AlarmArn' --output text); do
    echo "cloudwatch-alarma|$a"
  done
  for d in $(aws cloudwatch list-dashboards --dashboard-name-prefix AndysMotors \
             --query 'DashboardEntries[].DashboardArn' --output text); do
    echo "cloudwatch-dashboard|$d"
  done
)

# ------------------------------------------------------ 3. validacion
echo
echo "[2] Cumplimiento de la taxonomia (5 claves obligatorias y valores permitidos)"
printf '%-22s %-62s %s\n' "TIPO" "RECURSO" "RESULTADO"
printf '%s\n' "------------------------------------------------------------------------------------------------------------"
CUMPLE=0; NOCUMPLE=0; NOETIQ=0
while IFS='|' read -r tipo arn; do
  [ -z "$arn" ] && continue
  case "$arn" in
    *:log-group:*) nombre="${arn#*:log-group:}" ;;
    *) nombre="${arn##*:}"; nombre="${nombre##*/}" ;;
  esac
  if [ "$tipo" = "cloudwatch-dashboard" ]; then
    printf '%-22s %-62s %s\n' "$tipo" "$nombre" "NO ETIQUETABLE (CloudWatch no admite tags en dashboards)"
    NOETIQ=$((NOETIQ+1)); continue
  fi
  resultado=$(echo "$TAGS_JSON" | jq -r --arg arn "$arn" --argjson tax "$TAXONOMIA" '
    ([.ResourceTagMappingList[] | select(.ResourceARN == $arn) | .Tags[]] | from_entries) as $t
    | [ $tax | to_entries[] | .key as $k | .value as $permitidos
        | if ($t[$k] == null) then "falta " + $k
          elif (($permitidos | index($t[$k])) == null) then $k + "=" + $t[$k] + " (valor no permitido)"
          else empty end ]
    | if length == 0 then "CUMPLE" else "NO CUMPLE: " + join(", ") end')
  printf '%-22s %-62s %s\n' "$tipo" "$nombre" "$resultado"
  case "$resultado" in CUMPLE) CUMPLE=$((CUMPLE+1));; *) NOCUMPLE=$((NOCUMPLE+1));; esac
done <<< "$INVENTARIO"

TOTAL=$((CUMPLE+NOCUMPLE+NOETIQ))
echo
echo "[3] Resumen: $TOTAL recursos | CUMPLE: $CUMPLE | NO CUMPLE: $NOCUMPLE | NO ETIQUETABLE: $NOETIQ"
if [ $((CUMPLE+NOCUMPLE)) -gt 0 ]; then
  echo "    Cobertura sobre recursos etiquetables: $(( 100 * CUMPLE / (CUMPLE+NOCUMPLE) )) %"
fi
} | tee "$SALIDA"

echo
echo "Reporte guardado en $SALIDA"
