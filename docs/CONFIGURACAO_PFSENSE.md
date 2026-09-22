# Guia de Configuração Perimetral: Firewall pfSense
## Projeto: Arquitetura Segura para Rede de Farmácias (PUCPR)

Este documento define o roteiro de configuração das interfaces virtuais e regras de filtragem (*Stateful Inspection* e *Egress Filtering*) no firewall pfSense existente no laboratório acadêmico.

---

## 1. Topologia de Rede e Endereçamento

O firewall atua como roteador e concentrador de segurança entre três zonas:

```
                      [ WAN / Internet ]
                              │ (em0 / WAN)
                              ▼
                       ┌─────────────┐
                       │   pfSense   │
                       └──────┬──────┘
             ┌────────────────┴────────────────┐
             │ (em1 / DMZ)                     │ (em2 / LAN Interna)
             ▼                                 ▼
    ┌─────────────────┐               ┌─────────────────┐
    │  VM 1 -- DMZ    │               │ VM 2 -- Interna │
    │ 172.20.0.0/24   │               │ 172.21.0.0/24   │
    │ IP: 172.20.0.10 │               │ IP: 172.21.0.10 │
    │ • ModSec WAF    │               │ • E-commerce    │
    │ • Suricata IDS  │               │ • PostgreSQL    │
    │ • Wazuh Agent   │               │ • Keycloak IAM  │
    └─────────────────┘               │ • Wazuh Manager │
                                      └─────────────────┘
```

### Atribuição de Interfaces no pfSense:
| Interface pfSense | Interface Física / Virt | Sub-rede / IP Gateway | Descrição |
| :--- | :--- | :--- | :--- |
| **WAN** | `vtnet0` ou `em0` | DHCP ou IP Público do Lab | Acesso externo |
| **DMZ** | `vtnet1` ou `em1` | `172.20.0.1/24` | Zona de WAF e Sensores |
| **LAN / Interna**| `vtnet2` ou `em2` | `172.21.0.1/24` | Aplicação, Banco e SIEM |

---

## 2. Regras de Firewall: Interface DMZ

Navegue em **Firewall > Rules > DMZ**. As regras devem ser cadastradas na ordem exata de precedência (de cima para baixo):

| # | Ação | Interface | Protocolo | Origem | Porta Origem | Destino | Porta Destino | Descrição / TTP |
| :-: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :--- |
| **1** | **Pass** | DMZ | TCP | `172.20.0.10` (WAF) | * | `172.21.0.10` (E-com) | `5000` | Tráfego Proxy Reverso WAF -> E-commerce |
| **2** | **Pass** | DMZ | TCP/UDP | `172.20.0.20` (Agent)| * | `172.21.0.20` (Manager) | `1514, 1515` | Telemetria e Registro do Wazuh Agent |
| **3** | **Block**| DMZ | TCP | `172.20.0.0/24` | * | `172.21.0.0/24` | `22` (SSH) | **Cenário 1:** Bloqueio Movimentação Lateral SSH |
| **4** | **Block**| DMZ | Qualquer | `172.20.0.0/24` | * | `172.21.0.0/24` | Qualquer | Bloqueio Restritivo DMZ -> Rede Interna (*Zero Trust*) |
| **5** | **Block**| DMZ | TCP | `172.20.0.0/24` | * | WAN / Qualquer | `21` (FTP) | **Cenário 2:** Egress Filtering - Bloqueio Exfiltração FTP |
| **6** | **Pass** | DMZ | UDP | `172.20.0.0/24` | * | Gateway DMZ | `53` (DNS) | Resolução de nomes interna |
| **7** | **Pass** | DMZ | TCP | `172.20.0.0/24` | * | WAN / Qualquer | `80, 443` | Atualizações e pacotes de SO |
| **8** | **Reject**| DMZ | Qualquer | `172.20.0.0/24`| * | Qualquer | Qualquer | Default Deny DMZ |

---

## 3. Regras de Firewall: Interface WAN e Port Forwarding (NAT)

Para permitir que usuários da Internet acessem a loja virtual com proteção do WAF:

### NAT Port Forward (**Firewall > NAT > Port Forward**):
1. **HTTP (Porta 80):**
   * **Interface:** WAN
   * **Protocol:** TCP
   * **Destination Port:** `80` (HTTP)
   * **Redirect target IP:** `172.20.0.10` (IP da VM DMZ / ModSecurity)
   * **Redirect target port:** `80` (ou `8080` se mapeado diretamente)
   * **Description:** Encaminhamento público para WAF ModSecurity
2. **HTTPS (Porta 443):**
   * **Interface:** WAN
   * **Protocol:** TCP
   * **Destination Port:** `443` (HTTPS)
   * **Redirect target IP:** `172.20.0.10`
   * **Redirect target port:** `443` (ou `8443`)

---

## 4. Regras de Firewall: Interface LAN Interna

Navegue em **Firewall > Rules > LAN**:

| # | Ação | Interface | Protocolo | Origem | Porta Origem | Destino | Porta Destino | Descrição |
| :-: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :--- |
| **1** | **Pass** | LAN | Qualquer | `172.21.0.0/24` | * | `172.21.0.0/24` | Qualquer | Comunicação interna entre microsserviços |
| **2** | **Block**| LAN | TCP | `172.21.0.0/24` | * | Qualquer | `21` | Bloqueio de saída FTP (*Egress Filtering*) |
| **3** | **Pass** | LAN | UDP | `172.21.0.0/24` | * | Gateway LAN | `53` | Resolução de DNS |
| **4** | **Pass** | LAN | TCP | `172.21.0.0/24` | * | Qualquer | `80, 443` | Saída segura para download de imagens/atualizações |
| **5** | **Reject**| LAN | Qualquer | `172.21.0.0/24`| * | Qualquer | Qualquer | Default Deny LAN |

---

## 5. Roteiro Prático de Validação no Laboratório

Execute os seguintes comandos a partir da VM DMZ para comprovar a eficácia das regras:

### Teste 1: Comunicação Autorizada WAF -> E-commerce (Porta 5000)
```bash
curl -i http://172.21.0.10:5000/health
# Esperado: HTTP 200 OK
```

### Teste 2: Bloqueio de Movimentação Lateral SSH DMZ -> Interna (Porta 22)
```bash
nc -zv -w 3 172.21.0.10 22
# Esperado: Conexão recusada/dropada pelo pfSense + Alerta no Suricata SID 1000002
```

### Teste 3: Bloqueio de Exfiltração FTP (Porta 21)
```bash
nc -zv -w 3 8.8.8.8 21
# Esperado: Bloqueio imediato pelo pfSense (*Egress Filtering*) + Alerta Suricata SID 1000010
```

### Teste 4: Telemetria Wazuh DMZ -> Manager (Portas 1514/1515)
```bash
nc -zv -w 3 172.21.0.20 1515
# Esperado: Conexão aceita (Registro de agente online)
```
