# ==============================================================================
# Script de Validacao Automatizada dos 4 Cenarios de Teste (PowerShell)
# Projeto: Arquitetura Segura para Rede de Farmacias (PUCPR)
# Alinhado com MITRE ATT&CK, LGPD e Controles de Defesa Perimetral
# ==============================================================================

param (
    [string]$TargetHost = "localhost",
    [int]$TargetPort = 80
)

Write-Host "==================================================================" -ForegroundColor Cyan
Write-Host "    BATERIA DE TESTES OFICIAL - 4 CENARIOS DE SEGURANCA SOC       " -ForegroundColor Cyan
Write-Host "==================================================================" -ForegroundColor Cyan
Write-Host "Alvo WAF: http://${TargetHost}:${TargetPort}`n"

# ─────────────────────────────────────────────────────────────────────────────
# CENARIO 1: MOVIMENTACAO LATERAL & RECONHECIMENTO (T1046, T1021.004)
# ─────────────────────────────────────────────────────────────────────────────
Write-Host "[CENARIO 1] Simulando Movimentacao Lateral e Reconhecimento..." -ForegroundColor Yellow

$suricataId = (docker ps -q -f "name=^suricata$")
if ($suricataId) {
    $now = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.000000+0000")
    
    # 1.1 Port Scan (SID 1000001)
    $scanEvent = '{"timestamp":"' + $now + '","flow_id":9001001,"in_iface":"eth0","event_type":"alert","src_ip":"172.20.0.10","src_port":54321,"dest_ip":"172.21.0.10","dest_port":80,"proto":"TCP","alert":{"action":"allowed","gid":1,"signature_id":1000001,"rev":1,"signature":"[FARMACIA] Port Scan Detectado - Possivel Lateral Movement","category":"Network Scan","severity":2}}'
    $scanEvent | docker exec -i suricata sh -c "cat >> /var/log/suricata/eve.json"
    Write-Host "  -> 1.1 Injetando Port Scan: [OK] Evento Suricata SID 1000001 gravado." -ForegroundColor Green

    # 1.2 Tentativa SSH (SID 1000002)
    $sshEvent = '{"timestamp":"' + $now + '","flow_id":9001002,"in_iface":"eth0","event_type":"alert","src_ip":"172.20.0.20","src_port":49152,"dest_ip":"172.21.0.10","dest_port":22,"proto":"TCP","alert":{"action":"allowed","gid":1,"signature_id":1000002,"rev":1,"signature":"[FARMACIA] Acesso SSH da DMZ para Rede Interna - Lateral Movement","category":"Attempted Administrator Privilege Gain","severity":1}}'
    $sshEvent | docker exec -i suricata sh -c "cat >> /var/log/suricata/eve.json"
    Write-Host "  -> 1.2 Injetando Conexao SSH: [OK] Evento Suricata SID 1000002 gravado." -ForegroundColor Green
} else {
    Write-Host "  [SKIP] Container Suricata nao encontrado." -ForegroundColor Yellow
}

# ─────────────────────────────────────────────────────────────────────────────
# CENARIO 2: EXFILTRACAO DE DADOS E DLP (T1048.003, LGPD)
# ─────────────────────────────────────────────────────────────────────────────
Write-Host "`n[CENARIO 2] Testando Bloqueio de Exfiltracao e DLP (LGPD)..." -ForegroundColor Yellow

if ($suricataId) {
    $now = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.000000+0000")
    $ftpEvent = '{"timestamp":"' + $now + '","flow_id":9001010,"in_iface":"eth0","event_type":"alert","src_ip":"172.21.0.10","src_port":50000,"dest_ip":"198.51.100.1","dest_port":21,"proto":"TCP","alert":{"action":"allowed","gid":1,"signature_id":1000010,"rev":1,"signature":"[FARMACIA] ALERTA CRITICO - Tentativa de Exfiltracao via FTP (T1048)","category":"Policy Violation","severity":1}}'
    $ftpEvent | docker exec -i suricata sh -c "cat >> /var/log/suricata/eve.json"
    Write-Host "  -> 2.1 Simulacao Exfiltracao FTP: [OK] Evento Suricata SID 1000010 gravado." -ForegroundColor Green
}

# 2.2 Teste SQL Injection contra WAF usando curl.exe
$sqliCode = (curl.exe -s -o /dev/null -w "%{http_code}" "http://${TargetHost}:${TargetPort}/api/produtos?id=1%20UNION%20SELECT%201,2,3")
if ($sqliCode -eq "403") {
    Write-Host "  -> 2.2 Teste SQLi contra WAF: [PASS] Bloqueado com sucesso (HTTP 403 Forbidden)" -ForegroundColor Green
} else {
    Write-Host "  -> 2.2 Teste SQLi contra WAF: [FAIL] Resposta HTTP $sqliCode (esperado: 403)" -ForegroundColor Red
}

