#!/usr/bin/env bash
# ==============================================================================
# Script de Deploy e Inicializacao: VM 1 (DMZ)
# Projeto: Arquitetura Segura para Rede de Farmacias (PUCPR)
# Servicos: ModSecurity WAF (NGINX), Suricata IDS/IPS, Wazuh Agent DMZ
# ==============================================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_ok()   { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_err()  { echo -e "${RED}[ERROR]${NC} $1"; }

echo "=================================================================="
echo "    DEPLOYMENT STACK - DMZ PERIMETRAL (VM 1) - FARMACIA SOC       "
echo "=================================================================="

# 1. Verificar Privilegios de Superusuario
if [ "$EUID" -ne 0 ]; then
    log_err "Este script deve ser executado com privilegios de superusuario (sudo)."
    exit 1
fi

# 2. Verificar Pre-requisitos do Docker
log_info "Verificando dependencias essenciais (docker, docker compose)..."
if ! command -v docker &> /dev/null; then
    log_err "Docker nao encontrado! Instale o Docker antes de continuar."
    exit 1
fi

if ! docker compose version &> /dev/null; then
    log_err "Plugin 'docker compose' nao encontrado! Instale o Docker Compose."
    exit 1
fi
log_ok "Docker e Docker Compose identificados com sucesso."

# 3. Posicionar no diretorio raiz do projeto
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT"
log_info "Diretorio raiz do projeto: $PROJECT_ROOT"

if [ ! -f "docker-compose.dmz.yml" ]; then
    log_err "Arquivo docker-compose.dmz.yml nao encontrado em $PROJECT_ROOT!"
    exit 1
fi

# 4. Definir IP da VM Interna (comunicação via pfSense)
INTERNAL_IP="${1:-}"
if [ -z "$INTERNAL_IP" ]; then
    echo ""
    log_warn "O IP da VM Interna nao foi passado como argumento."
    read -rp "Informe o IP da VM Interna (ex: 192.168.21.10 ou 172.21.0.10): " INTERNAL_IP
fi

if [ -z "$INTERNAL_IP" ]; then
    log_err "O IP da VM Interna e obrigatorio para configurar o WAF e o agente Wazuh!"
    exit 1
fi
log_ok "IP da VM Interna definido como: $INTERNAL_IP"

# 5. Detectar Interface de Rede Ativa para o Suricata
DEFAULT_IFACE=$(ip route show default 2>/dev/null | awk '/default/ {print $5}' | head -n1 || echo "")
if [ -z "$DEFAULT_IFACE" ]; then
    DEFAULT_IFACE=$(ip -o link show | awk -F': ' '$2 != "lo" {print $2; exit}' || echo "eth0")
fi
SURICATA_IFACE="${SURICATA_IFACE:-$DEFAULT_IFACE}"
log_ok "Interface de rede para o Suricata detectada: $SURICATA_IFACE"

# 6. Atualizar configuracao de captura no suricata.yaml se necessario
SURICATA_CONF="$PROJECT_ROOT/dmz/suricata/suricata.yaml"
if [ -f "$SURICATA_CONF" ]; then
    log_info "Ajustando interface af-packet no suricata.yaml para: $SURICATA_IFACE"
    sed -i "s/- interface: .*/- interface: $SURICATA_IFACE/g" "$SURICATA_CONF"
fi

# 7. Exportar Variaveis de Ambiente para o Docker Compose
export BACKEND_URL="http://$INTERNAL_IP:5000"
export WAZUH_MANAGER_IP="$INTERNAL_IP"
export SURICATA_IFACE="$SURICATA_IFACE"

# Criar rede net_interna caso nao exista (para compatibilidade de bridge local)
if ! docker network inspect net_interna &> /dev/null; then
    log_info "Criando rede net_interna ficticia para viabilizar carregamento do compose..."
    docker network create net_interna --subnet 172.21.0.0/24 2>/dev/null || true
fi

# 8. Garantir Permissoes de Execucao no Script de Logs
chmod +x "$PROJECT_ROOT/dmz/modsecurity/init-logs.sh"

# 9. Inicializar a Pilha da DMZ
log_info "Subindo servicos da DMZ (ModSecurity, Suricata, Wazuh Agent DMZ)..."
docker compose -f docker-compose.dmz.yml up -d --build

# 10. Validar Inicializacao
log_info "Aguardando estabilizacao dos servicos da DMZ..."
sleep 5

echo -n "  -> ModSecurity WAF: "
if curl -sk http://localhost/nginx-health &> /dev/null || curl -sk http://localhost/api/produtos &> /dev/null; then
    echo -e "${GREEN}Online e Operante!${NC}"
else
    echo -e "${YELLOW}Subiu (verifique conexao com backend em $BACKEND_URL)${NC}"
fi

echo -n "  -> Suricata IDS: "
if docker ps --format '{{.Names}}' | grep -q '^suricata$'; then
    echo -e "${GREEN}Monitorando interface $SURICATA_IFACE!${NC}"
else
    echo -e "${RED}Suricata nao esta ativo!${NC}"
fi

echo -n "  -> Wazuh Agent DMZ: "
if docker ps --format '{{.Names}}' | grep -q '^wazuh-agent-dmz$'; then
    echo -e "${GREEN}Ativo e apontado para $WAZUH_MANAGER_IP!${NC}"
else
    echo -e "${RED}Wazuh Agent DMZ nao esta ativo!${NC}"
fi

# 11. Resumo Final
IP_DMZ=$(hostname -I 2>/dev/null | awk '{print $1}' || echo "localhost")

echo ""
echo "=================================================================="
echo -e "${GREEN}  PILHA DA DMZ IMPLANTADA COM SUCESSO!${NC}"
echo "=================================================================="
echo "  * IP da Máquina DMZ:     $IP_DMZ"
echo "  * ModSecurity WAF HTTP:  http://$IP_DMZ/"
echo "  * Backend Configurado:   $BACKEND_URL"
echo "  * Suricata IDS Escuta:   Interface '$SURICATA_IFACE'"
echo "  * Wazuh Manager Destino: $WAZUH_MANAGER_IP (portas 1514/1515)"
echo "------------------------------------------------------------------"
echo "  Comandos rapidos de verificacao de seguranca:"
echo "  1) Teste de Bloqueio SQLi WAF:"
echo "     curl -i 'http://localhost/api/produtos?id=1%20UNION%20SELECT%201,2,3'"
echo "  2) Ver logs de alertas do Suricata:"
echo "     docker exec suricata tail -f /var/log/suricata/eve.json"
echo "=================================================================="
