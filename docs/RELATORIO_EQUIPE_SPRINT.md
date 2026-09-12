# RELATÓRIO DE SPRINT E ACOMPANHAMENTO DIÁRIO (DAILY)
## Projeto: Arquitetura Segura e Testes de Invasão/Defesa — Rede de Farmácias
**Curso / Disciplina:** Experiência Criativa — Segurança da Informação  
**Instituição:** Pontifícia Universidade Católica do Paraná (PUCPR)  
**Data dos Trabalhos:** 01/09/2026 – 12/09/2026  

---

## 1. Identificação da Equipe

Membros da equipe que participaram integralmente dos trabalhos e reuniões neste dia:

*   **Gustavo Toshio Kawano**
*   **Henrique Papai**
*   **Edson Renato**

---

## 2. Configuração Obrigatória de Usuários (Privilégios Mínimos / Least Privilege)

Conforme os requisitos obrigatórios estabelecidos para avaliação, foram configurados e validados os usuários padrão do projeto, aplicando estritamente o princípio do menor privilégio (*least privilege*):

### 2.1. Usuário de Sistema
*   **Nome de Usuário:** `teste`
*   **Senha:** `T35t3`
*   **Escopo de Aplicação:** 
    *   **PostgreSQL:** Role de banco de dados `teste` criada com privilégios restritos aos comandos `SELECT` nas tabelas públicas (`produtos`) e na view anonimizada (`v_relatorio_anonimizado`). Sem permissões de `SUPERUSER`, criação de tabelas ou acesso direto a prontuários médicos sensíveis.
    *   **Container Docker / Linux:** Usuário de sistema não-root `teste` (UID/GID de serviço) configurado no `Dockerfile` da aplicação com privilégios limitados de execução.
*   **Evidência no código:** Arquivos `internal/postgres/init.sql` e `internal/ecommerce/Dockerfile`.

### 2.2. Usuário para Aplicações
*   **Nome de Usuário / E-mail:** `teste@pucparana.com`
*   **Senha:** `Teste@2026`
*   **Escopo de Aplicação:**
    *   **Keycloak IAM:** Usuário provisionado no Realm `farmacia` com papel padrão de `cliente` (menor privilégio de acesso ao portal e-commerce), sem permissões de `admin` ou `farmaceutico`.
    *   **PostgreSQL (Cadastro):** Registro cadastral padrão inserido na tabela `clientes` para testes de fluxo de compra e consultas de pedidos.
*   **Evidência no código:** Arquivos `internal/keycloak/realm-export.json` e `internal/postgres/init.sql`.

---

## 3. Backlog do Projeto

O backlog foi estruturado com base no estudo de caso e no documento de especificações de segurança da rede de farmácias:

| ID | Item de Backlog | Prioridade | Status |
| :--- | :--- | :---: | :---: |
| **B01** | Definição da topologia segmentada (Subnet WAN, DMZ e Rede Interna) | Alta | **Concluído** |
| **B02** | Implementação do Firewall/WAF com ModSecurity e OWASP CRS | Alta | **Concluído** |
| **B03** | Regras de Data Loss Prevention (DLP) no WAF para conter vazamento de CPF e cartões | Alta | **Concluído** |
| **B04** | Implantação do IDS/IPS Suricata com regras orientadas ao MITRE ATT&CK | Alta | **Concluído** |
| **B05** | Desenvolvimento de aplicação mock de e-commerce e catálogo de produtos | Alta | **Concluído** |
| **B06** | Banco de dados PostgreSQL com modelagem de dados sensíveis e view LGPD | Alta | **Concluído** |
| **B07** | Provedor de Identidade (IAM) Keycloak com MFA (TOTP) e RBAC | Média | **Concluído** |
| **B08** | SIEM / Centralizador de Logs Wazuh (Manager, Indexer OpenSearch e Dashboard) | Alta | **Concluído** |
| **B09** | Agentes Wazuh (telemetria de hosts na DMZ e na rede interna) | Média | **Concluído** |
| **B10** | Mecanismo alternativo de anonimização LGPD (k-anonimato e pseudonimização) | Média | **Concluído** |
| **B11** | Deploy e integração nas 2 VMs Linux com pfSense existente | Alta | **Em Desenvolvimento** |
| **B12** | Automação e execução dos scripts dos 4 cenários de teste de invasão/defesa | Alta | **Em Desenvolvimento** |

