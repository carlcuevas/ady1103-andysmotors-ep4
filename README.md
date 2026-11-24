# AndysMotors · EP4 ADY1103 · Auditoría FinOps de la observabilidad

Laboratorio automatizado de la Evaluación Parcial N°4 de *Monitoreo y Observabilidad* (ADY1103). Retoma el caso AndysMotors de la EP1, EP2 y EP3 y audita el **costo de su telemetría** en Amazon CloudWatch.

| Ruta | Qué es |
|---|---|
| `ep4.sh` | Orquestador: un comando por etapa del laboratorio |
| `terraform/` | EC2 con las 6 plataformas en Docker, CloudWatch Agent, 2 Log Groups, 5 filtros métricos, 2 tópicos SNS, 3 alarmas (incluida la de **costo** con Metric Math) y 3 dashboards |
| `inyector/` | `inyector-metricas.js` + `package.json`: métricas de negocio en `AndysMotors/Negocio` (AWS SDK v3, sin credenciales en el código) |
| `gobernanza/` | `etiquetar.sh`, `auditoria-tags.sh`, Tag Policy y SCP en JSON |
| `finops/` | `calculos_finops.py` (escenarios A y B + umbral) e `inventario-costos.sh` |

## Inicio rápido (AWS CloudShell, us-east-1)

```bash
git clone https://github.com/carlcuevas/ady1103-andysmotors-ep4.git
cd ady1103-andysmotors-ep4
./ep4.sh desplegar      # ~3 min. Luego confirma los 2 correos de SNS
./ep4.sh estado         # repetir hasta ver "LISTO" (8-10 min)
./ep4.sh etiquetar
./ep4.sh auditar
# ... esperar ~1 hora con el inyector corriendo ...
./ep4.sh inventario
./ep4.sh desvio         # 7 min; luego esperar 5-10 min
./ep4.sh alarma
./ep4.sh destruir       # solo cuando tengas TODAS las capturas
```

Lo que **no** se puede automatizar (y la pauta lo pide como evidencia de consola): capturas, pantalla de Tag Editor, intento de Cost Explorer y AWS Pricing Calculator. Abajo se indica cuándo hacer cada uno.

---

## Paso a paso con capturas

Guarda cada captura con su código (C01…C24): así se arma el informe.

### 1 · Despliegue

```bash
./ep4.sh desplegar
```
Confirma los 2 correos **AWS Notification – Subscription Confirmation** (`andysmotors-alertas` y `andysmotors-finops-alertas`). Después:
```bash
./ep4.sh estado
```
Cuando diga **LISTO**, la instancia ya levantó las plataformas, el agente, el generador de tráfico y el **inyector** (servicio `andys-inyector`, corre 4 h solo).

### 2 · Inyector de métricas (sección 3 del informe)

```bash
./ep4.sh inyector
cat inyector/package.json
grep -nE "AKIA|secretAccessKey|accessKeyId" inyector/inyector-metricas.js || echo "Sin llaves en el codigo"
```

| Captura | Qué mostrar |
|---|---|
| **C01** | `grep` sin llaves + `package.json` (credenciales por cadena por defecto del SDK / rol LabInstanceProfile) |
| **C02** | `./ep4.sh inyector`: líneas **"5 metricas en 1 llamada \| HTTP 200"** |
| **C03** | CloudWatch → Metrics → All metrics → **AndysMotors/Negocio → Plataforma**: las 5 métricas graficadas (Sum, 1 min, último 30–60 min) |
| **C04** | Dashboard **AndysMotors-Negocio** |

### 3 · Etiquetado (sección 4)

```bash
./ep4.sh etiquetar
```
Aplica la taxonomía con la Resource Groups Tagging API (la misma API de Tag Editor). Luego ve a la consola para la evidencia de Tag Editor:

1. **Resource Groups & Tag Editor → Tag Editor** · Region `us-east-1` · *All supported resource types* · **Search resources**.
2. En el engranaje de la tabla, activa las columnas `CentroDeCostos`, `Responsable` y `Plataforma`.
3. Selecciona 2–3 recursos → **Manage tags of selected resources** (no hace falta aplicar nada: ya están).

