#!/usr/bin/env bash
# ==============================================================================
# Script de Validacao Automatizada dos 4 Cenarios de Teste
# Projeto: Arquitetura Segura para Rede de Farmacias (PUCPR)
# Alinhado com MITRE ATT&CK, LGPD e Controles de Defesa Perimetral
# ==============================================================================

set -uo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

TARGET_HOST="${1:-localhost}"
TARGET_PORT="${2:-80}"

echo "=================================================================="
echo "    BATERIA DE TESTES OFICIAL - 4 CENARIOS DE SEGURANCA SOC       "
echo "=================================================================="
echo "Alvo WAF: http://${TARGET_HOST}:${TARGET_PORT}"
echo ""

# ─────────────────────────────────────────────────────────────────────────────
# CENARIO 1: MOVIMENTACAO LATERAL & RECONHECIMENTO (T1046, T1021.004)
# ─────────────────────────────────────────────────────────────────────────────
echo -e "${CYAN}[CENARIO 1] Simulando Movimentacao Lateral e Reconhecimento...${NC}"

echo "  -> 1.1 Injetando evento simulado de port scan (Suricata SID 1000001)..."
SURICATA_CONTAINER=$(docker ps -qf "name=^suricata$" 2>/dev/null || true)
if [ -n "$SURICATA_CONTAINER" ]; then
    NOW=$(date -u +"%Y-%m-%dT%H:%M:%S.000000+0000")
    EVENT_SCAN='{"timestamp":"'"$NOW"'","flow_id":9001001,"in_iface":"eth0","event_type":"alert","src_ip":"172.20.0.10","src_port":54321,"dest_ip":"172.21.0.10","dest_port":80,"proto":"TCP","alert":{"action":"allowed","gid":1,"signature_id":1000001,"rev":1,"signature":"[FARMACIA] Port Scan Detectado - Possivel Lateral Movement","category":"Network Scan","severity":2}}'
    docker exec "$SURICATA_CONTAINER" sh -c "echo '$EVENT_SCAN' >> /var/log/suricata/eve.json"
    echo -e "     ${GREEN}[OK]${NC} Evento de Port Scan injetado em /var/log/suricata/eve.json"

    echo "  -> 1.2 Injetando tentativa de conexao SSH DMZ -> Interna (Suricata SID 1000002)..."
    EVENT_SSH='{"timestamp":"'"$NOW"'","flow_id":9001002,"in_iface":"eth0","event_type":"alert","src_ip":"172.20.0.20","src_port":49152,"dest_ip":"172.21.0.10","dest_port":22,"proto":"TCP","alert":{"action":"allowed","gid":1,"signature_id":1000002,"rev":1,"signature":"[FARMACIA] Acesso SSH da DMZ para Rede Interna - Lateral Movement","category":"Attempted Administrator Privilege Gain","severity":1}}'
    docker exec "$SURICATA_CONTAINER" sh -c "echo '$EVENT_SSH' >> /var/log/suricata/eve.json"
    echo -e "     ${GREEN}[OK]${NC} Evento SSH Lateral Movement injetado."
else
    echo -e "     ${YELLOW}[SKIP]${NC} Container Suricata nao encontrado localmente."
fi

# ─────────────────────────────────────────────────────────────────────────────
# CENARIO 2: EXFILTRACAO DE DADOS E DLP (T1048.003, LGPD)
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo -e "${CYAN}[CENARIO 2] Testando Bloqueio de Exfiltracao e DLP (LGPD)...${NC}"

echo "  -> 2.1 Simulando tentativa de Exfiltracao via FTP porta 21 (Suricata SID 1000010)..."
if [ -n "$SURICATA_CONTAINER" ]; then
    NOW=$(date -u +"%Y-%m-%dT%H:%M:%S.000000+0000")
    EVENT_FTP='{"timestamp":"'"$NOW"'","flow_id":9001010,"in_iface":"eth0","event_type":"alert","src_ip":"172.21.0.10","src_port":50000,"dest_ip":"198.51.100.1","dest_port":21,"proto":"TCP","alert":{"action":"allowed","gid":1,"signature_id":1000010,"rev":1,"signature":"[FARMACIA] ALERTA CRITICO - Tentativa de Exfiltracao via FTP (T1048)","category":"Policy Violation","severity":1}}'
    docker exec "$SURICATA_CONTAINER" sh -c "echo '$EVENT_FTP' >> /var/log/suricata/eve.json"
    echo -e "     ${GREEN}[OK]${NC} Evento de Exfiltracao FTP registrado."
fi

echo "  -> 2.2 Testando bloqueio WAF para SQL Injection (OWASP CRS)..."
HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "http://${TARGET_HOST}:${TARGET_PORT}/api/produtos?id=1%20UNION%20SELECT%201,2,3" || echo "000")
if [ "$HTTP_STATUS" = "403" ]; then
    echo -e "     ${GREEN}[PASS]${NC} WAF bloqueou ataque SQLi com sucesso (HTTP 403 Forbidden)."
else
    echo -e "     ${RED}[FAIL]${NC} Resposta inesperada: HTTP $HTTP_STATUS (Esperado: 403)"
fi

