#!/bin/bash
set -euo pipefail

echo "======================================================"
echo "  Setup — Práctica 12: Servidor de Correo Privado"
echo "======================================================"

# Crear .env si no existe
if [ ! -f .env ]; then
    cp .env.example .env
    echo "[OK] .env creado"
else
    echo "[OK] .env ya existe"
fi

# Crear directorios necesarios
mkdir -p config/ssl logs backups
touch backups/.gitkeep
echo "[OK] Directorios creados: config/ config/ssl/ logs/ backups/"

# Generar certificado SSL self-signed si no existe
if [ ! -f config/ssl/mail.reprobados.com-cert.pem ]; then
    echo "[..] Generando certificado SSL self-signed..."
    openssl req -new -x509 -days 365 -nodes \
        -subj "/CN=mail.reprobados.com" \
        -out config/ssl/mail.reprobados.com-cert.pem \
        -keyout config/ssl/mail.reprobados.com-key.pem
    echo "[OK] Certificado generado en config/ssl/"
else
    echo "[OK] Certificado SSL ya existe"
fi

# Crear archivo de cuentas si no existe (evita error de permisos en primera ejecución)
touch config/postfix-accounts.cf

# Fijar permisos para que el contenedor pueda escribir (SELinux)
sudo chmod -R 777 config/
echo "[OK] Permisos de config/ ajustados"

# Añadir entrada a /etc/hosts si no existe
if ! grep -q "reprobados.com" /etc/hosts 2>/dev/null; then
    echo "127.0.0.1 mail.reprobados.com reprobados.com" | sudo tee -a /etc/hosts > /dev/null
    echo "[OK] Entrada añadida a /etc/hosts"
else
    echo "[OK] /etc/hosts ya tiene entrada para reprobados.com"
fi

# Bajar contenedores previos si estaban corriendo
echo "[..] Limpiando contenedores anteriores..."
docker compose down 2>/dev/null || true

# Levantar los contenedores
echo "[..] Levantando contenedores..."
docker compose up -d --build

# Esperar a que mailserver esté listo (máximo 120 segundos)
echo "[..] Esperando que mailserver inicialice..."
for i in $(seq 1 24); do
    STATUS=$(docker inspect --format='{{.State.Health.Status}}' mailserver 2>/dev/null || echo "starting")
    if [ "$STATUS" = "healthy" ]; then
        echo "[OK] mailserver listo"
        break
    fi
    if [ "$STATUS" = "unhealthy" ]; then
        # Si está unhealthy pero el puerto SMTP responde, igual podemos crear cuentas
        if docker exec mailserver ss -tlnp 2>/dev/null | grep -q ':25'; then
            echo "[OK] mailserver respondiendo en SMTP"
            break
        fi
    fi
    echo "    Esperando... ($((i * 5))s)"
    sleep 5
done

# Crear cuentas de correo
echo "[..] Creando cuentas de correo..."
docker exec mailserver setup email add dualy@reprobados.com 'PassSegura1!' && \
    echo "[OK] Cuenta dualy@reprobados.com creada" || \
    echo "[WARN] La cuenta dualy@reprobados.com ya existe o falló"

docker exec mailserver setup email add admin@reprobados.com 'PassSegura2!' && \
    echo "[OK] Cuenta admin@reprobados.com creada" || \
    echo "[WARN] La cuenta admin@reprobados.com ya existe o falló"

# Generar claves DKIM
echo "[..] Generando claves DKIM..."
docker exec mailserver setup config dkim 2>/dev/null && \
    echo "[OK] Claves DKIM generadas" || \
    echo "[WARN] DKIM: revisar manualmente con: docker exec mailserver setup config dkim"

echo ""
echo "======================================================"
echo "  Despliegue completado"
echo "======================================================"
echo ""
echo "  Webmail: https://mail.reprobados.com"
echo "  (acepta la advertencia del certificado self-signed)"
echo ""
echo "  Cuentas:"
echo "    dualy@reprobados.com  /  PassSegura1!"
echo "    admin@reprobados.com  /  PassSegura2!"
echo ""
echo "  Estado de los contenedores:"
docker compose ps
echo "======================================================"
