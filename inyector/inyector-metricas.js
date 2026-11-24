#!/usr/bin/env node
// =============================================================================
// AndysMotors - Inyector de metricas de negocio (EP4 - ADY1103)
// Rol: Consultor SRE - Auditoria FinOps de la telemetria
// =============================================================================
// Publica metricas de negocio de AndysMotors en el namespace propio
// "AndysMotors/Negocio" usando AWS SDK for JavaScript v3.
//
// SEGURIDAD: este archivo NO contiene llaves de acceso. El cliente usa la
// cadena de credenciales por defecto del SDK (default credential provider
// chain): en AWS CloudShell toma la sesion de la consola y en EC2 toma el
// rol del perfil de instancia LabInstanceProfile (servicio de metadatos IMDS).
//
// DISENO COSTO-EFICIENTE
//   - Batching: todas las metricas de un intervalo viajan en UNA sola llamada
//     PutMetricData (la API acepta hasta 1.000 datos por llamada). El costo de
//     la API se cobra por llamada, no por dato: 5 metricas en 1 llamada cuestan
//     lo mismo que 1 metrica en 1 llamada.
//   - Baja cardinalidad: una sola dimension, Plataforma, con valores fijos
//     (agenda, crm, pagos). No se usa InstanceId, sucursal, cliente ni
//     request_id como dimension: cada combinacion distinta de dimensiones es
//     una serie nueva que se cobra como metrica personalizada al mes. El
//     analisis por sucursal se hace en Logs Insights (EP3), que cobra por
//     consulta y no por serie.
//   - Frecuencia de 60 s (resolucion estandar): entrega 5 puntos por cada
//     ventana de 5 minutos y 15 por cada ventana de 15 minutos, las ventanas
//     de los umbrales de alerta de la EP1 (secciones 4.1 a 4.3).
//   - Pre-agregacion: la latencia de pagos se envia como StatisticValues
//     (SampleCount, Sum, Minimum, Maximum) de todo el intervalo, no como un
//     dato por transaccion.
//
// MODOS
//   normal : comportamiento costo-eficiente descrito arriba (1 llamada/intervalo).
//   desvio : reproduce el anti-patron del Escenario A (una metrica por llamada
//            y alta frecuencia). Sirve SOLO para provocar el desvio controlado
//            de costo que dispara la alarma de presupuesto (seccion 7).
//
// USO
//   node inyector-metricas.js                                  # normal, 60 min
//   node inyector-metricas.js --duracion 1800 --hora-inicio 9  # 30 min desde las 09:00
//   node inyector-metricas.js --modo desvio --duracion 420     # desvio de 7 min
//   node inyector-metricas.js --simular                        # sin enviar a AWS
// =============================================================================

import { CloudWatchClient, PutMetricDataCommand } from "@aws-sdk/client-cloudwatch";

// ----------------------------------------------------------------- parametros
function leerArgumentos(argv) {
  const opciones = {
    modo: "normal",          // normal | desvio
    intervalo: null,         // segundos entre envios (60 normal, 1 desvio)
    duracion: null,          // segundos totales (3600 normal, 420 desvio)
    horaInicio: 9,           // hora simulada inicial (09:00 = horario comercial)
    factor: 1,               // 1 = reloj real; 60 = 1 minuto real es 1 hora simulada
    region: process.env.AWS_REGION || process.env.AWS_DEFAULT_REGION || "us-east-1",
    namespace: "AndysMotors/Negocio",
    simular: false,          // true = no llama a AWS (prueba local)
  };
  for (let i = 2; i < argv.length; i++) {
    const clave = argv[i];
    const valor = argv[i + 1];
    switch (clave) {
      case "--modo": opciones.modo = valor; i++; break;
      case "--intervalo": opciones.intervalo = Number(valor); i++; break;
      case "--duracion": opciones.duracion = Number(valor); i++; break;
      case "--hora-inicio": opciones.horaInicio = Number(valor); i++; break;
      case "--factor": opciones.factor = Number(valor); i++; break;
      case "--region": opciones.region = valor; i++; break;
      case "--namespace": opciones.namespace = valor; i++; break;
      case "--simular": opciones.simular = true; break;
      case "--ayuda": case "-h": case "--help":
        console.log("Uso: node inyector-metricas.js [--modo normal|desvio] [--intervalo s] " +
          "[--duracion s] [--hora-inicio h] [--factor f] [--region r] [--simular]");
        process.exit(0);
      default:
        console.error(`Argumento desconocido: ${clave}`);
        process.exit(1);
    }
  }
  if (!["normal", "desvio"].includes(opciones.modo)) {
    console.error("--modo debe ser 'normal' o 'desvio'");
    process.exit(1);
  }
  if (opciones.intervalo === null) opciones.intervalo = opciones.modo === "normal" ? 60 : 1;
  if (opciones.duracion === null) opciones.duracion = opciones.modo === "normal" ? 3600 : 420;
  return opciones;
}

