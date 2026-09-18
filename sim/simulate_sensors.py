#!/usr/bin/env python3
"""
Simulador de sensores para testar o broker Mosquitto do Procel-Telemetry.

Publica eventos no formato do envelope MQTT definido no README:
  procel/telemetry/v1/{producerId}/{sensorId}/events
  {"messageId": ..., "sensorId": ..., "sourceTimestamp": ..., "payload": {...}}

Uso:
  python3 simulate_sensors.py

Requer: pip install paho-mqtt
"""
import json
import os
import random
import ssl
import sys
import time
import uuid
from datetime import datetime, timezone

import paho.mqtt.client as mqtt

# --- ajuste conforme o ambiente (local, dev, servidor real) ---
# pode sobrescrever via variavel de ambiente ou argumento de linha de comando:
#   BROKER_HOST=192.168.1.50 python3 simulate_sensors.py
#   python3 simulate_sensors.py 192.168.1.50
BROKER_HOST = os.environ.get("BROKER_HOST", sys.argv[1] if len(sys.argv) > 1 else "localhost")
BROKER_PORT = int(os.environ.get("BROKER_PORT", "8883"))
CA_CERT = os.environ.get("CA_CERT", "../certs/ca.crt")          # caminho para o ca.crt
USE_TLS = True

# --- sensores simulados: (producerId, mqttUsername, senha, [sensorIds]) ---
# producerId = usado no topico (namespace de dados)
# mqttUsername = credencial de autenticacao no broker (pode ser diferente do producerId)
SIMULATED_PRODUCERS = [
    ("producer_001", "sensor_producer_001", "TrocarSenhaSensor001!", ["sensor-A1", "sensor-A2"]),
    ("producer_002", "sensor_producer_002", "TrocarSenhaSensor002!", ["sensor-B1"]),
]

PUBLISH_INTERVAL_SECONDS = 5


def make_payload():
    return {
        "temperature": round(random.uniform(18.0, 32.0), 1),
        "humidity": round(random.uniform(30.0, 90.0), 1),
    }


def build_envelope(sensor_id: str) -> dict:
    return {
        "messageId": f"mqtt-{uuid.uuid4()}",
        "sensorId": sensor_id,
        "sourceTimestamp": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "payload": make_payload(),
    }


def connect_client(producer_id: str, mqtt_username: str, password: str) -> mqtt.Client:
    client = mqtt.Client(
        callback_api_version=mqtt.CallbackAPIVersion.VERSION2,
        client_id=f"sim-{producer_id}",
        protocol=mqtt.MQTTv311,
    )
    client.username_pw_set(mqtt_username, password)
    if USE_TLS:
        client.tls_set(ca_certs=CA_CERT, cert_reqs=ssl.CERT_REQUIRED)

    connected = {"ok": False}

    def on_connect(c, userdata, flags, reason_code, properties=None):
        connected["ok"] = (reason_code == 0)
        if reason_code != 0:
            print(f"[erro ao conectar {producer_id}] {reason_code}")

    client.on_connect = on_connect
    client.connect(BROKER_HOST, BROKER_PORT, keepalive=60)
    client.loop_start()

    # espera o handshake (TCP + TLS + CONNACK) concluir antes de publicar
    for _ in range(50):
        if connected["ok"]:
            break
        time.sleep(0.1)
    else:
        raise RuntimeError(f"Timeout conectando como {producer_id}")

    return client


def main():
    print(f"Conectando em {BROKER_HOST}:{BROKER_PORT} (TLS={USE_TLS}, CA={CA_CERT})\n")
    clients = []
    for producer_id, mqtt_username, password, sensor_ids in SIMULATED_PRODUCERS:
        client = connect_client(producer_id, mqtt_username, password)
        clients.append((client, producer_id, sensor_ids))
        print(f"[conectado] {producer_id} (usuario mqtt: {mqtt_username})")

    print(f"\nPublicando a cada {PUBLISH_INTERVAL_SECONDS}s. Ctrl+C para parar.\n")
    try:
        while True:
            for client, producer_id, sensor_ids in clients:
                for sensor_id in sensor_ids:
                    envelope = build_envelope(sensor_id)
                    topic = f"procel/telemetry/v1/{producer_id}/{sensor_id}/events"
                    payload = json.dumps(envelope)
                    result = client.publish(topic, payload, qos=1)
                    result.wait_for_publish()
                    print(f"[publicado] {topic} -> {payload}")
            time.sleep(PUBLISH_INTERVAL_SECONDS)
    except KeyboardInterrupt:
        print("\nEncerrando...")
    finally:
        for client, _, _ in clients:
            client.loop_stop()
            client.disconnect()


if __name__ == "__main__":
    main()
