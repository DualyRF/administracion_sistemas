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

# Generar certificados SSL dentro de un contenedor Docker
# (así los archivos quedan con el contexto SELinux correcto para ser leídos por otros contenedores)
if [ ! -f config/ssl/mail.reprobados.com-full.pem ]; then
    echo "[..] Generando certificados SSL en contenedor Docker..."
    mkdir -p config/ssl
    chmod 777 config/ssl
    docker run --rm \
        -v "$(pwd)/config/ssl:/ssl:z" \
        alpine sh -c "
            apk add --no-cache openssl -q &&
            openssl req -new -x509 -days 365 -nodes \
                -subj '/CN=mail.reprobados.com' \
                -out /ssl/mail.reprobados.com-cert.pem \
                -keyout /ssl/mail.reprobados.com-key.pem 2>/dev/null &&
            cat /ssl/mail.reprobados.com-cert.pem /ssl/mail.reprobados.com-key.pem \
                > /ssl/mail.reprobados.com-full.pem &&
            echo 'Certificados generados correctamente'
        "
    echo "[OK] Certificados generados en config/ssl/"
else
    echo "[OK] Certificados SSL ya existen"
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

# Crear cuentas de correo (el mailserver las necesita para inicializar)
# Reintenta durante 90 segundos hasta que el contenedor acepte comandos
echo "[..] Creando cuentas de correo (esperando que el contenedor arranque)..."
CUENTAS_OK=0
for i in $(seq 1 18); do
    if docker exec mailserver setup email add dualy@reprobados.com 'PassSegura1!' 2>/dev/null; then
        echo "[OK] Cuenta dualy@reprobados.com creada"
        docker exec mailserver setup email add admin@reprobados.com 'PassSegura2!' 2>/dev/null && \
            echo "[OK] Cuenta admin@reprobados.com creada" || \
            echo "[WARN] admin@reprobados.com ya existe o falló"
        CUENTAS_OK=1
        break
    fi
    echo "    Reintentando... ($((i * 5))s)"
    sleep 5
done

if [ "$CUENTAS_OK" = "0" ]; then
    echo "[ERROR] No se pudieron crear las cuentas. Revisa: docker compose logs mailserver"
    exit 1
fi

# Esperar a que mailserver termine de inicializar tras tener cuentas
echo "[..] Esperando que mailserver complete la inicialización..."
for i in $(seq 1 12); do
    STATUS=$(docker inspect --format='{{.State.Health.Status}}' mailserver 2>/dev/null || echo "starting")
    if [ "$STATUS" = "healthy" ]; then
        echo "[OK] mailserver listo"
        break
    fi
    echo "    Estado: $STATUS ($((i * 5))s)"
    sleep 5
done

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
