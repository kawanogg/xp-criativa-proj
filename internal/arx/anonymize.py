#!/usr/bin/env python3
"""
anonymize.py — Substituto do ARX (anonimização de dados LGPD)
Rede de Farmácias — Segurança da Informação

Aplica técnicas de k-anonimato e pseudonimização nos dados de clientes
exportados do PostgreSQL, gerando um relatório anonimizado em CSV.

Técnicas aplicadas:
  - Supressão de identificadores diretos (CPF -> hash SHA-256 truncado)
  - Generalização de idade (data_nasc -> faixa etária)
  - Pseudonimização de e-mail e nome
  - Mascaramento de endereço (mantém apenas cidade/UF)

Uso:
  python anonymize.py --output relatorio_anonimizado.csv
  python anonymize.py --output relatorio_anonimizado.csv --k 3
"""

import os
import csv
import hashlib
import argparse
import logging
from datetime import date
from collections import defaultdict

import psycopg2
import psycopg2.extras

logging.basicConfig(level=logging.INFO, format='%(asctime)s [%(levelname)s] %(message)s')
logger = logging.getLogger(__name__)

DATABASE_URL = os.environ.get(
    'DATABASE_URL',
    'postgresql://farmacia:farmacia2026@localhost:5432/farmaciadb'
)


def conectar_banco() -> psycopg2.extensions.connection:
    logger.info("Conectando ao banco de dados...")
    return psycopg2.connect(DATABASE_URL)


