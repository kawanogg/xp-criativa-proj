FROM python:3.12-slim

# Hardening: não rodar como root
RUN groupadd -r appuser && useradd -r -g appuser appuser

WORKDIR /app

# Copiar dependências e instalar
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copiar código da aplicação
COPY app.py .

# Permissões
RUN chown -R appuser:appuser /app
USER appuser

# Porta da aplicação
EXPOSE 5000

# Iniciar com gunicorn (não usar flask run em produção)
CMD ["gunicorn", "--bind", "0.0.0.0:5000", "--workers", "2", "--timeout", "60", "app:app"]
