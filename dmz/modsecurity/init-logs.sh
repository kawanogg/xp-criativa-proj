#!/bin/sh
# ============================================================
# init-logs.sh — Inicializacao de arquivos de log fisicos
# Garante que /var/log/nginx contenha arquivos reais para o
# agente Wazuh poder ler atraves do volume compartilhado.
# ============================================================

set -e

# Se access.log ou error.log forem symlinks (apontando para /dev/std*), substitui por arquivos normais
if [ -L /var/log/nginx/access.log ]; then
    rm -f /var/log/nginx/access.log
fi
if [ -L /var/log/nginx/error.log ]; then
    rm -f /var/log/nginx/error.log
fi

touch /var/log/nginx/access.log /var/log/nginx/error.log 2>/dev/null || true

# Configura permissao de leitura global para o Wazuh Agent
chmod 644 /var/log/nginx/*.log 2>/dev/null || true
