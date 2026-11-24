#!/usr/bin/env bash
# =============================================================================
# AndysMotors EP4 - Inventario de costos de la observabilidad (laboratorio)
# Ejecutar en AWS CloudShell (us-east-1):   bash inventario-costos.sh
# Cuantifica con precios de lista: series personalizadas activas, llamadas
# PutMetricData (ultimas 24 h proyectadas a 30 dias), GB de logs ingeridos y
# almacenados con su retencion, dashboards y alarmas. Precios sin capa gratuita.
# =============================================================================
set -uo pipefail
export AWS_DEFAULT_REGION="${AWS_REGION:-us-east-1}"
SALIDA="inventario-costos-$(date -u +%Y%m%dT%H%M%SZ).txt"
INICIO=$(date -u -d '24 hours ago' +%Y-%m-%dT%H:%M:%SZ)
FIN=$(date -u +%Y-%m-%dT%H:%M:%SZ)

{
echo "=============================================================================="
echo " INVENTARIO DE COSTOS DE OBSERVABILIDAD - AndysMotors | $(date -u '+%Y-%m-%d %H:%M UTC')"
echo " Ventana de uso medida: $INICIO -> $FIN (proyectada a 30 dias)"
echo "=============================================================================="

# --------------------------------------------------- metricas personalizadas
echo
echo "[1] Series de metricas personalizadas (USD 0,30 por serie-mes)"
TOTAL_SERIES=0
for ns in "AndysMotors/Negocio" "AndysMotors" "CWAgent"; do
  n=$(aws cloudwatch list-metrics --namespace "$ns" --recently-active PT3H --query 'length(Metrics)' --output text)
  [ "$n" = "None" ] && n=0
  printf '    %-24s %4s series\n' "$ns" "$n"
  TOTAL_SERIES=$((TOTAL_SERIES + n))
done
C_METRICAS=$(awk -v n="$TOTAL_SERIES" 'BEGIN{printf "%.2f", n*0.30}')
echo "    Total: $TOTAL_SERIES series -> USD $C_METRICAS / mes"

# ------------------------------------------------------- API PutMetricData
echo
echo "[2] Llamadas PutMetricData (AWS/Usage CallCount, USD 0,01 por 1.000)"
LLAMADAS=$(aws cloudwatch get-metric-statistics --namespace AWS/Usage --metric-name CallCount \
  --dimensions Name=Service,Value=CloudWatch Name=Type,Value=API Name=Resource,Value=PutMetricData Name=Class,Value=None \
  --start-time "$INICIO" --end-time "$FIN" --period 86400 --statistics Sum \
  --query 'sum(Datapoints[].Sum)' --output text)
[ "$LLAMADAS" = "None" ] && LLAMADAS=0
C_API=$(awk -v l="$LLAMADAS" 'BEGIN{printf "%.4f", l*30/1000*0.01}')
echo "    Ultimas 24 h: $LLAMADAS llamadas -> proyeccion 30 dias: USD $C_API / mes"

# ------------------------------------------------------------------ logs
echo
echo "[3] Log Groups (ingesta USD 0,50/GB | almacenamiento USD 0,03/GB-mes)"
printf '    %-30s %-12s %14s %16s\n' "LOG GROUP" "RETENCION" "ALMACENADO(MB)" "INGESTA 24h(MB)"
C_LOGS=0
while read -r nombre retencion bytes; do
  [ -z "$nombre" ] && continue
  [ "$retencion" = "None" ] && retencion="Nunca expira" || retencion="$retencion dias"
  ing=$(aws cloudwatch get-metric-statistics --namespace AWS/Logs --metric-name IncomingBytes \
    --dimensions Name=LogGroupName,Value="$nombre" --start-time "$INICIO" --end-time "$FIN" \
    --period 86400 --statistics Sum --query 'sum(Datapoints[].Sum)' --output text)
  [ "$ing" = "None" ] && ing=0
  printf '    %-30s %-12s %14.2f %16.2f\n' "$nombre" "$retencion" \
    "$(awk -v b="$bytes" 'BEGIN{print b/1048576}')" "$(awk -v b="$ing" 'BEGIN{print b/1048576}')"
  C_LOGS=$(awk -v c="$C_LOGS" -v i="$ing" -v s="$bytes" 'BEGIN{printf "%.4f", c + (i*30/1e9)*0.50 + (s/1e9)*0.03}')
done < <(aws logs describe-log-groups --log-group-name-prefix /andysmotors \
          --query 'logGroups[].[logGroupName, retentionInDays, storedBytes]' --output text)
echo "    Logs (ingesta proyectada 30 dias + almacenamiento actual): USD $C_LOGS / mes"

# ---------------------------------------------------- dashboards y alarmas
echo
echo "[4] Dashboards (USD 3,00 c/u) y alarmas (USD 0,10 estandar | USD 0,30 alta resolucion)"
DASH=$(aws cloudwatch list-dashboards --query 'length(DashboardEntries)' --output text)
ALARMAS=$(aws cloudwatch describe-alarms --query 'MetricAlarms[].[AlarmName, Period]' --output text)
STD=0; HR=0
while read -r nombre periodo; do
  [ -z "$nombre" ] && continue
  if [ "$periodo" != "None" ] && [ "$periodo" -lt 60 ] 2>/dev/null; then HR=$((HR+1)); else STD=$((STD+1)); fi
  echo "    alarma: $nombre"
done <<< "$ALARMAS"
C_DASH=$(awk -v d="$DASH" 'BEGIN{printf "%.2f", d*3}')
C_ALARM=$(awk -v s="$STD" -v h="$HR" 'BEGIN{printf "%.2f", s*0.10 + h*0.30}')
echo "    Dashboards: $DASH -> USD $C_DASH / mes | Alarmas: $STD estandar + $HR alta resolucion -> USD $C_ALARM / mes"

# ---------------------------------------------------------------- total
TOTAL=$(awk -v a="$C_METRICAS" -v b="$C_API" -v c="$C_LOGS" -v d="$C_DASH" -v e="$C_ALARM" 'BEGIN{printf "%.2f", a+b+c+d+e}')
echo
echo "=============================================================================="
echo " COSTO MENSUAL ESTIMADO DE LA OBSERVABILIDAD DEL LABORATORIO: USD $TOTAL"
echo "   metricas $C_METRICAS | API $C_API | logs $C_LOGS | dashboards $C_DASH | alarmas $C_ALARM"
echo "=============================================================================="
} | tee "$SALIDA"
echo "Reporte guardado en $SALIDA"