| Captura | Qué mostrar |
|---|---|
| **C05** | Tag Editor → *Manage tags* con las 5 claves |
| **C06** | Tag Editor → resultados con las columnas de etiquetas |
| **C07–C10** | Pestaña **Tags** de: EC2, Log Group `/andysmotors/plataformas`, SNS `andysmotors-finops-alertas`, alarma `AndysMotors-AgendaSilenciosa` |

**Taxonomía**

| Clave | Responde a | Valores permitidos |
|---|---|---|
| `Entorno` | ¿Etapa del ciclo de vida? | `produccion` `qa` `desarrollo` `laboratorio` |
| `Responsable` | ¿Qué equipo responde por el recurso y su gasto? | `equipo-sre` `equipo-desarrollo` `equipo-comercial` `finanzas` |
| `CentroDeCostos` | ¿A qué presupuesto se imputa? | `CC-1001` TI Observabilidad · `CC-1002` TI Plataformas · `CC-2001` Comercial · `CC-3001` Finanzas |
| `Proyecto` | ¿Qué iniciativa lo justifica? | `andysmotors-observabilidad` `andysmotors-plataforma` `andysmotors-expansion` |
| `Plataforma` *(propia)* | ¿Qué sistema del negocio sostiene? | `web` `stock` `agenda` `crm` `pagos` `gateway` `transversal` |

Claves en PascalCase sin tildes; valores en minúsculas con guiones; sin valores libres.

| Recurso | Responsable | CentroDeCostos | Proyecto | Plataforma |
|---|---|---|---|---|
| EC2 `andys-motors` + volumen EBS | equipo-desarrollo | CC-1002 | andysmotors-plataforma | transversal |
| Log Group `/andysmotors/plataformas` · SNS `andysmotors-alertas` | equipo-sre | CC-1001 | andysmotors-observabilidad | transversal |
| SNS `andysmotors-finops-alertas` · alarma de costo | finanzas | CC-3001 | andysmotors-observabilidad | transversal |
| Alarma `AgendaSilenciosa` / `PagosLentos` | equipo-sre | CC-1001 | andysmotors-observabilidad | agenda / pagos |
| Log Group `/andysmotors/agente-debug` | **sin etiquetas a propósito** (recurso huérfano y sin retención) | | | |
| 3 dashboards | **CloudWatch no admite etiquetas en dashboards** | | | |

Todos llevan `Entorno=laboratorio`.

### 4 · Auditoría por CLI

```bash
./ep4.sh auditar
cat gobernanza/tag-policy-andysmotors.json gobernanza/scp-exigir-centrodecostos.json
```

| Captura | Qué mostrar |
|---|---|
| **C11** | Tabla CUMPLE / NO CUMPLE / NO ETIQUETABLE y resumen de cobertura |

- La **Tag Policy** normaliza claves y valores, pero **no obliga** a que la etiqueta exista. Por eso se suma la **SCP**, que deniega `RunInstances`, `CreateVolume`, `CreateLogGroup` y `CreateTopic` sin `aws:RequestTag/CentroDeCostos` y protege la etiqueta de borrado (salvo el rol `FinOpsAdmin`).
- Las alarmas quedan fuera de la SCP: `PutMetricAlarm` también actualiza alarmas existentes y se bloquearían las modificaciones. Se controlan con la auditoría periódica.
- **Cost Allocation Tags (cuenta real):** Billing → *Cost allocation tags* → *User-defined* → activar las 5 claves desde la cuenta de administración. Tardan hasta 24 h y **no son retroactivas**.

### 5 · Costos (sección 5)

**Restricción de Billing**

| Captura | Qué mostrar |
|---|---|
| **C12** | Intento de abrir **Cost Explorer** → acceso denegado |
| **C13** | Intento de abrir **Billing → Cost allocation tags** → acceso denegado |

Configuración de Cost Explorer a documentar: últimos 3 meses + pronóstico · granularidad diaria (picos) y mensual (gerencia) · filtros *Service* = CloudWatch, *Tag* `Proyecto` = `andysmotors-observabilidad`, *Region* = us-east-1 · agrupar por **Usage type** (`CW:MetricMonitorUsage`, `CW:Requests`, `DataProcessing-Bytes`, `TimedStorage-ByteHrs`, `DashboardsUsageHour`, `CW:AlarmMonitorUsage`) y luego por **Tag: CentroDeCostos** / **Tag: Plataforma** · guardar como reporte + AWS Budget con alertas al 80 % y 100 %.

