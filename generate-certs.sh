#!/bin/bash
# Regera a CA e o certificado do servidor com o endereco real onde o
# broker vai ficar acessivel (IP publico/privado ou dominio).
#
# Por que precisa disso: o certificado de teste original tem CN=localhost,
# que só valida quando cliente e servidor estao na mesma maquina. Testando
# de uma maquina diferente (rede aberta), o cliente MQTT valida o hostname
# do certificado contra o endereco que ele discou — se nao bater, a conexao
# TLS falha mesmo com a CA correta.
#
# Uso:
#   ./generate-certs.sh 203.0.113.10        (IP publico/privado do servidor)
#   ./generate-certs.sh mqtt.procel.com      (dominio)
#
# Sempre inclui tambem localhost/127.0.0.1 como alternativas, entao os
# testes locais continuam funcionando.

set -e

CN="${1:?Uso: ./generate-certs.sh <ip-ou-hostname-do-servidor>}"
BASE_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$BASE_DIR/certs"

if [[ "$CN" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  EXTRA_SAN="IP:$CN"
else
  EXTRA_SAN="DNS:$CN"
fi

openssl genrsa -out ca.key 2048 2>/dev/null
openssl req -x509 -new -nodes -key ca.key -sha256 -days 3650 \
  -out ca.crt -subj "/CN=Procel-MQTT-CA" 2>/dev/null

openssl genrsa -out server.key 2048 2>/dev/null
openssl req -new -key server.key -out server.csr -subj "/CN=$CN" 2>/dev/null

cat > server.ext << EOF
subjectAltName = DNS:localhost,IP:127.0.0.1,$EXTRA_SAN
EOF

openssl x509 -req -in server.csr -CA ca.crt -CAkey ca.key -CAcreateserial \
  -out server.crt -days 825 -sha256 -extfile server.ext 2>/dev/null

chmod 644 ca.crt server.crt server.key
chmod 600 ca.key
rm -f server.csr server.ext ca.srl

echo "Certificados gerados para CN=$CN (+ localhost / 127.0.0.1)."
echo ""
echo "Verificacao:"
openssl x509 -in server.crt -noout -text | grep -A1 "Subject Alternative Name"
echo ""
echo "Copie certs/ca.crt para qualquer maquina que for CONECTAR neste broker"
echo "(sensores simulados, backend de teste, etc) — ela precisa confiar nessa CA."
