"""
app.py — E-commerce Mock (Rede de Farmácias)
Aplicação Flask mínima que serve como alvo dos cenários de segurança.
Integra com PostgreSQL e Keycloak (OIDC).
"""

import os
import re
import json
import logging
import psycopg2
import psycopg2.extras
import requests
from functools import wraps
from flask import Flask, request, jsonify, g
from jose import jwt, JWTError

# ── Logging estruturado ───────────────────────────────────────
logging.basicConfig(
    level=logging.INFO,
    format='{"timestamp": "%(asctime)s", "level": "%(levelname)s", "message": "%(message)s", "module": "%(module)s"}'
)
logger = logging.getLogger(__name__)

app = Flask(__name__)
app.config['SECRET_KEY'] = os.environ.get('SECRET_KEY', 'changeme')

# ── Configuração ──────────────────────────────────────────────
DATABASE_URL    = os.environ.get('DATABASE_URL', 'postgresql://farmacia:farmacia2026@postgres:5432/farmaciadb')
KEYCLOAK_URL    = os.environ.get('KEYCLOAK_URL', 'http://keycloak:8080')
KEYCLOAK_REALM  = os.environ.get('KEYCLOAK_REALM', 'farmacia')
KEYCLOAK_CLIENT = os.environ.get('KEYCLOAK_CLIENT_ID', 'ecommerce-app')

JWKS_URL = f"{KEYCLOAK_URL}/realms/{KEYCLOAK_REALM}/protocol/openid-connect/certs"

# ── Conexão com banco de dados ────────────────────────────────
def get_db():
    if 'db' not in g:
        g.db = psycopg2.connect(DATABASE_URL)
        g.db.autocommit = False
    return g.db

@app.teardown_appcontext
def close_db(error):
    db = g.pop('db', None)
    if db is not None:
        db.close()

# ── Autenticação JWT (Keycloak) ───────────────────────────────
def get_keycloak_public_keys():
    try:
        resp = requests.get(JWKS_URL, timeout=5)
        return resp.json()
    except Exception as e:
        logger.error(f"Erro ao buscar JWKS do Keycloak: {e}")
        return None

def require_auth(roles=None):
    """Decorator: exige JWT válido emitido pelo Keycloak."""
    def decorator(f):
        @wraps(f)
        def decorated(*args, **kwargs):
            auth_header = request.headers.get('Authorization', '')
            if not auth_header.startswith('Bearer '):
                return jsonify({'error': 'Token de autenticação ausente'}), 401
            token = auth_header[7:]
            try:
                jwks = get_keycloak_public_keys()
                payload = jwt.decode(
                    token,
                    jwks,
                    algorithms=['RS256'],
                    audience=KEYCLOAK_CLIENT
                )
                g.user = payload
                # Verificar roles se necessário
                if roles:
                    user_roles = payload.get('realm_access', {}).get('roles', [])
                    if not any(r in user_roles for r in roles):
                        return jsonify({'error': 'Acesso negado: permissão insuficiente'}), 403
            except JWTError as e:
                logger.warning(f"Token JWT inválido: {e}")
                return jsonify({'error': 'Token inválido ou expirado'}), 401
            return f(*args, **kwargs)
        return decorated
    return decorator

# ── Endpoints públicos ────────────────────────────────────────

@app.route('/health', methods=['GET'])
def health():
    """Health check para o Docker e WAF."""
    return jsonify({'status': 'ok', 'service': 'ecommerce-farmacia'}), 200

@app.route('/api/produtos', methods=['GET'])
def listar_produtos():
    """Lista o catálogo de produtos (público)."""
    try:
        with get_db().cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
            cur.execute("""
                SELECT id, nome, descricao, principio_ativo, preco, estoque,
                       requer_receita, categoria
                FROM produtos
                ORDER BY categoria, nome
            """)
            produtos = cur.fetchall()
        return jsonify({'produtos': [dict(p) for p in produtos]}), 200
    except Exception as e:
        logger.error(f"Erro ao listar produtos: {e}")
        return jsonify({'error': 'Erro interno'}), 500