// ------------------------------------------------ curva horaria del caso (EP1)
// 02-06 nulo, 06-09 creciente, 09-19 maximo, 19-22 medio, 22-02 bajo.
function factorHorario(hora) {
  if (hora >= 2 && hora < 6) return 0.02;
  if (hora >= 6 && hora < 9) return 0.15 + ((hora - 6) / 3) * 0.6;
  if (hora >= 9 && hora < 19) return 1.0;
  if (hora >= 19 && hora < 22) return 0.45;
  return 0.12;
}

// CRM y pagos solo tienen actividad relevante en horario de sucursales.
function esHorarioComercial(hora) {
  return hora >= 9 && hora < 19;
}

// Conteo aleatorio con media "media" (aproximacion de Poisson).
function conteoAleatorio(media) {
  if (media <= 0) return 0;
  const desviacion = Math.sqrt(media);
  const valor = Math.round(media + desviacion * (Math.random() * 2 - 1));
  return Math.max(0, valor);
}

// ------------------------------------- telemetria de negocio de un intervalo
// Medias por minuto en horario peak, escaladas por el intervalo y la hora.
function generarIntervalo(hora, segundosIntervalo) {
  const escala = (segundosIntervalo / 60) * factorHorario(hora);
  const comercial = esHorarioComercial(hora);

  const agendamientos = conteoAleatorio(6 * escala);
  const oportunidades = comercial ? conteoAleatorio(3 * escala) : 0;
  const pagos = comercial ? conteoAleatorio(2 * escala) : 0;
  // ~1 % de rechazo base del proveedor externo (guia del caso).
  let rechazados = 0;
  for (let i = 0; i < pagos; i++) if (Math.random() < 0.01) rechazados++;

  // Latencia de autorizacion de pagos pre-agregada (ms).
  const muestras = [];
  for (let i = 0; i < pagos; i++) muestras.push(Math.round(350 + Math.random() * 900));
  const latencia = muestras.length
    ? {
        SampleCount: muestras.length,
        Sum: muestras.reduce((a, b) => a + b, 0),
        Minimum: Math.min(...muestras),
        Maximum: Math.max(...muestras),
      }
    : null;

  return { agendamientos, oportunidades, pagos, rechazados, latencia };
}

// Construye los datos (MetricData). Dimension unica: Plataforma.
function construirMetricData(datos, marcaTiempo) {
  const dim = (plataforma) => [{ Name: "Plataforma", Value: plataforma }];
  const lista = [
    { MetricName: "AgendamientosRegistrados", Dimensions: dim("agenda"), Unit: "Count", Value: datos.agendamientos },
    { MetricName: "OportunidadesCreadas", Dimensions: dim("crm"), Unit: "Count", Value: datos.oportunidades },
    { MetricName: "PagosProcesados", Dimensions: dim("pagos"), Unit: "Count", Value: datos.pagos },
    { MetricName: "PagosRechazados", Dimensions: dim("pagos"), Unit: "Count", Value: datos.rechazados },
  ];
  if (datos.latencia) {
    lista.push({
      MetricName: "LatenciaAutorizacionPago",
      Dimensions: dim("pagos"),
      Unit: "Milliseconds",
      StatisticValues: datos.latencia,
    });
  }
  return lista.map((m) => ({ ...m, Timestamp: marcaTiempo, StorageResolution: 60 }));
}

