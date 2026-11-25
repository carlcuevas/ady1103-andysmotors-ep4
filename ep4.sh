#!/usr/bin/env bash
# =============================================================================
# AndysMotors EP4 (ADY1103) - Orquestador del laboratorio FinOps
# Ejecutar en AWS CloudShell (us-east-1) desde la raiz del repositorio.
#   ./ep4.sh <comando>        (./ep4.sh ayuda para ver la lista)
# =============================================================================
set -uo pipefail
RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export AWS_DEFAULT_REGION="${AWS_REGION:-us-east-1}"
export PATH="$HOME/bin:$PATH"
# El home de CloudShell tiene solo 1 GB y el proveedor AWS de Terraform pesa
# ~700 MB: los plugins se guardan en /tmp (el estado sigue en terraform/).
export TF_DATA_DIR="/tmp/andysmotors-ep4-tf"
LG_DEBUG="/andysmotors/agente-debug"
ALARMA_COSTO="AndysMotors-FinOps-CostoPutMetricData"

titulo() { echo; echo "==== $* ===="; }

asegurar_terraform() {
  if ! command -v terraform >/dev/null 2>&1; then
    titulo "Instalando Terraform 1.10.5 en ~/bin"
    mkdir -p "$HOME/bin"
    curl -fsSL -o /tmp/tf.zip https://releases.hashicorp.com/terraform/1.10.5/terraform_1.10.5_linux_amd64.zip
    unzip -oq /tmp/tf.zip -d "$HOME/bin" && rm -f /tmp/tf.zip
  fi
  terraform -version | head -1
}

cmd_desplegar() {
  asegurar_terraform
  titulo "Desplegando infraestructura (terraform apply)"
  cd "$RAIZ/terraform" || exit 1
  terraform init -input=false || { echo "ERROR: fallo terraform init"; exit 1; }
  terraform apply -auto-approve -input=false || { echo "ERROR: fallo terraform apply"; exit 1; }
  echo
  echo ">> Confirma los 2 correos 'AWS Notification - Subscription Confirmation'."
  echo ">> En 8-10 minutos corre: ./ep4.sh estado"
}

cmd_estado() {
  titulo "Instancia"
  aws ec2 describe-instances --filters Name=tag:Name,Values=andys-motors \
    --query 'Reservations[].Instances[].[InstanceId,State.Name,InstanceType,PublicIpAddress]' --output table
  titulo "Arranque (user data)"
  if aws logs filter-log-events --log-group-name "$LG_DEBUG" --log-stream-names bootstrap \
       --filter-pattern '"ANDYS-EP4 LISTO"' --query 'events[0].message' --output text 2>/dev/null | grep -q LISTO; then
    echo "LISTO: plataformas, agente e inyector en marcha"
  else
    echo "Aun instalando (o el agente todavia no envia el log). Reintenta en 2-3 minutos."
  fi
  titulo "Suscripciones SNS"
  for t in andysmotors-alertas andysmotors-finops-alertas; do
    arn="arn:aws:sns:$AWS_DEFAULT_REGION:$(aws sts get-caller-identity --query Account --output text):$t"
    aws sns list-subscriptions-by-topic --topic-arn "$arn" \
      --query 'Subscriptions[].[`'"$t"'`,Endpoint,SubscriptionArn]' --output text 2>/dev/null
  done
  echo "(PendingConfirmation = falta confirmar el correo)"
  titulo "Ultimas lineas del inyector"
  aws logs tail "$LG_DEBUG" --log-stream-names inyector --since 10m 2>/dev/null | tail -n 5 \
    || echo "Sin datos aun"
}

cmd_inyector() {
  titulo "Salida del inyector en EC2 (CloudWatch Logs: $LG_DEBUG / inyector)"
  aws logs tail "$LG_DEBUG" --log-stream-names inyector --since "${1:-30m}"
}

cmd_etiquetar() { bash "$RAIZ/gobernanza/etiquetar.sh"; }
cmd_auditar()   { cd "$RAIZ/gobernanza" && bash auditoria-tags.sh; }
cmd_inventario(){ cd "$RAIZ/finops" && bash inventario-costos.sh; }
cmd_calcular()  { python3 "$RAIZ/finops/calculos_finops.py"; }

cmd_desvio() {
  titulo "Desvio controlado de costo: modo anti-patron (1 metrica por llamada) por 7 minutos"
  cd "$RAIZ/inyector"
  [ -d node_modules ] || npm install --no-audit --no-fund --silent
  node inyector-metricas.js --modo desvio --duracion "${1:-420}"
  echo
  echo ">> La alarma evalua periodos de 5 min: espera 5-10 min y corre ./ep4.sh alarma"
}

cmd_alarma() {
  titulo "Estado de la alarma de presupuesto"
  aws cloudwatch describe-alarms --alarm-names "$ALARMA_COSTO" \
    --query 'MetricAlarms[].[AlarmName,StateValue,Threshold,StateReason]' --output table
  titulo "Historial de cambios de estado"
  aws cloudwatch describe-alarm-history --alarm-name "$ALARMA_COSTO" --history-item-type StateUpdate \
    --query 'AlarmHistoryItems[].[Timestamp,HistorySummary]' --output table
}

cmd_destruir() {
  asegurar_terraform
  titulo "Eliminando infraestructura (terraform destroy)"
  cd "$RAIZ/terraform" || exit 1
  terraform init -input=false >/dev/null || { echo "ERROR: fallo terraform init"; exit 1; }
  terraform destroy -auto-approve -input=false
}

cmd_ayuda() {
  cat <<'TXT'
Uso: ./ep4.sh <comando>

  desplegar   Instala Terraform si falta y levanta todo (EC2, logs, SNS, alarmas, dashboards).
              El inyector de metricas arranca solo en la EC2 y corre 4 horas.
  estado      Muestra si la instancia termino de instalar, las suscripciones SNS y el inyector.
  inyector    Muestra la salida del inyector (lineas con HTTP 200). Opcional: ventana, ej. 60m.
  etiquetar   Aplica la taxonomia de etiquetas (deja agente-debug sin etiquetar a proposito).
  auditar     Auditoria de cumplimiento con la Resource Groups Tagging API.
  calcular    Escenarios A y B y el umbral de la alarma (no usa AWS).
  inventario  Inventario de costos real del laboratorio (ideal con 1-2 h de datos).
  desvio      Provoca el desvio de costo durante 7 min para disparar la alarma.
  alarma      Estado e historial de la alarma de presupuesto.
  destruir    Elimina toda la infraestructura (terraform destroy).

Orden sugerido: desplegar -> (confirmar correos) -> estado -> etiquetar -> auditar
                -> [esperar 1 h] -> inventario -> desvio -> alarma -> destruir
TXT
}

case "${1:-ayuda}" in
  desplegar|estado|inyector|etiquetar|auditar|calcular|inventario|desvio|alarma|destruir|ayuda)
    c="$1"; shift || true; "cmd_$c" "$@" ;;
  *) echo "Comando desconocido: $1"; cmd_ayuda; exit 1 ;;
esac