@app.route('/api/produtos/<produto_id>', methods=['GET'])
def detalhe_produto(produto_id):
    """Detalhe de um produto específico."""
    try:
        with get_db().cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
            # Uso de parâmetro parametrizado — prevenção de SQL injection
            cur.execute("SELECT * FROM produtos WHERE id = %s", (produto_id,))
            produto = cur.fetchone()
        if not produto:
            return jsonify({'error': 'Produto não encontrado'}), 404
        return jsonify(dict(produto)), 200
    except Exception as e:
        logger.error(f"Erro ao buscar produto: {e}")
        return jsonify({'error': 'Erro interno'}), 500

# ── Endpoint de login (redireciona ao Keycloak) ───────────────

@app.route('/api/login', methods=['POST'])
def login():
    """
    Autentica o usuário via Keycloak (Resource Owner Password Credentials).
    Em produção, usar Authorization Code Flow com redirect.
    """
    data = request.get_json()
    if not data or 'username' not in data or 'password' not in data:
        return jsonify({'error': 'Credenciais ausentes'}), 400

    token_url = f"{KEYCLOAK_URL}/realms/{KEYCLOAK_REALM}/protocol/openid-connect/token"
    try:
        resp = requests.post(token_url, data={
            'grant_type': 'password',
            'client_id': KEYCLOAK_CLIENT,
            'username': data['username'],
            'password': data['password'],
        }, timeout=10)

        if resp.status_code == 200:
            tokens = resp.json()
            logger.info(f"Login bem-sucedido para usuário: {data['username']}")
            return jsonify({
                'access_token': tokens.get('access_token'),
                'refresh_token': tokens.get('refresh_token'),
                'expires_in': tokens.get('expires_in'),
            }), 200
        else:
            logger.warning(f"Falha de login para: {data['username']}")
            return jsonify({'error': 'Credenciais inválidas'}), 401
    except Exception as e:
        logger.error(f"Erro ao contatar Keycloak: {e}")
        return jsonify({'error': 'Serviço de autenticação indisponível'}), 503

# ── Endpoints autenticados ────────────────────────────────────

@app.route('/api/minha-conta', methods=['GET'])
@require_auth()
def minha_conta():
    """Retorna dados da conta do usuário autenticado (sem CPF direto)."""
    user = g.user
    return jsonify({
        'sub': user.get('sub'),
        'nome': user.get('name'),
        'email': user.get('email'),
        'roles': user.get('realm_access', {}).get('roles', []),
    }), 200

@app.route('/api/pedidos', methods=['GET'])
@require_auth()
def listar_pedidos():
    """Lista pedidos do usuário autenticado."""
    user_sub = g.user.get('sub')
    try:
        with get_db().cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
            cur.execute("""
                SELECT p.id, p.total, p.status, p.created_at
                FROM pedidos p
                JOIN clientes c ON c.id = p.cliente_id
                WHERE c.email = %s
                ORDER BY p.created_at DESC
            """, (g.user.get('email'),))
            pedidos = cur.fetchall()
        return jsonify({'pedidos': [dict(p) for p in pedidos]}), 200
    except Exception as e:
        logger.error(f"Erro ao listar pedidos: {e}")
        return jsonify({'error': 'Erro interno'}), 500

@app.route('/api/relatorio', methods=['GET'])
@require_auth(roles=['admin', 'farmaceutico'])
def relatorio_anonimizado():
    """
    Relatório de clientes — retorna dados anonimizados.
    Apenas admins e farmacêuticos têm acesso.
    O ModSecurity WAF inspeciona o body desta resposta para detectar PII.
    """
    try:
        with get_db().cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
            cur.execute("SELECT * FROM v_relatorio_anonimizado")
            dados = cur.fetchall()
        logger.info(f"Relatório acessado por: {g.user.get('email')}")
        return jsonify({'relatorio': [dict(d) for d in dados]}), 200
    except Exception as e:
        logger.error(f"Erro ao gerar relatório: {e}")
        return jsonify({'error': 'Erro interno'}), 500

# ── Tratamento de erros ───────────────────────────────────────

@app.errorhandler(404)
def not_found(e):
    return jsonify({'error': 'Endpoint não encontrado'}), 404

@app.errorhandler(405)
def method_not_allowed(e):
    return jsonify({'error': 'Método não permitido'}), 405

@app.errorhandler(500)
def internal_error(e):
    logger.error(f"Erro interno: {e}")
    return jsonify({'error': 'Erro interno do servidor'}), 500

if __name__ == '__main__':
    # Apenas para desenvolvimento local
    app.run(host='0.0.0.0', port=5000, debug=False)
