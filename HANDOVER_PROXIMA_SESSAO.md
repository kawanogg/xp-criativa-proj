# DOCUMENTO DE TRANSIÇÃO E PLANO DE IMPLEMENTAÇÃO
## Projeto: Arquitetura Segura para Rede de Farmácias (PUCPR)
**Data de Registro:** 12 de Setembro de 2026  
**Equipe:** Gustavo Toshio Kawano, Henrique Papai, Edson Renato  
**Finalidade:** Guia de contexto, estado da arte e roteiro para a próxima sessão de desenvolvimento no Gemini Antigravity.

---

## 1. Visão Geral e Contexto Atual

O projeto consiste no desenvolvimento, endurecimento (*hardening*), monitoramento e testes de invasão/defesa de uma infraestrutura para uma **Rede de Farmácias**, atendendo a requisitos de segurança perimetral, detecção de ameaças (MITRE ATT&CK) e privacidade de dados (LGPD).

### Decisões de Arquitetura Fixadas:
1. **Topologia em Zonas:** A infraestrutura foi dividida em duas pilhas de containers segregadas, espelhando duas Máquinas Virtuais distintas conectadas por um firewall **pfSense** já existente no laboratório:
   * **VM 1 -- DMZ (Zona Desmilitarizada):** ModSecurity WAF, Suricata IDS/IPS e Agente Wazuh DMZ.
   * **VM 2 -- Rede Interna:** E-commerce (Flask), PostgreSQL, Keycloak IAM, Wazuh Manager, Wazuh Indexer (OpenSearch), Wazuh Dashboard e Agente Wazuh Interno.
2. **ZTNA / Zero Trust:** O uso de Twingate/ZTNA foi formalmente adiado e **não** faz parte do escopo atual.
3. **Substituto do ARX:** Devido à ausência de imagem oficial, o ARX foi substituído pelo script em Python `internal/arx/anonymize.py`, que executa k-anonimato e pseudonimização SHA-256 com sucesso.
4. **Usuários Obrigatórios de Avaliação (Privilégio Mínimo):**
   * **Sistema:** `teste` | Senha: `T35t3` (PostgreSQL com acesso apenas de `SELECT` e usuário não-root no container).
   * **Aplicações:** `teste@pucparana.com` | Senha: `Teste@2026` (Keycloak com papel restrito de `cliente`).

---

## 2. O Que Já Foi Implementado e Validado (Status: 100% Funcional Localmente)

Todos os serviços foram criados, corrigidos e testados no Docker Desktop, estando os arquivos sincronizados no repositório GitHub (`kawanogg/xp-criativa-proj`):

* [x] **`docker-compose.dmz.yml`:**
  * WAF ModSecurity sobre NGINX Alpine com OWASP CRS ativo.
  * Regras customizadas de DLP (`id:9001` bloqueia CPF, `id:9002` bloqueia cartões, `id:9003` audita prontuários/CID).
  * Mapeamento de portas externo 80 e 443 apontando para as portas não-privilegiadas 8080/8443 da imagem.
  * Sensor Suricata IDS/IPS com 11 regras cobrindo técnicas de movimentação lateral, portas de exfiltração (FTP 21), C2 e ofuscação Base64.
* [x] **`docker-compose.internal.yml`:**
  * Aplicação E-commerce em Flask com endpoints REST (`/api/produtos`, `/health`) e validação JWT.
  * PostgreSQL 16 com schema populado de dados sintéticos e view `v_relatorio_anonimizado`.
  * Keycloak 25.0 com importação automática do Realm `farmacia`, suporte a MFA via TOTP e usuários cadastrados.
  * Wazuh Manager 4.14.7 e Wazuh Indexer (OpenSearch 2.x) com cluster inicializado em status `GREEN` via `securityadmin.sh`.
  * Wazuh Dashboard web ativo na porta `5601`.
  * Ambos os agentes Wazuh (`agent-dmz` e `agent-internal`) registrados no Manager.
* [x] **Documentação e Relatórios:**
  * `RELATORIO_EQUIPE_SPRINT.md` e `RELATORIO_EQUIPE_SPRINT.tex` (para Overleaf) com todas as evidências, backlog e descrições dos 3 prints oficiais solicitados pelo professor.