**Gráfico de costo con AWS/Usage + Metric Math** (hazlo a mano en la consola para la evidencia): CloudWatch → Metrics → All metrics → **Usage → By AWS Resource** → `CloudWatch / API / PutMetricData / None` → **CallCount** · *Graphed metrics*: Sum, 5 minutes → **Add math → Start with empty expression** → `(m1/1000)*0.01` → ocultar `m1`.

| Captura | Qué mostrar |
|---|---|
| **C14** | *Graphed metrics* con `m1` y `e1 = (m1/1000)*0.01` |
| **C15** | Dashboard **AndysMotors-FinOps** completo |

**Inventario** (con 1–2 h de datos):
```bash
./ep4.sh inventario
```

| Captura | Qué mostrar |
|---|---|
| **C16** | Salida del inventario con costo mensual por componente |

### 6 · AWS Pricing Calculator (sección 6)

```bash
./ep4.sh calcular
```

[calculator.aws](https://calculator.aws) → *Create estimate* → **Amazon CloudWatch** → US East (N. Virginia). Dos estimaciones:

| Campo | A (propuesto) | B (optimizado) |
|---|---|---|
| Number of metrics (custom) | 600 | 150 |
| API requests (PutMetricData) | 155.520.000 | 1.296.000 |
| Standard logs – data ingested (GB) | 1.350 | 405 |
| Logs storage/archival (GB) | 1.350 | 405 |
| Dashboards | 8 | 3 |
| Standard resolution alarm metrics | 25 | 20 |
| High resolution alarm metrics | 5 | 0 |

Esperado: **A ≈ USD 2.478,70/mes** (USD 2.924,20 al mes 12 por logs que nunca expiran) · **B ≈ USD 283,61/mes** · **ahorro 88,6 %**. Si la calculadora aplica capa gratuita o su propia compresión de logs, usa sus cifras y explica la diferencia.

Guarda cada una → **Share** (enlace) y **Export → PDF**.

| Captura | Qué mostrar |
|---|---|
| **C17 / C18** | Resumen de la estimación A / B |

### 7 · Alarma de costo y desvío controlado (sección 7)

Umbral: B = 30 instancias × 1 llamada/min = **150 llamadas cada 5 min → USD 0,0015** · +50 % de margen → **USD 0,00225**.

```bash
./ep4.sh desvio      # 7 min enviando 1 métrica por llamada (patrón del Escenario A)
# esperar 5-10 min
./ep4.sh alarma
```

| Captura | Qué mostrar |
|---|---|
| **C19** | Salida de `./ep4.sh desvio` (HTTP 200 por llamada) |
| **C20** | Alarma `AndysMotors-FinOps-CostoPutMetricData` en **ALARM** con la línea del umbral |
| **C21** | Configuración de la alarma (expresión `e1`, umbral, período 5 min, acción SNS) |
| **C22** | Correo **ALARM** de `andysmotors-finops-alertas` |
| **C23** | (Opcional) correo de vuelta a **OK** + `./ep4.sh alarma` con el historial |
| **C24** | Dashboard FinOps con el pico del desvío |

### 8 · Cierre

```bash
./ep4.sh destruir
```

Entregables: informe .docx · `inyector/inyector-metricas.js` · `inyector/package.json` · 2 enlaces o PDF de Pricing Calculator · presentación (máx. 8 láminas).

## Problemas frecuentes

| Síntoma | Solución |
|---|---|
| `estado` no dice LISTO a los 15 min | EC2 → Connect → Instance Connect → `sudo tail -n 30 /var/log/andys-bootstrap.log` |
| No aparece `Usage` en CloudWatch Metrics | Las métricas de uso tardan unos minutos; amplía el rango a 3 h |
| La alarma queda en *Insufficient data* | Normal sin llamadas recientes (`treat_missing_data = notBreaching` la deja en OK al primer dato) |
| Se cerró la sesión del Learner Lab | Vuelve a iniciar el lab: la instancia queda detenida; `./ep4.sh estado` y arráncala desde EC2 si hace falta (el inyector no se reinicia solo: `sudo systemctl start andys-inyector`) |
