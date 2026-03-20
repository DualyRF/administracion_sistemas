#!/bin/bash
#===============================================================================
# setup_ftp_repo.sh
# Práctica 7 - VM1: Servidor FTP Centralizado (OpenSUSE Leap 16)
# IP: 192.168.10.180
#
# Este script:
#   1. Instala y configura vsftpd
#   2. Crea la estructura de carpetas del repositorio
#   3. Descarga los binarios de Apache, Nginx y Tomcat (Linux y Windows)
#   4. Genera archivos .sha256 para validación de integridad
#
# Ejecutar como root: sudo bash setup_ftp_repo.sh
#===============================================================================

set -e

# ========================== COLORES ==========================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# ========================== VARIABLES ==========================
FTP_USER="ftpuser"
FTP_PASS="Practica7FTP"
FTP_BASE="/srv/ftp"
DOMAIN="reprobados.com"

# --- Versiones de software ---
APACHE_VER="2.4.66"
NGINX_VER="1.28.2"
TOMCAT_VER="10.1.52"

# --- URLs de descarga (Linux) ---
APACHE_LINUX_URL="https://dlcdn.apache.org/httpd/httpd-${APACHE_VER}.tar.gz"
NGINX_LINUX_URL="https://nginx.org/download/nginx-${NGINX_VER}.tar.gz"
TOMCAT_LINUX_URL="https://dlcdn.apache.org/tomcat/tomcat-10/v${TOMCAT_VER}/bin/apache-tomcat-${TOMCAT_VER}.tar.gz"

# --- URLs de descarga (Windows) ---
# Apache para Windows: Apache Lounge (si falla, descargar manualmente)
APACHE_WIN_URL="https://www.apachelounge.com/download/VS17/binaries/httpd-${APACHE_VER}-win64-VS17.zip"
NGINX_WIN_URL="https://nginx.org/download/nginx-${NGINX_VER}.zip"
TOMCAT_WIN_URL="https://dlcdn.apache.org/tomcat/tomcat-10/v${TOMCAT_VER}/bin/apache-tomcat-${TOMCAT_VER}-windows-x64.zip"

# ========================== FUNCIONES ==========================

print_header() {
    echo -e "\n${CYAN}============================================================${NC}"
    echo -e "${CYAN}  $1${NC}"
    echo -e "${CYAN}============================================================${NC}\n"
}

print_ok()   { echo -e "${GREEN}[OK]${NC} $1"; }
print_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
print_err()  { echo -e "${RED}[ERROR]${NC} $1"; }

check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_err "Este script debe ejecutarse como root (sudo bash $0)"
        exit 1
    fi
}

# ========================== PASO 1: INSTALAR VSFTPD ==========================

install_vsftpd() {
    print_header "PASO 1: Instalando vsftpd"

    if rpm -q vsftpd &>/dev/null; then
        print_ok "vsftpd ya esta instalado"
    else
        zypper --non-interactive install vsftpd
        print_ok "vsftpd instalado correctamente"
    fi

    # Instalar tree para visualizar estructura (opcional)
    zypper --non-interactive install tree 2>/dev/null || true

    # Crear usuario FTP si no existe
    if id "$FTP_USER" &>/dev/null; then
        print_ok "Usuario '$FTP_USER' ya existe"
    else
        useradd -m -s /bin/bash "$FTP_USER"
        echo "${FTP_USER}:${FTP_PASS}" | chpasswd
        print_ok "Usuario '$FTP_USER' creado (pass: ${FTP_PASS})"
    fi
}

# ========================== PASO 2: CONFIGURAR VSFTPD ==========================

configure_vsftpd() {
    print_header "PASO 2: Configurando vsftpd"

    # Backup
    if [[ -f /etc/vsftpd.conf && ! -f /etc/vsftpd.conf.bak.p7 ]]; then
        cp /etc/vsftpd.conf /etc/vsftpd.conf.bak.p7
        print_ok "Backup de vsftpd.conf creado"
    fi

    cat > /etc/vsftpd.conf << 'EOF'
# ==================================================
# vsftpd.conf - Practica 7 - Repositorio FTP
# ==================================================

# --- Acceso ---
anonymous_enable=NO
local_enable=YES
write_enable=YES
local_umask=022

# --- Directorio raiz del repositorio ---
local_root=/srv/ftp
chroot_local_user=YES
allow_writeable_chroot=YES

# --- Modo pasivo ---
pasv_enable=YES
pasv_min_port=30000
pasv_max_port=31000

# --- Logging ---
xferlog_enable=YES
xferlog_std_format=YES
log_ftp_protocol=YES
vsftpd_log_file=/var/log/vsftpd.log

# --- Conexion ---
listen=YES
listen_ipv6=NO
pam_service_name=vsftpd

# --- Banner ---
ftpd_banner=Repositorio FTP - Practica 7 - reprobados.com

# ==================================================
# SSL/TLS - DESCOMENTARR DESPUES CON EL ORQUESTADOR
# ==================================================
# ssl_enable=YES
# rsa_cert_file=/etc/ssl/certs/vsftpd.pem
# rsa_private_key_file=/etc/ssl/private/vsftpd.key
# allow_anon_ssl=NO
# force_local_data_ssl=YES
# force_local_logins_ssl=YES
# ssl_tlsv1_2=YES
# ssl_sslv2=NO
# ssl_sslv3=NO
# require_ssl_reuse=NO
# ssl_ciphers=HIGH
EOF

    print_ok "vsftpd.conf configurado"

    systemctl enable vsftpd
    systemctl restart vsftpd
    print_ok "Servicio vsftpd habilitado e iniciado"
}

