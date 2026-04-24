FROM --platform=linux/amd64 python:3.11-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .
RUN pip install --no-cache-dir -e .

EXPOSE 8000

CMD ["/usr/local/bin/gunicorn", "--bind", "0.0.0.0:9999", "--workers", "2", "hello:create_app()"]