// ----------------------------------------------------------------- utilidades
const pausa = (ms) => new Promise((r) => setTimeout(r, ms));
const dosDigitos = (n) => String(n).padStart(2, "0");
function horaTexto(hora) {
  const h = Math.floor(hora) % 24;
  const m = Math.floor((hora - Math.floor(hora)) * 60);
  return `${dosDigitos(h)}:${dosDigitos(m)}`;
}

// ---------------------------------------------------------------- principal
async function main() {
  const op = leerArgumentos(process.argv);
  const cliente = op.simular ? null : new CloudWatchClient({ region: op.region });

  console.log("=".repeat(78));
  console.log("AndysMotors - inyector de metricas de negocio (AWS SDK v3)");
  console.log(`Namespace: ${op.namespace} | Region: ${op.region} | Modo: ${op.modo}`);
  console.log(`Intervalo: ${op.intervalo} s | Duracion: ${op.duracion} s | ` +
    `Hora simulada inicial: ${horaTexto(op.horaInicio)} | Factor: ${op.factor}`);
  console.log("Credenciales: cadena por defecto del SDK (sin llaves en el codigo)");
  if (op.simular) console.log("SIMULACION: no se envia nada a AWS");
  console.log("=".repeat(78));

  let llamadas = 0;
  let datosEnviados = 0;
  let errores = 0;
  let detener = false;
  process.on("SIGINT", () => { detener = true; });
  process.on("SIGTERM", () => { detener = true; });

  async function enviar(metricData) {
    if (op.simular) { llamadas++; datosEnviados += metricData.length; return 200; }
    try {
      const resp = await cliente.send(new PutMetricDataCommand({
        Namespace: op.namespace,
        MetricData: metricData,
      }));
      llamadas++;
      datosEnviados += metricData.length;
      return resp.$metadata.httpStatusCode;
    } catch (e) {
      errores++;
      const codigo = e.$metadata?.httpStatusCode ?? "sin-respuesta";
      console.error(`  ERROR ${codigo} ${e.name}: ${e.message}`);
      return codigo;
    }
  }

  const inicio = Date.now();
  while (!detener && (Date.now() - inicio) / 1000 < op.duracion) {
    const cicloInicio = Date.now();
    const transcurrido = (cicloInicio - inicio) / 1000;
    const hora = (op.horaInicio + (transcurrido * op.factor) / 3600) % 24;
    const datos = generarIntervalo(hora, op.intervalo);
    const metricData = construirMetricData(datos, new Date());
    const ahora = new Date().toISOString().replace("T", " ").slice(0, 19) + " UTC";

    if (op.modo === "normal") {
      // Batching: una sola llamada con todas las metricas del intervalo.
      const estado = await enviar(metricData);
      console.log(`${ahora} | hora ${horaTexto(hora)} | ` +
        `agend=${datos.agendamientos} oport=${datos.oportunidades} pagos=${datos.pagos} ` +
        `rech=${datos.rechazados} | ${metricData.length} metricas en 1 llamada | HTTP ${estado}`);
    } else {
      // Anti-patron (Escenario A): una metrica por llamada.
      const estados = [];
      for (const dato of metricData) estados.push(await enviar([dato]));
      console.log(`${ahora} | DESVIO | ${metricData.length} llamadas de 1 metrica | ` +
        `HTTP ${[...new Set(estados)].join(",")} | llamadas acumuladas=${llamadas}`);
    }

    const espera = op.intervalo * 1000 - (Date.now() - cicloInicio);
    if (espera > 0) await pausa(espera);
  }

  const minutos = (Date.now() - inicio) / 60000;
  const costo = (llamadas / 1000) * 0.01;
  console.log("=".repeat(78));
  console.log(`Fin. Llamadas PutMetricData: ${llamadas} | Datos enviados: ${datosEnviados} | ` +
    `Errores: ${errores} | Minutos: ${minutos.toFixed(1)}`);
  console.log(`Costo de API estimado (USD 0,01 por 1.000 llamadas): USD ${costo.toFixed(6)}`);
  console.log("=".repeat(78));
}

main().catch((e) => {
  console.error("Fallo inesperado:", e);
  process.exit(1);
});
