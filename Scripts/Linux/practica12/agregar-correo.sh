#!/bin/bash

read -rp "Usuario (sin @reprobados.com): " USUARIO
read -rsp "Contraseña: " PASS; echo

EMAIL="${USUARIO}@reprobados.com"

if docker exec mailserver setup email list 2>/dev/null | grep -q "^${EMAIL}"; then
    echo "[WARN] La cuenta $EMAIL ya existe"
    exit 0
fi

if docker exec mailserver setup email add "$EMAIL" "$PASS"; then
    echo "[OK] Cuenta $EMAIL creada"
else
    echo "[ERROR] No se pudo crear la cuenta"
fi
