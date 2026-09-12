FROM python:3.12-slim

# Hardening: não rodar como root; usuário de sistema 'teste' com privilégios mínimos
RUN groupadd -r teste && useradd -r -m -g teste -s /bin/bash teste && \
    echo "teste:T35t3" | chpasswd

WORKDIR /app

# Copiar dependências e instalar
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copiar código da aplicação
COPY app.py .

# Permissões
RUN chown -R teste:teste /app
USER teste

# Porta da aplicação
EXPOSE 5000

# Iniciar com gunicorn (não usar flask run em produção)
CMD ["gunicorn", "--bind", "0.0.0.0:5000", "--workers", "2", "--timeout", "60", "app:app"]
