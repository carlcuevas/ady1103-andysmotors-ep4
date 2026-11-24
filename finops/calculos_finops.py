#!/usr/bin/env python3
"""AndysMotors EP4 - Proyeccion de costos de observabilidad (Escenarios A y B).

Precios de lista de Amazon CloudWatch en us-east-1 (sin capa gratuita):
  Metricas personalizadas  USD 0,30 por metrica-mes (primeras 10.000)
  API PutMetricData        USD 0,01 por 1.000 solicitudes
  Logs (Standard) ingesta  USD 0,50 por GB
  Logs almacenamiento      USD 0,03 por GB-mes
  Dashboards               USD 3,00 por dashboard-mes
  Alarma estandar          USD 0,10 por metrica de alarma-mes
  Alarma alta resolucion   USD 0,30 por metrica de alarma-mes
Mes de 30 dias. Uso: python3 calculos_finops.py
"""

P_METRICA = 0.30
P_API_1000 = 0.01
P_INGESTA_GB = 0.50
P_ALMAC_GB = 0.03
P_DASHBOARD = 3.00
P_ALARMA_STD = 0.10
P_ALARMA_HR = 0.30
DIAS = 30
SEG_MES = DIAS * 24 * 3600

PLATAFORMAS = 5
INSTANCIAS = 30


def escenario_a():
    metricas = INSTANCIAS * 20                       # 20 por instancia con InstanceId
    llamadas = metricas * (SEG_MES / 10)             # 1 metrica por llamada cada 10 s
    ingesta = 1.5 * INSTANCIAS * DIAS                # GB/mes en DEBUG
    almac_m1 = ingesta                               # Nunca expira: acumulado mes 1
    almac_m12 = ingesta * 12                         # acumulado al mes 12
    return dict(
        nombre="A - Diseno propuesto",
        series=metricas, llamadas=llamadas, ingesta=ingesta,
        almac=almac_m1, almac_m12=almac_m12, dashboards=8, alarmas_std=25, alarmas_hr=5,
    )


def escenario_b():
    series = INSTANCIAS * 2 + 18 * PLATAFORMAS       # mem y disco por instancia + 18 de negocio por Plataforma
    llamadas = INSTANCIAS * (SEG_MES / 60)           # 1 llamada por instancia por minuto (batching)
    ingesta = 1.5 * 0.30 * INSTANCIAS * DIAS         # nivel INFO = 30 % del volumen DEBUG
    almac = ingesta * 1.0                            # retencion 30 dias: ~1 mes de ingesta en equilibrio
    return dict(
        nombre="B - Diseno optimizado",
        series=series, llamadas=llamadas, ingesta=ingesta,
        almac=almac, almac_m12=almac, dashboards=3, alarmas_std=20, alarmas_hr=0,
    )


def costear(e, mes12=False):
    almac = e["almac_m12"] if mes12 else e["almac"]
    c = {
        "Metricas personalizadas": e["series"] * P_METRICA,
        "API PutMetricData": e["llamadas"] / 1000 * P_API_1000,
        "Ingesta de logs": e["ingesta"] * P_INGESTA_GB,
        "Almacenamiento de logs": almac * P_ALMAC_GB,
        "Dashboards": e["dashboards"] * P_DASHBOARD,
        "Alarmas": e["alarmas_std"] * P_ALARMA_STD + e["alarmas_hr"] * P_ALARMA_HR,
    }
    c["TOTAL"] = sum(c.values())
    return c


def usd(v):
    return f"{v:>12,.2f}".replace(",", "X").replace(".", ",").replace("X", ".")


def main():
    a, b = escenario_a(), escenario_b()
    ca, cb, ca12 = costear(a), costear(b), costear(a, mes12=True)

    print("PARAMETROS")
    for e in (a, b):
        print(f"  {e['nombre']}: series={e['series']:,} | llamadas/mes={e['llamadas']:,.0f} | "
              f"ingesta={e['ingesta']:,.0f} GB | almacenado={e['almac']:,.0f} GB "
              f"(mes 12: {e['almac_m12']:,.0f} GB) | dashboards={e['dashboards']} | "
              f"alarmas={e['alarmas_std']} std + {e['alarmas_hr']} HR")

    print("\nCOSTO MENSUAL (USD, precios de lista us-east-1)")
    print(f"{'Componente':<26}{'A mes 1':>12}{'A mes 12':>12}{'B':>12}{'Ahorro':>12}{'%':>8}")
    for k in ca:
        ahorro = ca[k] - cb[k]
        pct = (ahorro / ca[k] * 100) if ca[k] else 0
        print(f"{k:<26}{usd(ca[k])}{usd(ca12[k])}{usd(cb[k])}{usd(ahorro)}{pct:>7.1f}%")

    print("\nCOSTO ANUAL (12 meses)")
    anual_a = sum(costear(dict(a, almac=a["ingesta"] * m))["TOTAL"] for m in range(1, 13))
    anual_b = cb["TOTAL"] * 12
    print(f"  A: USD {anual_a:,.2f} | B: USD {anual_b:,.2f} | ahorro: USD {anual_a - anual_b:,.2f} "
          f"({(anual_a - anual_b) / anual_a * 100:.1f} %)")

    llamadas_5min_b = INSTANCIAS * 5
    costo_5min_b = llamadas_5min_b / 1000 * P_API_1000
    umbral = costo_5min_b * 1.5
    print("\nUMBRAL DE LA ALARMA DE PRESUPUESTO (periodo 5 min)")
    print(f"  B: {llamadas_5min_b} llamadas/5 min -> USD {costo_5min_b:.4f}; "
          f"+50 % de margen -> umbral USD {umbral:.5f} ({umbral / P_API_1000 * 1000:.0f} llamadas)")
    llamadas_5min_a = INSTANCIAS * 20 * 30
    print(f"  A: {llamadas_5min_a:,} llamadas/5 min -> USD {llamadas_5min_a / 1000 * P_API_1000:.2f} "
          f"({llamadas_5min_a / 1000 * P_API_1000 / umbral:.0f} veces el umbral)")


if __name__ == "__main__":
    main()