# ========================== PASO 3: ESTRUCTURA DE CARPETAS ==========================

create_directory_structure() {
    print_header "PASO 3: Creando estructura de carpetas"

    local dirs=(
        "${FTP_BASE}/http/Linux/Apache"
        "${FTP_BASE}/http/Linux/Nginx"
        "${FTP_BASE}/http/Linux/Tomcat"
        "${FTP_BASE}/http/Windows/Apache"
        "${FTP_BASE}/http/Windows/Nginx"
        "${FTP_BASE}/http/Windows/Tomcat"
    )

    for dir in "${dirs[@]}"; do
        mkdir -p "$dir"
        print_ok "Creado: $dir"
    done

    chown -R "${FTP_USER}:users" "${FTP_BASE}/http"
    chmod -R 755 "${FTP_BASE}/http"
    print_ok "Permisos asignados"
}

# ========================== PASO 4: DESCARGAR BINARIOS ==========================

download_file() {
    local url="$1"
    local dest="$2"
    local filename
    filename=$(basename "$dest")

    if [[ -f "$dest" ]]; then
        print_warn "Ya existe: $filename (saltando)"
        return 0
    fi

    echo -e "  Descargando: ${YELLOW}${filename}${NC}"
    echo -e "  URL: ${url}"

    if curl -fSL --connect-timeout 30 --max-time 600 -o "$dest" "$url" 2>/dev/null; then
        local size
        size=$(du -h "$dest" | cut -f1)
        print_ok "Descargado: $filename ($size)"
        return 0
    else
        print_err "Fallo descarga: $filename"
        print_warn "Descargalo manualmente y colocalo en: $(dirname "$dest")/"
        print_warn "URL: $url"
        echo "PENDIENTE: Descargar de $url" > "${dest}.PENDIENTE"
        return 1
    fi
}

generate_sha256() {
    local file="$1"
    if [[ -f "$file" ]]; then
        # Formato: hash  nombre_archivo
        local hash
        hash=$(sha256sum "$file" | awk '{print $1}')
        echo "${hash}  $(basename "$file")" > "${file}.sha256"
        print_ok "SHA256: $(basename "${file}.sha256")"
    fi
}

download_all_binaries() {
    print_header "PASO 4: Descargando binarios"

    local failed=0

    echo -e "\n${CYAN}--- LINUX ---${NC}\n"

    download_file "$APACHE_LINUX_URL" \
        "${FTP_BASE}/http/Linux/Apache/httpd-${APACHE_VER}.tar.gz" || ((failed++))

    download_file "$NGINX_LINUX_URL" \
        "${FTP_BASE}/http/Linux/Nginx/nginx-${NGINX_VER}.tar.gz" || ((failed++))

    download_file "$TOMCAT_LINUX_URL" \
        "${FTP_BASE}/http/Linux/Tomcat/apache-tomcat-${TOMCAT_VER}.tar.gz" || ((failed++))

    echo -e "\n${CYAN}--- WINDOWS ---${NC}\n"

    download_file "$APACHE_WIN_URL" \
        "${FTP_BASE}/http/Windows/Apache/httpd-${APACHE_VER}-win64.zip" || ((failed++))

    download_file "$NGINX_WIN_URL" \
        "${FTP_BASE}/http/Windows/Nginx/nginx-${NGINX_VER}.zip" || ((failed++))

    download_file "$TOMCAT_WIN_URL" \
        "${FTP_BASE}/http/Windows/Tomcat/apache-tomcat-${TOMCAT_VER}-windows-x64.zip" || ((failed++))

    if [[ $failed -gt 0 ]]; then
        echo ""
        print_warn "$failed descarga(s) fallida(s). Revisa archivos .PENDIENTE"
    fi

    return 0
}

# ========================== PASO 5: GENERAR HASHES ==========================

generate_all_hashes() {
    print_header "PASO 5: Generando hashes SHA256"

    find "${FTP_BASE}/http" -type f \
        \( -name "*.tar.gz" -o -name "*.zip" -o -name "*.msi" \) | sort | while read -r file; do
        if [[ ! -f "${file}.sha256" ]] || [[ "$file" -nt "${file}.sha256" ]]; then
            generate_sha256 "$file"
        else
            print_ok "Hash vigente: $(basename "${file}.sha256")"
        fi
    done
}

