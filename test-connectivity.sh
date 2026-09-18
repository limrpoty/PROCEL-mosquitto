#!/bin/bash
# Testa se o broker esta realmente funcional, de qualquer maquina que tenha
# mosquitto-clients instalado e o certs/ca.crt deste pacote.
#
# Uso:
#   ./test-connectivity.sh <host> [porta]
#   ./test-connectivity.sh 192.168.1.50
#   ./test-connectivity.sh mqtt.procel.com 8883
#
# Requer: mosquitto-clients (sudo apt install -y mosquitto-clients)

set -u
HOST="${1:?Uso: ./test-connectivity.sh <host-ou-ip-do-broker> [porta]}"
PORT="${2:-8883}"
BASE_DIR="$(cd "$(dirname "$0")" && pwd)"
CA="$BASE_DIR/certs/ca.crt"

if [ ! -f "$CA" ]; then
  echo "Nao encontrei $CA. Rode este script a partir da pasta do pacote."
  exit 1
fi

PASS=0
FAIL=0
check() {
  if [ "$2" = "0" ]; then echo "[OK]   $1"; PASS=$((PASS+1));
  else echo "[FAIL] $1"; FAIL=$((FAIL+1)); fi
}

echo "== Teste de conectividade: $HOST:$PORT =="
echo ""

# 1) Backend assina e sensor publica -> mensagem deve chegar
SUBLOG="$(mktemp)"
timeout 6 mosquitto_sub -h "$HOST" -p "$PORT" --cafile "$CA" \
  -u backend_procel_telemetry -P 'TrocarSenhaBackend123!' \
  -t 'procel/telemetry/v1/#' -C 1 -W 5 > "$SUBLOG" 2>&1 &
SUB_PID=$!
sleep 1

mosquitto_pub -h "$HOST" -p "$PORT" --cafile "$CA" \
  -u sensor_producer_001 -P 'TrocarSenhaSensor001!' \
  -t 'procel/telemetry/v1/producer_001/sensor-teste/events' \
  -m '{"messageId":"conn-test-001","sensorId":"sensor-teste","sourceTimestamp":"2026-01-01T00:00:00Z","payload":{"ok":true}}' 2>/dev/null
check "sensor publica com TLS + autenticacao" $?

wait "$SUB_PID" 2>/dev/null
grep -q "conn-test-001" "$SUBLOG"
check "backend recebe a mensagem publicada" $?

# 2) Senha errada deve ser rejeitada na conexao
AUTHLOG="$(mktemp)"
mosquitto_pub -h "$HOST" -p "$PORT" --cafile "$CA" \
  -u sensor_producer_001 -P 'senha-errada-de-proposito' \
  -t 'procel/telemetry/v1/producer_001/sensor-teste/events' \
  -m '{}' > "$AUTHLOG" 2>&1
grep -qi "not authorised\|Connection Refused" "$AUTHLOG"
check "senha errada e rejeitada" $?

# 3) ACL: sensor_001 nao pode publicar no namespace do producer_002
ACLLOG="$(mktemp)"
timeout 5 mosquitto_sub -h "$HOST" -p "$PORT" --cafile "$CA" \
  -u backend_procel_telemetry -P 'TrocarSenhaBackend123!' \
  -t 'procel/telemetry/v1/producer_002/#' -C 1 -W 4 > "$ACLLOG" 2>&1 &
ACL_SUB_PID=$!
sleep 1
mosquitto_pub -h "$HOST" -p "$PORT" --cafile "$CA" \
  -u sensor_producer_001 -P 'TrocarSenhaSensor001!' \
  -t 'procel/telemetry/v1/producer_002/sensor-invasor/events' \
  -m '{"tentativa":"cross-producer"}' 2>/dev/null
wait "$ACL_SUB_PID" 2>/dev/null
if grep -q "cross-producer" "$ACLLOG"; then
  check "ACL bloqueia sensor publicando fora do proprio producerId" 1
else
  check "ACL bloqueia sensor publicando fora do proprio producerId" 0
fi

rm -f "$SUBLOG" "$AUTHLOG" "$ACLLOG"

echo ""
echo "== Resultado: $PASS OK / $FAIL falhas =="
[ "$FAIL" -eq 0 ]