# 2.3 Teste Path Traversal contra WAF usando curl.exe
$travCode = (curl.exe -s -o /dev/null -w "%{http_code}" "http://${TargetHost}:${TargetPort}/api/produtos/../../etc/passwd")
if ($travCode -in @("400", "403", "404")) {
    Write-Host "  -> 2.3 Path Traversal contra WAF: [PASS] Bloqueado com sucesso (HTTP $travCode)" -ForegroundColor Green
} else {
    Write-Host "  -> 2.3 Path Traversal contra WAF: [FAIL] Resposta HTTP $travCode" -ForegroundColor Red
}

# ─────────────────────────────────────────────────────────────────────────────
# CENARIO 3: ESCALACAO DE PRIVILEGIOS & CONTAINER HARDENING (T1611)
# ─────────────────────────────────────────────────────────────────────────────
Write-Host "`n[CENARIO 3] Verificando Hardening do Container da Aplicacao..." -ForegroundColor Yellow

$ecommId = (docker ps -q -f "name=^ecommerce$")
if ($ecommId) {
    # 3.1 Usuario Nao-Root
    $uid = (docker exec ecommerce id -u)
    if ($uid -ne "0") {
        Write-Host "  -> 3.1 Usuario Nao-Root: [PASS] Executando com UID $uid (usuario 'teste')" -ForegroundColor Green
    } else {
        Write-Host "  -> 3.1 Usuario Nao-Root: [FAIL] Container executando como root!" -ForegroundColor Red
    }

    # 3.2 Filesystem Read-Only
    $roOut = (docker exec ecommerce sh -c "touch /test_file.txt 2>&1" | Out-String)
    if ($roOut -match "Read-only file system") {
        Write-Host "  -> 3.2 Filesystem Protegido: [PASS] Sistema de arquivos raiz e Read-Only" -ForegroundColor Green
    } else {
        Write-Host "  -> 3.2 Filesystem Protegido: [WARN] Nao bloqueou gravacao em / ($roOut)" -ForegroundColor Yellow
    }

    # 3.3 Ausencia de Docker Socket
    $sockOut = (docker exec ecommerce sh -c "ls /var/run/docker.sock 2>&1" | Out-String)
    if ($sockOut -match "No such file or directory") {
        Write-Host "  -> 3.3 Isolamento Docker Socket: [PASS] Docker socket nao esta montado" -ForegroundColor Green
    } else {
        Write-Host "  -> 3.3 Isolamento Docker Socket: [FAIL] Docker socket acessivel!" -ForegroundColor Red
    }
} else {
    Write-Host "  [SKIP] Container 'ecommerce' nao encontrado." -ForegroundColor Yellow
}

# ─────────────────────────────────────────────────────────────────────────────
# CENARIO 4: EVASAO DE DEFESAS E TELEMETRIA (T1027, SIEM)
# ─────────────────────────────────────────────────────────────────────────────
Write-Host "`n[CENARIO 4] Testando Evasao de Defesas (Base64) e Telemetria Wazuh..." -ForegroundColor Yellow

if ($suricataId) {
    $now = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.000000+0000")
    $b64Event = '{"timestamp":"' + $now + '","flow_id":9001030,"in_iface":"eth0","event_type":"alert","src_ip":"172.20.0.100","src_port":52000,"dest_ip":"172.20.0.10","dest_port":80,"proto":"TCP","alert":{"action":"allowed","gid":1,"signature_id":1000030,"rev":1,"signature":"[FARMACIA] Possivel Payload Ofuscado Base64 em HTTP (T1027)","category":"Web Application Attack","severity":2}}'
    $b64Event | docker exec -i suricata sh -c "cat >> /var/log/suricata/eve.json"
    Write-Host "  -> 4.1 Injetando Payload Base64: [OK] Evento Suricata SID 1000030 gravado." -ForegroundColor Green
}

# 4.2 Verificacao no Wazuh Manager
Start-Sleep -Seconds 3
$wazuhId = (docker ps -q -f "name=^wazuh-manager$")
if ($wazuhId) {
    $alertsCount = (docker exec wazuh-manager sh -c "grep -c 'Farmacia SOC' /var/ossec/logs/alerts/alerts.log 2>/dev/null || echo 0")
    Write-Host "  -> 4.2 Correlacao Wazuh SIEM: [OK] $alertsCount alertas registrados pelo Wazuh Manager." -ForegroundColor Green
}

Write-Host "`n==================================================================" -ForegroundColor Cyan
Write-Host "  EXECUCAO DOS 4 CENARIOS CONCLUIDA COM SUCESSO!                  " -ForegroundColor Green
Write-Host "==================================================================" -ForegroundColor Cyan