def calcular_faixa_etaria(data_nasc: date | None) -> str:
    """Generaliza data de nascimento em faixa etária de 10 anos."""
    if data_nasc is None:
        return "Não informado"
    hoje = date.today()
    idade = (hoje - data_nasc).days // 365
    faixa_inicio = (idade // 10) * 10
    return f"{faixa_inicio}-{faixa_inicio + 9} anos"


def pseudonimizar_cpf(cpf: str) -> str:
    """SHA-256 do CPF truncado — irreversível sem o dado original."""
    return "CPF-" + hashlib.sha256(cpf.encode()).hexdigest()[:12].upper()


def pseudonimizar_email(email: str) -> str:
    """Mantém domínio, pseudonimiza local part."""
    if '@' not in email:
        return "***@***.***"
    local, domain = email.split('@', 1)
    pseudo = "user-" + hashlib.sha256(local.encode()).hexdigest()[:8]
    return f"{pseudo}@{domain}"


def mascarar_nome(nome: str) -> str:
    """Mantém apenas o primeiro nome, oculta sobrenomes."""
    partes = nome.strip().split()
    if len(partes) <= 1:
        return partes[0] if partes else "***"
    return f"{partes[0]} {'*' * len(partes[-1])}"


def mascarar_endereco(endereco: str | None) -> str:
    """Mantém apenas cidade e UF."""
    if not endereco:
        return "Não informado"
    # Tenta extrair cidade-UF do formato "Rua X, N, Cidade-UF"
    partes = endereco.split(',')
    if len(partes) >= 3:
        return partes[-1].strip()
    return "Localização omitida"


def buscar_dados_clientes(conn) -> list[dict]:
    """Busca todos os dados de clientes do banco."""
    with conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
        cur.execute("""
            SELECT
                c.id,
                c.nome,
                c.cpf,
                c.email,
                c.data_nasc,
                c.genero,
                c.endereco,
                COUNT(DISTINCT p.id) AS total_pedidos,
                COALESCE(SUM(p.total), 0) AS valor_total_compras,
                COUNT(DISTINCT pr.id) AS total_prontuarios
            FROM clientes c
            LEFT JOIN pedidos p ON p.cliente_id = c.id
            LEFT JOIN prontuarios pr ON pr.cliente_id = c.id
            GROUP BY c.id
            ORDER BY c.id
        """)
        return [dict(row) for row in cur.fetchall()]


def verificar_k_anonimato(registros: list[dict], k: int, quasi_ids: list[str]) -> bool:
    """
    Verifica se o dataset satisfaz k-anonimato.
    Cada combinação de quasi-identificadores deve aparecer >= k vezes.
    """
    grupos = defaultdict(int)
    for reg in registros:
        chave = tuple(reg.get(qi, '') for qi in quasi_ids)
        grupos[chave] += 1

    violacoes = [(chave, cnt) for chave, cnt in grupos.items() if cnt < k]
    if violacoes:
        logger.warning(f"⚠ k-anonimato k={k} violado em {len(violacoes)} grupos:")
        for chave, cnt in violacoes[:5]:
            logger.warning(f"  Grupo {chave}: apenas {cnt} registro(s)")
        return False
    logger.info(f"✓ k-anonimato k={k} satisfeito em todos os grupos.")
    return True


def anonimizar(registros: list[dict]) -> list[dict]:
    """Aplica todas as técnicas de anonimização."""
    anonimizados = []
    for reg in registros:
        anon = {
            'id_pseudonimo':        pseudonimizar_cpf(reg['cpf']),
            'nome_mascarado':       mascarar_nome(reg['nome']),
            'email_pseudonimo':     pseudonimizar_email(reg['email']),
            'faixa_etaria':         calcular_faixa_etaria(reg.get('data_nasc')),
            'genero':               reg.get('genero') or 'Não informado',
            'localidade':           mascarar_endereco(reg.get('endereco')),
            'total_pedidos':        reg.get('total_pedidos', 0),
            'valor_total_faixa':    classificar_valor(float(reg.get('valor_total_compras', 0))),
            'tem_prontuario':       'Sim' if (reg.get('total_prontuarios', 0) > 0) else 'Não',
        }
        anonimizados.append(anon)
    return anonimizados


def classificar_valor(valor: float) -> str:
    """Generaliza valor em faixas — evita inferência por reidentificação."""
    if valor == 0:
        return "R$ 0"
    elif valor < 50:
        return "R$ 1 - R$ 49"
    elif valor < 200:
        return "R$ 50 - R$ 199"
    elif valor < 500:
        return "R$ 200 - R$ 499"
    else:
        return "R$ 500+"


def exportar_csv(registros: list[dict], caminho: str):
    """Exporta os dados anonimizados para CSV."""
    if not registros:
        logger.warning("Nenhum registro para exportar.")
        return

    campos = list(registros[0].keys())
    with open(caminho, 'w', newline='', encoding='utf-8') as f:
        writer = csv.DictWriter(f, fieldnames=campos)
        writer.writeheader()
        writer.writerows(registros)

    logger.info(f"✓ Exportado: {caminho} ({len(registros)} registros)")


def main():
    parser = argparse.ArgumentParser(
        description='Anonimização LGPD — Rede de Farmácias (substituto do ARX)'
    )
    parser.add_argument('--output', default='relatorio_anonimizado.csv',
                        help='Arquivo CSV de saída')
    parser.add_argument('--k', type=int, default=2,
                        help='Valor mínimo de k para k-anonimato (default: 2)')
    args = parser.parse_args()

    try:
        conn = conectar_banco()
        dados = buscar_dados_clientes(conn)
        logger.info(f"Registros encontrados: {len(dados)}")

        if not dados:
            logger.warning("Banco de dados sem registros. Execute o init.sql primeiro.")
            return

        # Anonimizar
        dados_anon = anonimizar(dados)

        # Verificar k-anonimato nos quasi-identificadores
        quasi_ids = ['faixa_etaria', 'genero', 'localidade']
        verificar_k_anonimato(dados_anon, args.k, quasi_ids)

        # Exportar
        exportar_csv(dados_anon, args.output)
        conn.close()

    except psycopg2.OperationalError as e:
        logger.error(f"Erro de conexão com banco: {e}")
        logger.info("Dica: certifique-se que o PostgreSQL está rodando e DATABASE_URL está correto.")
        raise SystemExit(1)


if __name__ == '__main__':
    main()
