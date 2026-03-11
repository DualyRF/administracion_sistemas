#!/bin/bash
# =============================================================================
# http_functions.sh — Funciones para Apache2
# Proyecto : Aprovisionamiento Web Automatizado
# SO       : OpenSUSE Leap
# Uso      : source ./http_functions.sh  (no ejecutar directamente)
# Requiere : source ./utils.sh
# =============================================================================

# -----------------------------------------------------------------------------
# CONSULTAR VERSIONES DISPONIBLES DE APACHE2
# Usa zypper para obtener versiones del repositorio (sin hardcodear)
# Exporta: VERSION_ESTABLE, VERSION_LATEST, VERSION_ELEGIDA
# -----------------------------------------------------------------------------
obtener_versiones_apache() {
    print_title "Versiones disponibles de Apache2"

    if ! requiere_comando "zypper"; then return 1; fi

    print_info "[INFO] Consultando repositorio, espera..."

    # Obtener lista de versiones disponibles desde zypper
    # Formato de columnas: S | Name | Type | Version | Arch | Repository
    local versiones
    versiones=$(zypper search -s apache2 2>/dev/null \
        | awk -F'|' '$2 ~ /^ apache2 *$/ {print $4}' \
        | tr -d ' ' \
        | sort -V \
        | uniq)

    if [[ -z "$versiones" ]]; then
        print_warning "[ERROR] No se encontraron versiones de Apache2 en el repositorio."
        return 1
    fi

    # Convertir a array para indexar
    local -a lista_versiones
    mapfile -t lista_versiones <<< "$versiones"
    local total=${#lista_versiones[@]}

    # Mostrar todas las versiones numeradas
    local i=1
    for v in "${lista_versiones[@]}"; do
        print_menu "  [$i] $v"
        (( i++ ))
    done
    echo ""

    local intentos=0
    while (( intentos < 3 )); do
        echo -ne "${cyan}Selecciona una versión [1-$total]: ${nc}"
        read -r opcion

        if [[ "$opcion" =~ ^[0-9]+$ ]] && (( opcion >= 1 && opcion <= total )); then
            export VERSION_ELEGIDA="${lista_versiones[$((opcion - 1))]}"
            break
        fi

        print_warning "[ERROR] Opción inválida. Ingresa un número entre 1 y $total."
        (( intentos++ ))
    done

    if [[ -z "$VERSION_ELEGIDA" ]]; then
        print_warning "[ERROR] No se seleccionó ninguna versión."
        return 1
    fi

    print_success "[OK] Versión seleccionada: $VERSION_ELEGIDA"
}

# -----------------------------------------------------------------------------
# INSTALAR APACHE2 (silencioso)
# Uso: instalar_apache
# Requiere: VERSION_ELEGIDA exportada por obtener_versiones_apache()
# -----------------------------------------------------------------------------
instalar_apache() {
    print_title "Instalando Apache2"

    if [[ -z "$VERSION_ELEGIDA" ]]; then
        print_warning "[ERROR] No hay versión elegida. Ejecuta obtener_versiones_apache primero."
        return 1
    fi

    # Verificar si ya está instalado
    if rpm -q apache2 &>/dev/null; then
        print_info "[INFO] Apache2 ya está instalado. Omitiendo instalación."
        return 0
    fi

    print_info "[INFO] Instalando apache2-$VERSION_ELEGIDA ..."

    # Instalación silenciosa con zypper (-n = no interactivo, -y = aceptar todo)
    if ! zypper install -n -y "apache2=$VERSION_ELEGIDA" &>/dev/null; then
        # Si la versión exacta falla, instalar la disponible por defecto
        print_info "[WARN] Versión exacta no disponible, instalando versión del repositorio..."
        if ! zypper install -n -y apache2 &>/dev/null; then
            print_warning "[ERROR] Falló la instalación de Apache2."
            return 1
        fi
    fi

    print_success "[OK] Apache2 instalado correctamente."
}

# -----------------------------------------------------------------------------
# CONFIGURAR PUERTO DE APACHE2
# Uso: configurar_puerto_apache "8080"
# Edita: /etc/apache2/listen.conf  (en OpenSUSE, NO ports.conf)
# -----------------------------------------------------------------------------
configurar_puerto_apache() {
    local puerto="$1"
    local listen_conf="/etc/apache2/listen.conf"

    print_title "Configurando puerto Apache2"

    if [[ ! -f "$listen_conf" ]]; then
        print_warning "[ERROR] No se encontró $listen_conf"
        return 1
    fi

    # Backup antes de editar
    cp "$listen_conf" "${listen_conf}.bak"
    print_info "[INFO] Backup creado: ${listen_conf}.bak"

    # Reemplazar cualquier puerto Listen existente por el nuevo
    sed -i "s/^Listen .*/Listen $puerto/" "$listen_conf"

    # Verificar que el cambio se aplicó
    if grep -q "Listen $puerto" "$listen_conf"; then
        print_success "[OK] Puerto configurado a $puerto en $listen_conf"
    else
        print_warning "[ERROR] No se pudo aplicar el cambio de puerto."
        cp "${listen_conf}.bak" "$listen_conf"
        return 1
    fi
}

# -----------------------------------------------------------------------------
# APLICAR HARDENING DE SEGURIDAD EN APACHE2
# - Oculta versión del servidor (ServerTokens / ServerSignature)
# - Deshabilita métodos peligrosos (TRACE, TRACK)
# - Agrega headers de seguridad (X-Frame-Options, X-Content-Type-Options)
# -----------------------------------------------------------------------------
aplicar_seguridad_apache() {
    print_title "Aplicando configuración de seguridad"

    local security_conf="/etc/apache2/conf.d/security.conf"

    # --- 1. Ocultar versión del servidor ---
    if [[ -f "$security_conf" ]]; then
        sed -i "s/^ServerTokens .*/ServerTokens Prod/"      "$security_conf"
        sed -i "s/^ServerSignature .*/ServerSignature Off/"  "$security_conf"
        print_success "[OK] ServerTokens y ServerSignature configurados."
    else
        # Crear el archivo si no existe
        cat >> "$security_conf" <<'EOF'
ServerTokens Prod
ServerSignature Off
EOF
        print_success "[OK] security.conf creado con ServerTokens Prod."
    fi

    # --- 2. Bloquear métodos peligrosos y agregar security headers ---
    local hardening_conf="/etc/apache2/conf.d/hardening.conf"

    cat > "$hardening_conf" <<'EOF'
# Bloquear métodos HTTP peligrosos
<Directory "/">
    <LimitExcept GET POST HEAD>
        Require all denied
    </LimitExcept>
</Directory>

# Cabeceras de seguridad
Header always set X-Frame-Options "SAMEORIGIN"
Header always set X-Content-Type-Options "nosniff"
EOF

    # Asegurarse de que mod_headers esté habilitado
    if ! apache2ctl -M 2>/dev/null | grep -q "headers_module"; then
        a2enmod headers &>/dev/null
        print_info "[INFO] Módulo headers habilitado."
    fi

    print_success "[OK] Hardening aplicado: métodos restringidos y headers de seguridad añadidos."
}

# -----------------------------------------------------------------------------
# HABILITAR Y ARRANCAR APACHE2
# -----------------------------------------------------------------------------
iniciar_apache() {
    print_title "Iniciando servicio Apache2"

    systemctl enable apache2 &>/dev/null
    systemctl restart apache2

    if systemctl is-active --quiet apache2; then
        print_success "[OK] Apache2 activo y corriendo."
    else
        print_warning "[ERROR] Apache2 no pudo iniciar. Revisa: journalctl -xe"
        return 1
    fi
}

# -----------------------------------------------------------------------------
# FLUJO COMPLETO DE APACHE2
# Llamada única desde main.sh
# -----------------------------------------------------------------------------
setup_apache() {
    obtener_versiones_apache || return 1
    pedir_puerto             || return 1
    instalar_apache          || return 1
    configurar_puerto_apache   "$PUERTO_ELEGIDO" || return 1
    aplicar_seguridad_apache || return 1
    abrir_puerto_firewall      "$PUERTO_ELEGIDO" || return 1
    crear_usuario_servicio   "wwwrun" "/srv/www" || return 1
    crear_index "Apache2" "$VERSION_ELEGIDA" "$PUERTO_ELEGIDO" "/srv/www/htdocs" || return 1
    iniciar_apache           || return 1

    echo ""
    print_success "================================================"
    print_success "  Apache2 desplegado exitosamente"
    print_success "  URL : http://localhost:$PUERTO_ELEGIDO"
    print_success "  Ver.: $VERSION_ELEGIDA"
    print_success "================================================"
}