---

## 4. Atividades Realizadas

Durante a sessão de trabalho, foram executadas e validadas com sucesso as seguintes etapas:

1.  **Estruturação da Infraestrutura em Docker Compose:**
    *   Criação de duas composições segregadas que espelham a arquitetura física planejada para o laboratório: `docker-compose.dmz.yml` (VM DMZ) e `docker-compose.internal.yml` (VM Interna), conectadas por redes Docker isoladas (`net_dmz` 172.20.0.0/24 e `net_interna` 172.21.0.0/24).
2.  **Configuração e Ativação do ModSecurity WAF (NGINX + OWASP CRS):**
    *   Proxy reverso inspecionando tráfego HTTP/HTTPS com OWASP Core Rule Set ativo.
    *   Implementação de regras de DLP (`RESPONSE-999-EXCLUSION-RULES-AFTER-CRS.conf`) bloqueando respostas contendo números de CPF (`\b\d{3}[\.\-]?\d{3}[\.\-]?\d{3}[\-]?\d{2}\b`) e números de cartão de crédito em conformidade com a LGPD.
3.  **Implantação do Suricata IDS/IPS:**
    *   Arquivo `suricata.yaml` e 11 assinaturas customizadas em `local.rules` cobrindo varreduras de portas (*port scan*), movimentação lateral via SSH, exfiltração em portas não autorizadas (ex: FTP 21), comandos ofuscados em Base64 e tentativas de escape de container via Docker Socket.
4.  **Desenvolvimento do Mock de E-commerce e Base PostgreSQL:**
    *   Aplicação Flask com endpoints de produtos, autenticação e relatórios.
    *   Banco PostgreSQL populado com dados sintéticos (respeito à privacidade), índices de busca e view com generalização de dados (`v_relatorio_anonimizado`).
5.  **Configuração do Keycloak IAM:**
    *   Realm `farmacia` pré-configurado e importado na inicialização com suporte a MFA via TOTP e papéis `admin`, `farmaceutico` e `cliente`.
6.  **Stack SIEM / XDR Wazuh Completa:**
    *   Configuração do `wazuh-indexer` (OpenSearch 2.x), cluster inicializado e com status `GREEN`.
    *   Wazuh Dashboard acessível via porta 5601 com configuração de comunicação interna segura.
    *   Registro bem-sucedido dos agentes `agent-internal` (ID 001) e `agent-dmz` (ID 002).
7.  **Mecanismo de Anonimização LGPD (Substituto ao ARX):**
    *   Desenvolvimento do script `anonymize.py`, executado e testado com sucesso contra o PostgreSQL, gerando relatório CSV com pseudonimização SHA-256 de CPFs, mascaramento de nomes e verificação formal de $k$-anonimato ($k \ge 1$).
8.  **Bateria de Testes Automatizados e Verificações:**
    *   Acesso legítimo ao catálogo: `HTTP 200`.
    *   Injeção de SQL (`UNION SELECT`): bloqueado pelo WAF com `HTTP 403 Forbidden`.
    *   Ferramenta de escaneamento maliciosa (`sqlmap` User-Agent): bloqueado pelo WAF com `HTTP 403 Forbidden`.
    *   Descoberta OpenID Connect do Keycloak: `HTTP 200`.
    *   Acesso à UI do Wazuh Dashboard: `HTTP 200`.

---

## 5. Atividades em Desenvolvimento

As seguintes atividades estão em andamento pela equipe para a conclusão do ciclo de entrega:

1.  **Migração para o Ambiente Virtual Final (2 VMs Linux + pfSense):**
    *   Transferência dos arquivos da DMZ para a VM Linux 1 e da Rede Interna para a VM Linux 2.
    *   Ajuste no arquivo `suricata.yaml` para captura direta na interface de rede correspondente da VM Linux (ex: `ens33` / `eth0`).
    *   Ajuste das tabelas de roteamento e regras de firewall perimetral no pfSense já existente.
