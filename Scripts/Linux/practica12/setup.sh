#!/bin/bash
set -e

echo "======================================================"
echo "  Setup — Práctica 12: Servidor de Correo Privado"
echo "======================================================"

# Crear .env si no existe
if [ ! -f .env ]; then
    cp .env.example .env
    echo "[OK] .env creado — edita las contraseñas en .env si lo deseas"
else
    echo "[OK] .env ya existe"
fi

# Crear directorios necesarios
mkdir -p config logs backups
touch backups/.gitkeep

echo "[OK] Directorios creados: config/ logs/ backups/"

# Añadir entrada a /etc/hosts si no existe
if ! grep -q "reprobados.com" /etc/hosts 2>/dev/null; then
    echo "127.0.0.1 mail.reprobados.com reprobados.com" | sudo tee -a /etc/hosts > /dev/null
    echo "[OK] Entrada añadida a /etc/hosts"
else
    echo "[OK] /etc/hosts ya tiene entrada para reprobados.com"
fi

echo ""
echo "======================================================"
echo "  Próximos pasos"
echo "======================================================"
echo ""
echo "1. Levantar los contenedores:"
echo "   docker compose up -d --build"
echo ""
echo "2. Esperar ~30s a que mailserver inicialice y luego crear las cuentas:"
echo "   docker exec mailserver setup email add director@reprobados.com 'PassSegura1!'"
echo "   docker exec mailserver setup email add admin@reprobados.com 'PassSegura2!'"
echo ""
echo "3. Generar claves DKIM:"
echo "   docker exec mailserver setup config dkim"
echo ""
echo "4. Acceder al webmail:"
echo "   https://mail.reprobados.com"
echo "   (acepta el certificado self-signed en el navegador)"
echo ""
echo "======================================================"