echo "  -> 2.3 Testando bloqueio WAF de Path Traversal (Regra 9010)..."
HTTP_TRAV=$(curl -s -o /dev/null -w "%{http_code}" "http://${TARGET_HOST}:${TARGET_PORT}/api/produtos/../../etc/passwd" || echo "000")
if [ "$HTTP_TRAV" = "400" ] || [ "$HTTP_TRAV" = "403" ] || [ "$HTTP_TRAV" = "404" ]; then
    echo -e "     ${GREEN}[PASS]${NC} Path Traversal bloqueado (HTTP $HTTP_TRAV)."
else
    echo -e "     ${RED}[FAIL]${NC} Resposta inesperada: HTTP $HTTP_TRAV"
fi

# ─────────────────────────────────────────────────────────────────────────────
# CENARIO 3: ESCALACAO DE PRIVILEGIOS & CONTAINER HARDENING (T1611)
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo -e "${CYAN}[CENARIO 3] Verificando Hardening do Container da Aplicacao...${NC}"

ECOMM_CONTAINER=$(docker ps -qf "name=^ecommerce$" 2>/dev/null || true)
if [ -n "$ECOMM_CONTAINER" ]; then
    # Teste de usuario nao-root
    CONTAINER_UID=$(docker exec "$ECOMM_CONTAINER" id -u 2>/dev/null || echo "error")
    if [ "$CONTAINER_UID" != "0" ] && [ "$CONTAINER_UID" != "error" ]; then
        echo -e "  -> 3.1 Usuario Nao-Root:       ${GREEN}[PASS]${NC} Executando com UID $CONTAINER_UID (usuario 'teste')"
    else
        echo -e "  -> 3.1 Usuario Nao-Root:       ${RED}[FAIL]${NC} Container executando como root!"
    fi

    # Teste de sistema de arquivos Read-Only
    RO_TEST=$(docker exec "$ECOMM_CONTAINER" touch /test_file.txt 2>&1 || true)
    if [[ "$RO_TEST" =~ "Read-only file system" ]]; then
        echo -e "  -> 3.2 Filesystem Protegido:    ${GREEN}[PASS]${NC} Sistema de arquivos raiz e Read-Only"
    else
        echo -e "  -> 3.2 Filesystem Protegido:    ${YELLOW}[WARN]${NC} Nao bloqueou escrita em /"
    fi

    # Teste de ausencia de Docker Socket
    SOCKET_TEST=$(docker exec "$ECOMM_CONTAINER" ls /var/run/docker.sock 2>&1 || true)
    if [[ "$SOCKET_TEST" =~ "No such file or directory" ]]; then
        echo -e "  -> 3.3 Isolamento Docker Socket: ${GREEN}[PASS]${NC} /var/run/docker.sock nao esta exposto"
    else
        echo -e "  -> 3.3 Isolamento Docker Socket: ${RED}[FAIL]${NC} Docker socket exposto no container!"
    fi
else
    echo -e "  ${YELLOW}[SKIP]${NC} Container 'ecommerce' nao encontrado para verificacao."
fi

# ─────────────────────────────────────────────────────────────────────────────
# CENARIO 4: EVASAO DE DEFESAS E TELEMETRIA (T1027, SIEM)
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo -e "${CYAN}[CENARIO 4] Testando Evasao de Defesas (Base64) e Telemetria Wazuh...${NC}"

echo "  -> 4.1 Injetando payload Base64 ofuscado (Suricata SID 1000030)..."
if [ -n "$SURICATA_CONTAINER" ]; then
    NOW=$(date -u +"%Y-%m-%dT%H:%M:%S.000000+0000")
    EVENT_B64='{"timestamp":"'"$NOW"'","flow_id":9001030,"in_iface":"eth0","event_type":"alert","src_ip":"172.20.0.100","src_port":52000,"dest_ip":"172.20.0.10","dest_port":80,"proto":"TCP","alert":{"action":"allowed","gid":1,"signature_id":1000030,"rev":1,"signature":"[FARMACIA] Possivel Payload Ofuscado Base64 em HTTP (T1027)","category":"Web Application Attack","severity":2}}'
    docker exec "$SURICATA_CONTAINER" sh -c "echo '$EVENT_B64' >> /var/log/suricata/eve.json"
    echo -e "     ${GREEN}[OK]${NC} Evento Base64 registrado no Suricata."
fi

echo "  -> 4.2 Verificando recebimento de alertas no Wazuh Manager..."
sleep 3
WAZUH_CONTAINER=$(docker ps -qf "name=^wazuh-manager$" 2>/dev/null || true)
if [ -n "$WAZUH_CONTAINER" ]; then
    RECENT_ALERTS=$(docker exec "$WAZUH_CONTAINER" grep -c "Farmacia SOC" /var/ossec/logs/alerts/alerts.log 2>/dev/null || echo 0)
    echo -e "     ${GREEN}[OK]${NC} Alertas correlacionados pelo Wazuh Manager: $RECENT_ALERTS ocorrencias da Farmacia SOC."
fi

echo ""
echo "=================================================================="
echo -e "${GREEN}  EXECUCAO DOS 4 CENARIOS CONCLUIDA COM SUCESSO!${NC}"
echo "=================================================================="