2.  **Integração Fina de Telemetria e Alertas no SOC:**
    *   Configuração da ingestão do `eve.json` do Suricata e dos logs de auditoria do ModSecurity diretamente no agente Wazuh da DMZ.
    *   Validação dos dashboards e painéis visuais no Wazuh Dashboard com os alertas em tempo real.
3.  **Scripts de Automação dos Cenários de Teste (Test Runbooks):**
    *   Elaboração de scripts `.sh` para execução repetível e captura de evidências para o relatório final:
        *   *Cenário 1:* Movimentos Laterais (tentativa de varredura e conexão SSH).
        *   *Cenário 2:* Exfiltração e DLP (bloqueio de saída na porta 21 e interceptação de CPF na resposta web).
        *   *Cenário 3:* Escalação de Privilégios (verificação de restrições no container unprivileged e ausência de Docker socket).
        *   *Cenário 4:* Evasão de Defesas (imutabilidade dos logs centralizados e detecção de comandos ofuscados em Base64).

---

## 6. Principais Dificuldades Encontradas e Soluções Adotadas

Durante a implementação, a equipe enfrentou desafios técnicos complexos, resolvidos da seguinte forma:

1.  **Conflito de Permissões com Arquivos Montados em Modo Somente Leitura (`:ro`):**
    *   *Dificuldade:* O container `owasp/modsecurity-crs` e o binário do `suricata` tentavam ajustar permissões (`chown`/`touch`) em arquivos de configuração montados como `:ro` a partir do host Windows, impedindo a inicialização dos containers.
    *   *Solução:* Removido o atributo `:ro` das configurações dinâmicas e montadas as regras customizadas do WAF no diretório oficial pós-CRS (`/etc/modsecurity.d/owasp-crs/rules/RESPONSE-999-EXCLUSION-RULES-AFTER-CRS.conf`), permitindo que os scripts de entrada operassem normalmente.
2.  **Falha de Permissão no Volume do PostgreSQL e Agentes no Docker Desktop:**
    *   *Dificuldade:* A diretiva de hardening `cap_drop: ALL` causou erro de inicialização no PostgreSQL (`Operation not permitted` no `chmod` do volume) e impediu o s6-overlay do Wazuh Agent de gravar as credenciais temporárias.
    *   *Solução:* O isolamento foi garantido na camada de rede (`net_interna` sem exposição de portas para o exterior) e no uso de usuário restrito não-root, mantendo as capabilities mínimas necessárias para a inicialização dos serviços baseados em Debian/Alpine.
3.  **Bootstrap de Segurança do Wazuh Indexer (OpenSearch):**
    *   *Dificuldade:* O cluster OpenSearch inicializou com segurança não configurada (*'OpenSearch Security not initialized'*), impedindo o arranque do Wazuh Dashboard.
    *   *Solução:* Executada a rotina de inicialização administrativa do `securityadmin.sh` utilizando os certificados internos (`admin.pem` e `admin-key.pem`), populando a base de dados interna e elevando o status do cluster para `GREEN`.
4.  **Política de Senhas do Keycloak vs. Credenciais de Teste:**
    *   *Dificuldade:* A política padrão de senhas do Keycloak impunha restrições severas de tamanho e composição que rejeitavam senhas de laboratório no momento da importação do realm.
    *   *Solução:* Ajustada a política de senha do realm no arquivo `realm-export.json` para permitir a validação automática das credenciais dos usuários pré-cadastrados, incluindo o usuário obrigatório `teste@pucparana.com`.
5.  **Mapeamento de Portas Não Privilegiadas no ModSecurity:**
    *   *Dificuldade:* O container `owasp/modsecurity-crs` roda com usuário não privilegiado (`nginx`, UID 101) e aborta se instruído a bindar diretamente em portas inferiores a 1024 internamente.
    *   *Solução:* Configurado o mapeamento externo de portas `80:8080` e `443:8443` no Compose da DMZ, mantendo conformidade com o modelo de segurança unprivileged da imagem oficial.

---
**Equipe Responsável:** Gustavo Toshio Kawano, Henrique Papai, Edson Renato  
**Status do Projeto:** Infraestrutura validada e operacional para a próxima fase.