# ========================== PASO 6: FIREWALL ==========================

configure_firewall() {
    print_header "PASO 6: Configurando firewall"

    if command -v firewall-cmd &>/dev/null; then
        firewall-cmd --permanent --add-service=ftp 2>/dev/null || true
        firewall-cmd --permanent --add-port=30000-31000/tcp 2>/dev/null || true
        # Puerto 443 para HTTPS (para cuando se instalen servicios HTTP aqui)
        firewall-cmd --permanent --add-service=https 2>/dev/null || true
        firewall-cmd --permanent --add-service=http 2>/dev/null || true
        firewall-cmd --reload 2>/dev/null || true
        print_ok "Firewall: FTP + pasivos (30000-31000) + HTTP/HTTPS"
    else
        print_warn "firewall-cmd no encontrado, configura manualmente"
    fi
}

# ========================== PASO 7: VERIFICACION ==========================

verify_setup() {
    print_header "PASO 7: Verificacion final"

    # Estado del servicio
    echo -e "${CYAN}--- Estado vsftpd ---${NC}"
    if systemctl is-active vsftpd &>/dev/null; then
        print_ok "vsftpd ACTIVO"
    else
        print_err "vsftpd NO esta corriendo"
    fi

    # Estructura
    echo -e "\n${CYAN}--- Estructura del repositorio ---${NC}"
    if command -v tree &>/dev/null; then
        tree "${FTP_BASE}/http" -h --du 2>/dev/null || \
            find "${FTP_BASE}/http" -type f | sort
    else
        find "${FTP_BASE}/http" -type f | sort
    fi

    # Hashes
    echo -e "\n${CYAN}--- Archivos con hash SHA256 ---${NC}"
    local hash_count=0
    find "${FTP_BASE}/http" -name "*.sha256" | sort | while read -r hf; do
        echo -e "  ${GREEN}✓${NC} $(basename "$hf")"
        ((hash_count++))
    done

    # Pendientes
    echo -e "\n${CYAN}--- Descargas pendientes ---${NC}"
    local pend
    pend=$(find "${FTP_BASE}/http" -name "*.PENDIENTE" 2>/dev/null)
    if [[ -z "$pend" ]]; then
        print_ok "Ninguna - todo descargado"
    else
        echo "$pend" | while read -r p; do
            print_warn "$(cat "$p")"
        done
    fi

    # Test FTP local
    echo -e "\n${CYAN}--- Test conexion FTP ---${NC}"
    if curl -s -u "${FTP_USER}:${FTP_PASS}" ftp://127.0.0.1/http/ --list-only &>/dev/null; then
        print_ok "Conexion FTP local exitosa"
        echo -e "  Carpetas en /http/:"
        curl -s -u "${FTP_USER}:${FTP_PASS}" ftp://127.0.0.1/http/ --list-only 2>/dev/null | sed 's/^/    /'
    else
        print_err "No se pudo conectar al FTP local"
        print_warn "Verifica vsftpd y credenciales"
    fi

    # Resumen
    echo ""
    print_header "RESUMEN"
    echo -e "  Servidor FTP:     ${GREEN}192.168.10.180${NC}"
    echo -e "  Usuario:          ${GREEN}${FTP_USER}${NC}"
    echo -e "  Contrasena:       ${GREEN}${FTP_PASS}${NC}"
    echo -e "  Directorio:       ${GREEN}${FTP_BASE}/http${NC}"
    echo -e "  Dominio SSL:      ${GREEN}${DOMAIN}${NC}"
    echo -e "  Puertos pasivos:  ${GREEN}30000-31000${NC}"
    echo ""
    echo -e "  ${CYAN}Comandos para probar desde otra VM:${NC}"
    echo -e "  curl -u ${FTP_USER}:${FTP_PASS} ftp://192.168.10.180/http/"
    echo -e "  curl -u ${FTP_USER}:${FTP_PASS} ftp://192.168.10.180/http/Linux/"
    echo -e "  curl -u ${FTP_USER}:${FTP_PASS} ftp://192.168.10.180/http/Windows/"
    echo ""
}

# ========================== MAIN ==========================

main() {
    print_header "PRACTICA 7 - SETUP SERVIDOR FTP CENTRALIZADO"
    echo -e "  VM1: OpenSUSE Leap 16 - 192.168.10.180"
    echo -e "  Fecha: $(date '+%Y-%m-%d %H:%M:%S')"

    check_root
    install_vsftpd
    configure_vsftpd
    create_directory_structure
    download_all_binaries
    generate_all_hashes
    configure_firewall
    verify_setup

    print_header "SETUP COMPLETADO"
    echo -e "  El repositorio FTP esta listo para usarse."
    echo -e "  Siguiente: ejecutar el orquestador en VM2 (Linux) o VM3 (Windows)."
    echo ""
}

main "$@"