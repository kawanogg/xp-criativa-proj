#!/usr/bin/env bash
# ==============================================================================
# Script de Deploy e Inicializacao: VM 2 (Rede Interna)
# Projeto: Arquitetura Segura para Rede de Farmacias (PUCPR)
# Servicos: Ecommerce, PostgreSQL, Keycloak, Wazuh Manager, Indexer, Dashboard
# ==============================================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_ok()   { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_err()  { echo -e "${RED}[ERROR]${NC} $1"; }

echo "=================================================================="
echo "    DEPLOYMENT STACK - REDE INTERNA (VM 2) - FARMACIA SOC         "
echo "=================================================================="

# 1. Verificar Privilegios de Root/Sudo
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
    log_err "Plugin 'docker compose' nao encontrado! Instale a versao atualizada do Docker Compose."
    exit 1
fi
log_ok "Docker e Docker Compose identificados com sucesso."

# 3. Configuracao Obrigatoria de Kernel para OpenSearch / Wazuh Indexer
log_info "Verificando e aplicando configuracao de kernel (vm.max_map_count)..."
CURRENT_MAP=$(sysctl -n vm.max_map_count 2>/dev/null || echo 0)
if [ "$CURRENT_MAP" -lt 262144 ]; then
    log_warn "vm.max_map_count atual ($CURRENT_MAP) e inferior ao minimo de 262144."
    sysctl -w vm.max_map_count=262144
    echo "vm.max_map_count=262144" > /etc/sysctl.d/99-wazuh.conf
    log_ok "vm.max_map_count configurado para 262144 e persistido em /etc/sysctl.d/99-wazuh.conf."
else
    log_ok "vm.max_map_count ($CURRENT_MAP) atende aos requisitos do Wazuh Indexer."
fi

# 4. Posicionar no diretorio raiz do projeto
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT"
log_info "Diretorio raiz do projeto: $PROJECT_ROOT"

if [ ! -f "docker-compose.internal.yml" ]; then
    log_err "Arquivo docker-compose.internal.yml nao encontrado em $PROJECT_ROOT!"
    exit 1
fi

# 5. Criar redes e inicializar containers
log_info "Subindo a pilha da Rede Interna..."
docker compose -f docker-compose.internal.yml up -d --build

# 6. Aguardar e Validar Servicos Criticos
log_info "Aguardando estabilizacao dos servicos essenciais..."

# Validar PostgreSQL
echo -n "  -> PostgreSQL: "
for i in {1..30}; do
    if docker exec postgres pg_isready -U farmacia -d farmaciadb &> /dev/null; then
        echo -e "${GREEN}Online e Saudavel!${NC}"
        break
    fi
    sleep 2
    if [ $i -eq 30 ]; then
        echo -e "${RED}Falha no timeout do PostgreSQL!${NC}"
    fi
done

# Validar Wazuh Indexer (OpenSearch Cluster Health)
echo -n "  -> Wazuh Indexer: "
for i in {1..40}; do
    STATUS=$(docker exec wazuh-indexer curl -sk --cert /usr/share/wazuh-indexer/config/certs/admin.pem --key /usr/share/wazuh-indexer/config/certs/admin-key.pem https://localhost:9200/_cluster/health 2>/dev/null | grep -o '"status":"[^"]*"' | cut -d'"' -f4 || echo "starting")
    if [ "$STATUS" = "green" ] || [ "$STATUS" = "yellow" ]; then
        echo -e "${GREEN}Cluster Ativo (Status: $STATUS)!${NC}"
        break
    fi
    sleep 3
    if [ $i -eq 40 ]; then
        echo -e "${YELLOW}Ainda inicializando (Status: $STATUS). Verifique com 'docker logs wazuh-indexer'.${NC}"
    fi
done

# 7. Obter IP da VM Interna
IP_LOCAL=$(hostname -I | awk '{print $1}')

echo ""
echo "=================================================================="
echo -e "${GREEN}  STACT INTERNA IMPLANTADA COM SUCESSO!${NC}"
echo "=================================================================="
echo "  * IP da Máquina Interna: $IP_LOCAL"
echo "  * E-commerce API:        http://$IP_LOCAL:5000/api/produtos"
echo "  * Keycloak IAM:          http://$IP_LOCAL:8080"
echo "  * Wazuh Dashboard (SOC): http://$IP_LOCAL:5601"
echo "  * Wazuh Manager:         Portas 1514 (UDP), 1515 (TCP)"
echo "------------------------------------------------------------------"
echo -e "${YELLOW}[PROXIMO PASSO]:${NC} Na VM da DMZ, execute o script deploy_dmz.sh informando o IP acima:"
echo "  ./scripts/deploy_dmz.sh $IP_LOCAL"
echo "=================================================================="