---

## 3. O Que Falta Fazer Para Concluir o Projeto (Gaps)

Para a conclusão definitiva da disciplina, restam 3 fases práticas:

### Gap 1: Migração para o Laboratório Virtual Real (2 VMs Linux + pfSense)
* Os serviços foram validados em uma única máquina (Docker Desktop Windows).
* Falta levar a pasta `dmz/` e `docker-compose.dmz.yml` para a **VM Linux da DMZ**.
* Falta levar a pasta `internal/` e `docker-compose.internal.yml` para a **VM Linux Interna**.
* Configurar o arquivo `dmz/suricata/suricata.yaml` e o compose para apontar para a interface de rede Linux real da VM (ex: `ens33` ou `eth0` obtida via `ip a`).

### Gap 2: Configuração do Firewall Perimetral pfSense
* Criação das regras de passagem entre as interfaces virtuais WAN, DMZ e LAN Interna:
  * Permitir tráfego da WAN para a DMZ na porta 80/443 (ModSecurity).
  * Permitir tráfego da DMZ para a Rede Interna apenas nas portas `5000` (E-commerce) e `1514/1515` (Wazuh Manager).
  * Configurar *Egress Filtering* bloqueando conexões de saída em portas não convencionais (ex: porta 21 FTP).

### Gap 3: Execução e Coleta de Evidências dos 4 Cenários de Teste
O estudo de caso exige a demonstração de 4 cenários práticos:
1. **Cenário 1 -- Movimentação Lateral:** Simulação de port scan (nmap) ou conexão SSH da DMZ para a rede interna (Suricata detecta e alerta).
2. **Cenário 2 -- Exfiltração e DLP:** Simulação de exfiltração em porta proibida (FTP 21 bloqueado pelo pfSense) e requisição forçando vazamento de CPF (bloqueada com 403 pelo WAF).
3. **Cenário 3 -- Escalação de Privilégios e Hardening:** Verificação das defesas do container da aplicação (usuário não-root `teste`, ausência de Docker socket montado, filesystem protegido).
4. **Cenário 4 -- Evasão de Defesas e Telemetria:** Verificação de envio de comandos codificados em Base64 (detectados pelo Suricata) e imutabilidade dos logs armazenados no Wazuh Indexer.

---

## 4. Plano de Implementação para a Próxima Sessão

Ao iniciar a próxima sessão no Gemini Antigravity, execute as tarefas na seguinte ordem:

```
[FASE 1: PREPARAÇÃO DE SCRIPTS DE DEPLOY]
  ├── 1.1 Criar script .sh de inicialização para a VM DMZ
  └── 1.2 Criar script .sh de inicialização para a VM Interna

[FASE 2: CONFIGURAÇÃO DE TELEMETRIA WAZUH]
  ├── 2.1 Mapear o arquivo /var/log/suricata/eve.json no wazuh-agent-dmz
  ├── 2.2 Configurar leitura do log do NGINX (/var/log/nginx/access.log)
  └── 2.3 Validar recebimento de alertas no Wazuh Dashboard (http://<ip-interna>:5601)

```

---

## 5. Dicas e Comandos de Retomada Imediata

### Para subir o ambiente local novamente (se precisar testar algo no Windows):
```powershell
# 1º: Subir sempre a rede interna primeiro (cria a rede net_interna)
docker compose -f docker-compose.internal.yml up -d

# 2º: Subir a DMZ em seguida
docker compose -f docker-compose.dmz.yml up -d
```

### URLs Locais de Teste:
* E-commerce via WAF: `http://localhost/api/produtos`
* Teste de Bloqueio WAF: `http://localhost/api/produtos?id=1%20UNION%20SELECT%201,2,3`
* Keycloak IAM: `http://localhost:8080/realms/farmacia/account`
* Wazuh Dashboard (SOC): `http://localhost:5601`

### Credenciais Padrão:
* **Usuário Sistema (menor privilégio):** `teste` / `T35t3`
* **Usuário Aplicação (menor privilégio):** `teste@pucparana.com` / `Teste@2026`
* **Keycloak Admin:** `admin` / `Admin2026!`
* **PostgreSQL Admin:** `farmacia` / `farmacia2026` (Banco: `farmaciadb`)
