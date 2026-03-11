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

# =============================================================================
# NGINX
# =============================================================================

# -----------------------------------------------------------------------------
# CONSULTAR VERSIONES DISPONIBLES DE NGINX
# Exporta: VERSION_ELEGIDA
# -----------------------------------------------------------------------------
obtener_versiones_nginx() {
    print_title "Versiones disponibles de Nginx"

    if ! requiere_comando "zypper"; then return 1; fi

    print_info "[INFO] Consultando repositorio, espera..."

    local versiones
    versiones=$(zypper search -s nginx 2>/dev/null \
        | awk -F'|' '$2 ~ /^ nginx *$/ {print $4}' \
        | tr -d ' ' \
        | sort -V \
        | uniq)

    if [[ -z "$versiones" ]]; then
        print_warning "[ERROR] No se encontraron versiones de Nginx en el repositorio."
        return 1
    fi

    local -a lista_versiones
    mapfile -t lista_versiones <<< "$versiones"
    local total=${#lista_versiones[@]}

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
# INSTALAR NGINX (silencioso)
# -----------------------------------------------------------------------------
instalar_nginx() {
    print_title "Instalando Nginx"

    if [[ -z "$VERSION_ELEGIDA" ]]; then
        print_warning "[ERROR] No hay versión elegida. Ejecuta obtener_versiones_nginx primero."
        return 1
    fi

    if rpm -q nginx &>/dev/null; then
        print_info "[INFO] Nginx ya está instalado. Omitiendo instalación."
        return 0
    fi

    print_info "[INFO] Instalando nginx-$VERSION_ELEGIDA ..."

    if ! zypper install -n -y "nginx=$VERSION_ELEGIDA" &>/dev/null; then
        print_info "[WARN] Versión exacta no disponible, instalando versión del repositorio..."
        if ! zypper install -n -y nginx &>/dev/null; then
            print_warning "[ERROR] Falló la instalación de Nginx."
            return 1
        fi
    fi

    print_success "[OK] Nginx instalado correctamente."
}

# -----------------------------------------------------------------------------
# CONFIGURAR PUERTO DE NGINX
# Edita: /etc/nginx/nginx.conf  —  bloque server { listen PORT; }
# -----------------------------------------------------------------------------
configurar_puerto_nginx() {
    local puerto="$1"
    local nginx_conf="/etc/nginx/nginx.conf"

    print_title "Configurando puerto Nginx"

    if [[ ! -f "$nginx_conf" ]]; then
        print_warning "[ERROR] No se encontró $nginx_conf"
        return 1
    fi

    cp "$nginx_conf" "${nginx_conf}.bak"
    print_info "[INFO] Backup creado: ${nginx_conf}.bak"

    sed -i "s/listen\s\+[0-9]\+;/listen $puerto;/g" "$nginx_conf"

    if grep -q "listen $puerto;" "$nginx_conf"; then
        print_success "[OK] Puerto configurado a $puerto en $nginx_conf"
    else
        print_warning "[ERROR] No se pudo aplicar el cambio de puerto."
        cp "${nginx_conf}.bak" "$nginx_conf"
        return 1
    fi
}

# -----------------------------------------------------------------------------
# APLICAR HARDENING DE SEGURIDAD EN NGINX
# - Oculta versión (server_tokens off)
# - Deshabilita métodos peligrosos
# - Agrega headers de seguridad
# -----------------------------------------------------------------------------
aplicar_seguridad_nginx() {
    print_title "Aplicando configuración de seguridad Nginx"

    local nginx_conf="/etc/nginx/nginx.conf"
    local puerto="$PUERTO_ELEGIDO"

    # Eliminar cualquier archivo previo en conf.d que pueda causar conflictos
    rm -f /etc/nginx/conf.d/hardening.conf
    rm -f /etc/nginx/conf.d/*.conf 2>/dev/null

    # Reescribir nginx.conf completo con todas las directivas correctas
    cat > "$nginx_conf" << NGINXEOF
user nginx;
worker_processes auto;
error_log /var/log/nginx/error.log;
pid /run/nginx.pid;

events {
    worker_connections 1024;
}

http {
    include       /etc/nginx/mime.types;
    default_type  application/octet-stream;
    sendfile        on;
    keepalive_timeout 65;

    # Ocultar version del servidor
    server_tokens off;

    server {
        listen $puerto;
        server_name localhost;

        root /srv/www/nginx;
        index index.html;

        # Cabeceras de seguridad
        add_header X-Frame-Options "SAMEORIGIN" always;
        add_header X-Content-Type-Options "nosniff" always;

        # Bloquear metodos peligrosos
        location / {
            limit_except GET POST HEAD {
                deny all;
            }
        }
    }
}
NGINXEOF

    print_success "[OK] server_tokens off aplicado."
    print_success "[OK] Headers de seguridad añadidos."
    print_success "[OK] Métodos peligrosos bloqueados en location /."
    print_success "[OK] Hardening aplicado."
}

# -----------------------------------------------------------------------------
# HABILITAR Y ARRANCAR NGINX
# -----------------------------------------------------------------------------
iniciar_nginx() {
    print_title "Iniciando servicio Nginx"

    # Crear directorio para el pid si no existe
    if [[ ! -d /run/nginx ]]; then
        mkdir -p /run/nginx
        chown nginx:nginx /run/nginx
        chmod 755 /run/nginx
        print_info "[INFO] Directorio /run/nginx creado."
    fi

    # Aplicar override de systemd para deshabilitar restricciones SELinux del unit
    local override_dir="/etc/systemd/system/nginx.service.d"
    mkdir -p "$override_dir"
    cat > "${override_dir}/override.conf" <<'EOF'
[Service]
ProtectSystem=false
PrivateTmp=false
RuntimeDirectory=nginx
RuntimeDirectoryMode=0755
PIDFile=/run/nginx/nginx.pid
EOF
    systemctl daemon-reload &>/dev/null
    print_info "[INFO] Override de systemd aplicado."

    # Cambiar pid a ubicacion que nginx puede escribir
    sed -i "s|pid /run/nginx.pid;|pid /run/nginx/nginx.pid;|g" /etc/nginx/nginx.conf

    if ! nginx -t &>/dev/null; then
        print_warning "[ERROR] Configuración de Nginx inválida:"
        nginx -t
        return 1
    fi

    systemctl enable nginx &>/dev/null
    systemctl restart nginx

    if systemctl is-active --quiet nginx; then
        print_success "[OK] Nginx activo y corriendo."
    else
        print_warning "[ERROR] Nginx no pudo iniciar. Revisa: journalctl -xe"
        return 1
    fi
}

# -----------------------------------------------------------------------------
# FLUJO COMPLETO DE NGINX
# Llamada única desde main.sh
# -----------------------------------------------------------------------------
setup_nginx() {
    obtener_versiones_nginx                                                    || return 1
    pedir_puerto                                                               || return 1
    instalar_nginx                                                             || return 1
    configurar_puerto_nginx      "$PUERTO_ELEGIDO"                            || return 1
    aplicar_seguridad_nginx                                                    || return 1
    abrir_puerto_firewall        "$PUERTO_ELEGIDO"                            || return 1
    crear_usuario_servicio       "nginx" "/srv/www/nginx"                     || return 1
    crear_index "Nginx" "$VERSION_ELEGIDA" "$PUERTO_ELEGIDO" "/srv/www/nginx" || return 1
    iniciar_nginx                                                              || return 1

    echo ""
    print_success "================================================"
    print_success "  Nginx desplegado exitosamente"
    print_success "  URL : http://localhost:$PUERTO_ELEGIDO"
    print_success "  Ver.: $VERSION_ELEGIDA"
    print_success "================================================"
}

# =============================================================================
# TOMCAT
# =============================================================================

# -----------------------------------------------------------------------------
# CONSULTAR VERSIONES DISPONIBLES DE TOMCAT
# Exporta: VERSION_ELEGIDA
# -----------------------------------------------------------------------------
obtener_versiones_tomcat() {
    print_title "Versiones disponibles de Tomcat"

    if ! requiere_comando "zypper"; then return 1; fi

    print_info "[INFO] Consultando repositorio, espera..."

    local versiones
    versiones=$(zypper search -s tomcat 2>/dev/null \
        | awk -F'|' '$2 ~ /^ tomcat *$/ {print $4}' \
        | tr -d ' ' \
        | sort -V \
        | uniq)

    if [[ -z "$versiones" ]]; then
        print_warning "[ERROR] No se encontraron versiones de Tomcat en el repositorio."
        return 1
    fi

    local -a lista_versiones
    mapfile -t lista_versiones <<< "$versiones"
    local total=${#lista_versiones[@]}

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
# INSTALAR TOMCAT (silencioso)
# -----------------------------------------------------------------------------
instalar_tomcat() {
    print_title "Instalando Tomcat"

    if [[ -z "$VERSION_ELEGIDA" ]]; then
        print_warning "[ERROR] No hay versión elegida. Ejecuta obtener_versiones_tomcat primero."
        return 1
    fi

    if rpm -q tomcat &>/dev/null; then
        print_info "[INFO] Tomcat ya está instalado. Omitiendo instalación."
        return 0
    fi

    print_info "[INFO] Instalando tomcat-$VERSION_ELEGIDA ..."

    if ! zypper install -n -y "tomcat=$VERSION_ELEGIDA" &>/dev/null; then
        print_info "[WARN] Versión exacta no disponible, instalando versión del repositorio..."
        if ! zypper install -n -y tomcat &>/dev/null; then
            print_warning "[ERROR] Falló la instalación de Tomcat."
            return 1
        fi
    fi

    print_success "[OK] Tomcat instalado correctamente."
}

# -----------------------------------------------------------------------------
# CONFIGURAR PUERTO DE TOMCAT
# Edita: /etc/tomcat/server.xml  — atributo port del Connector HTTP
# -----------------------------------------------------------------------------
configurar_puerto_tomcat() {
    local puerto="$1"
    local server_xml="/etc/tomcat/server.xml"

    print_title "Configurando puerto Tomcat"

    if [[ ! -f "$server_xml" ]]; then
        print_warning "[ERROR] No se encontró $server_xml"
        return 1
    fi

    cp "$server_xml" "${server_xml}.bak"
    print_info "[INFO] Backup creado: ${server_xml}.bak"

    # Cambiar el puerto del Connector HTTP (no el AJP)
    sed -i "s/port=\"8080\"/port=\"$puerto\"/" "$server_xml"
    sed -i "s/port=\"8009\"/port=\"8009\"/" "$server_xml"

    if grep -q "port=\"$puerto\"" "$server_xml"; then
        print_success "[OK] Puerto configurado a $puerto en $server_xml"
    else
        print_warning "[ERROR] No se pudo aplicar el cambio de puerto."
        cp "${server_xml}.bak" "$server_xml"
        return 1
    fi
}

# -----------------------------------------------------------------------------
# APLICAR HARDENING DE SEGURIDAD EN TOMCAT
# - Oculta versión del servidor
# - Deshabilita métodos peligrosos (TRACE)
# - Agrega headers de seguridad via web.xml
# -----------------------------------------------------------------------------
aplicar_seguridad_tomcat() {
    print_title "Aplicando configuración de seguridad Tomcat"

    local server_xml="/etc/tomcat/server.xml"
    local web_xml="/etc/tomcat/web.xml"

    # --- 1. Ocultar versión — agregar ServerInfo vacío via server.xml ---
    if ! grep -q "ServerInfo" "$server_xml"; then
        sed -i "s|</Host>|    <Valve className=\"org.apache.catalina.valves.ErrorReportValve\" showReport=\"false\" showServerInfo=\"false\" />\n        </Host>|" "$server_xml"
    fi
    print_success "[OK] Versión del servidor ocultada."

    # --- 2. Deshabilitar método TRACE en web.xml ---
    if [[ -f "$web_xml" ]]; then
        if ! grep -q "TRACE" "$web_xml"; then
            sed -i "s|</web-app>|    <security-constraint>\n        <web-resource-collection>\n            <web-resource-name>Restricted Methods</web-resource-name>\n            <url-pattern>/*</url-pattern>\n            <http-method>TRACE</http-method>\n            <http-method>TRACK</http-method>\n        </web-resource-collection>\n        <auth-constraint />\n    </security-constraint>\n</web-app>|" "$web_xml"
        fi
        print_success "[OK] Métodos TRACE/TRACK deshabilitados."
    fi

    # --- 3. Agregar headers de seguridad via FilterDef en web.xml ---
    if [[ -f "$web_xml" ]] && ! grep -q "X-Frame-Options" "$web_xml"; then
        sed -i "s|</web-app>|    <filter>\n        <filter-name>SecurityHeaders</filter-name>\n        <filter-class>org.apache.catalina.filters.HttpHeaderSecurityFilter</filter-class>\n        <init-param><param-name>antiClickJackingEnabled</param-name><param-value>true</param-value></init-param>\n        <init-param><param-name>antiClickJackingOption</param-name><param-value>SAMEORIGIN</param-value></init-param>\n        <init-param><param-name>blockContentTypeSniffingEnabled</param-name><param-value>true</param-value></init-param>\n    </filter>\n    <filter-mapping>\n        <filter-name>SecurityHeaders</filter-name>\n        <url-pattern>/*</url-pattern>\n    </filter-mapping>\n</web-app>|" "$web_xml"
        print_success "[OK] Headers de seguridad añadidos via HttpHeaderSecurityFilter."
    fi

    print_success "[OK] Hardening de Tomcat aplicado."
}

# -----------------------------------------------------------------------------
# CREAR INDEX.JSP PERSONALIZADO PARA TOMCAT
# Tomcat sirve desde /var/lib/tomcat/webapps/ROOT
# -----------------------------------------------------------------------------
crear_index_tomcat() {
    local version="$1"
    local puerto="$2"
    local ruta_web="/var/lib/tomcat/webapps/ROOT"

    mkdir -p "$ruta_web"

    cat > "${ruta_web}/index.jsp" <<EOF
<!DOCTYPE html>
<html lang="es">
<head>
  <meta charset="UTF-8">
  <title>Servidor Web - Tomcat</title>
  <style>
    body { font-family: monospace; background:#1e1e1e; color:#d4d4d4;
           display:flex; justify-content:center; align-items:center; height:100vh; margin:0; }
    .card { background:#252526; border:1px solid #3c3c3c; padding:2rem 3rem;
            border-radius:8px; text-align:center; }
    h1 { color:#4ec9b0; }
    span { color:#ce9178; }
  </style>
</head>
<body>
  <div class="card">
    <h1>&#x2705; Servidor Activo</h1>
    <p>Servidor : <span>Tomcat</span></p>
    <p>Versión  : <span>$version</span></p>
    <p>Puerto   : <span>$puerto</span></p>
  </div>
</body>
</html>
EOF

    print_success "[OK] index.jsp creado en $ruta_web"
}

# -----------------------------------------------------------------------------
# HABILITAR Y ARRANCAR TOMCAT
# -----------------------------------------------------------------------------
iniciar_tomcat() {
    print_title "Iniciando servicio Tomcat"

    systemctl enable tomcat &>/dev/null
    systemctl restart tomcat

    if systemctl is-active --quiet tomcat; then
        print_success "[OK] Tomcat activo y corriendo."
    else
        print_warning "[ERROR] Tomcat no pudo iniciar. Revisa: journalctl -xe"
        return 1
    fi
}

# -----------------------------------------------------------------------------
# FLUJO COMPLETO DE TOMCAT
# Llamada única desde main.sh
# -----------------------------------------------------------------------------
setup_tomcat() {
    obtener_versiones_tomcat                                                       || return 1
    pedir_puerto                                                                   || return 1
    instalar_tomcat                                                                || return 1
    configurar_puerto_tomcat     "$PUERTO_ELEGIDO"                                || return 1
    aplicar_seguridad_tomcat                                                       || return 1
    abrir_puerto_firewall        "$PUERTO_ELEGIDO"                                || return 1
    crear_usuario_servicio       "tomcat" "/var/lib/tomcat"                       || return 1
    crear_index_tomcat           "$VERSION_ELEGIDA" "$PUERTO_ELEGIDO"             || return 1
    iniciar_tomcat                                                                 || return 1

    echo ""
    print_success "================================================"
    print_success "  Tomcat desplegado exitosamente"
    print_success "  URL : http://localhost:$PUERTO_ELEGIDO"
    print_success "  Ver.: $VERSION_ELEGIDA"
    print_success "================================================"
}