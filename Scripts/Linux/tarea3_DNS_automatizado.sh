# Tarea 3 - Automatizacióin del Servidor DNS

# ----------Colores para que sea mas intuitivo ----------
rojo='\033[0;31m'
amarillo='\033[1;33m'
verde='\033[0;32m'
azul='\033[1;34m'
cyan='\033[0;36m'
nc='\033[0m'

# Variables globales
domain=""
ip=""
interface=""
mode=""
server_ip=""
named_conf="/etc/named.conf"
ZONES_DIR="/var/lib/named"
NAMED_SERVICE="named"
LOG_DIR="/var/log/named"
FORCE=false
BACKUP=false
DRY_RUN=false
CONFIGURE_DNS=false
EVIDENCE_FILE="/tmp/dns-test-evidence-$(date +%Y%m%d-%H%M%S).log"

# ---------- Funciones ----------

ayuda() {
    # Todas las opciones
    echo "Uso del script: $0"
    echo "Opciones:"
    echo -e "  ${azul}-v, --verify       ${nc}Verifica si esta instalado BIND9"
    echo -e "  ${azul}-i, --install      ${nc}Instala BIND9"
    echo -e "  ${azul}-m, --monitor      ${nc}Monitorear servidor DNS"
    echo -e "  ${azul}-r, --restart      ${nc}Reiniciar servidor DNS"
    echo -e "  ${azul}-c, --configurar   ${nc}Configurar servidor DNS"
    echo -e "  ${azul}-?, --help         ${nc}Muestra esta ayuda/menu"
}

print_warning(){
    echo -e "${rojo}$1${nc}"
}

print_success(){
    echo -e "${verde}$1${nc}"
}

print_info(){
    echo -e "${amarillo}$1${nc}"
}

validate_domain() {
    local domain="$1"
    
    # Regex para validar dominio
    local domain_regex='^([a-zA-Z0-9]([-a-zA-Z0-9]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$'
    
    if [[ ! $domain =~ $domain_regex ]]; then
        print_warning "Formato de dominio inválido: $domain"
        return 1
    fi
    
    return 0
}


validar_IP(){
	# Variable
	local ip="$1"

	# Validar formato X.X.X.X solo con numeros
	if ! [[ "$ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
		print_warning "Direccion IP invalida, tiene que contener un formato X.X.X.X unicamente con numeros positivos"
        return 1
    fi
	
	# Validar cada octeto entre 0 y 255
    IFS='.' read -r a b c d <<< "$ip"
	if [[ "$a" -eq 0  || "$d" -eq 0 ]]; then
		print_warning "Direccion IP invalida, no puede ser 0.X.X.X ni X.X.X.0"
		return 1
	fi
	
	# Validar que no tenga 0 al izquierda y que no pasen los rangos de 8 bits
	for octeto in $a $b $c $d; do
	if [[ "$octeto" =~ ^0[0-9]+ ]]; then
		print_warning "Direccion IP invalida, no se pueden poner 0 a la izquierda a menos que sea 0"
		return 1
	fi
		if [[ "$octeto" -lt 0 || "$octeto" -gt 255 ]]; then
				print_warning "Direccion IP invalida, no puede ser mayor a 255 ni menor a 0"
				return 1
		fi
	done

	# Validar que no sea 0.0.0.0 ni 255.255.255.255
	if [[ "$ip" = "0.0.0.0" || "$ip" = "255.255.255.255" ]]; then
		print_warning "Direccion IP invalida, no puede ser 0.0.0.0 ni 255.255.255.255"
		return 1
	fi

    # Validar los espacios reservados para uso experimental (127.0.0.1-127.255.255.255)
	if [[ "$a" -eq 127 ]]; then
		print_warning "Direccion IP invalida, las direcciones del rango 127.0.0.1 al 127.255.255.255 estan reservadas para host local"
		return 1
	fi

    # Validar los espacios reservados para multicast (224.0.0.0-239.255.255.255)
	if [[ "$a" -gt 224 && "$a" -lt 239 ]]; then
		print_warning "Direccion IP invalida, las direcciones del rango 224.0.0.0 al 239.255.255.255 estan reservadas para multicast"
		return 1
	fi

	# Validar los espacios reservados para uso experimental (240.0.0.0-255.255.255.254)
	if [[ "$a" -gt 240 && "$a" -lt 255 ]]; then
		print_warning "Direccion IP invalida, las direcciones del rango 240.0.0.0 al 255.255.255.254 estan reservadas para usos experimentales"
		return 1
	fi
    
    return 0
}

verificar_Instalacion() {
    print_info "Verificando instalación de BIND9..."
    
    if rpm -q bind &>/dev/null; then
        local version=$(rpm -q bind --queryformat '%{VERSION}')
        print_success "BIND9 ya está instalado (versión: $version)"
        return 0
    fi
    
    if command -v named &>/dev/null; then
        local version=$(named -v 2>&1 | head -1)
        print_success "BIND9 encontrado: $version"
        return 0
    fi
    
    if systemctl list-unit-files 2>/dev/null | grep -q "^named.service"; then
        print_success "Servicio named encontrado en systemd"
        return 0
    fi
    
    print_warning "BIND9 no está instalado"
    return 1
}

# Instalar BIND9 en openSUSE
install_bind9() {
    if verificar_Instalacion; then
        print_info "BIND9 ya está instalado"
        echo -ne "${amarillo}¿Desea reconfigurar el servidor DNS? [s/N]: ${nc}"
        read -r reconf
        if [[ ! "$reconf" =~ ^[Ss]$ ]]; then
            print_info "Operación cancelada"
            return 0
        fi
    else
        # -----------------------------------------------
        # PASO 2: Instalar paquetes
        # -----------------------------------------------
        print_info "Instalando BIND9 y utilidades..."

        print_info "Actualizando repositorios..."
        zypper refresh &>/dev/null

        print_info "Instalando paquete bind..."
        if zypper install -y bind &>/dev/null; then
            print_success "Paquete bind instalado correctamente"
        else
            print_warning "Error al instalar bind"
            return 1
        fi

        print_info "Instalando paquete bind-utils..."
        if zypper install -y bind-utils &>/dev/null; then
            print_success "Paquete bind-utils instalado correctamente"
        else
            print_warning "Error al instalar bind-utils (no crítico)"
        fi
    fi

    # -----------------------------------------------
    # PASO 3: Generar named.conf
    # -----------------------------------------------
    print_info "Generando archivo de configuración $named_conf..."

    # Crear directorio de zonas si no existe
    if [[ ! -d "$ZONES_DIR" ]]; then
        mkdir -p "$ZONES_DIR"
        print_success "Directorio de zonas creado: $ZONES_DIR"
    fi

    cat > "$named_conf" <<EOF
# Archivo de configuración de BIND9
# Generado automáticamente por dns-setup.sh
# $(date)

options {
    directory "$ZONES_DIR";
    listen-on { any; };
    allow-query { any; };
    recursion no;
    forwarders { };
    allow-transfer { none; };
};

zone "localhost" {
    type master;
    file "localhost.zone";
};

zone "0.in-addr.arpa" {
    type master;
    file "0.in-addr.arpa.zone";
};

zone "127.in-addr.arpa" {
    type master;
    file "127.in-addr.arpa.zone";
};
EOF

    # Verificar sintaxis de named.conf
    if named-checkconf "$named_conf" 2>/dev/null; then
        print_success "Archivo named.conf generado correctamente"
    else
        print_warning "Error en la sintaxis de named.conf"
        return 1
    fi

    # -----------------------------------------------
    # PASO 4: Habilitar el servicio
    # -----------------------------------------------
    print_info "Habilitando servicio named en el arranque..."
    if systemctl enable named 2>/dev/null; then
        print_success "Servicio named habilitado"
    else
        print_warning "No se pudo habilitar el servicio named"
        return 1
    fi

    # -----------------------------------------------
    # PASO 5: Iniciar el servicio
    # -----------------------------------------------
    print_info "Iniciando servicio named..."

    if systemctl is-active --quiet named; then
        print_info "Servicio ya estaba activo, reiniciando..."
        if systemctl restart named 2>/dev/null; then
            print_success "Servicio named reiniciado"
        else
            print_warning "Error al reiniciar el servicio named"
            return 1
        fi
    else
        if systemctl start named 2>/dev/null; then
            print_success "Servicio named iniciado"
        else
            print_warning "Error al iniciar el servicio named"
            print_warning "Revise los logs: journalctl -u named"
            return 1
        fi
    fi

    # -----------------------------------------------
    # PASO 6: Configurar firewall
    # -----------------------------------------------
    print_info "Configurando firewall para DNS (puerto 53)..."

    if command -v firewall-cmd &>/dev/null; then
        if firewall-cmd --add-service=dns --permanent 2>/dev/null; then
            print_success "Puerto 53 abierto en firewall (permanente)"
        else
            print_warning "No se pudo configurar el firewall"
        fi

        if firewall-cmd --reload 2>/dev/null; then
            print_success "Firewall recargado"
        else
            print_warning "No se pudo recargar el firewall"
        fi
    else
        print_warning "firewalld no encontrado, configure el firewall manualmente"
        print_warning "Abra el puerto 53 TCP y UDP"
    fi

    # -----------------------------------------------
    # PASO 7: Verificar que todo funciona
    # -----------------------------------------------
    print_info "Verificando estado del servidor DNS..."
    echo ""

    if systemctl is-active --quiet named; then
        print_success "Servicio named    : activo y corriendo"
    else
        print_warning "Servicio named    : NO está corriendo"
        return 1
    fi

    if ss -tulnp 2>/dev/null | grep -q ":53 "; then
        print_success "Puerto 53         : escuchando"
    else
        print_warning "Puerto 53         : NO está escuchando"
    fi

    if named-checkconf "$named_conf" 2>/dev/null; then
        print_success "Configuración     : sintaxis correcta"
    else
        print_warning "Configuración     : hay errores de sintaxis"
    fi

    echo ""
    print_success "========================================"
    print_success " BIND9 instalado y configurado          "
    print_success "========================================"
    echo ""
    print_info "Siguiente paso: agregar dominios con"
    print_info "  $0 --monitor"
}

agregar_dominio() {
    print_info "Agregar Dominio"

    # Pedir nombre del dominio
    echo -ne "${azul}[i]${nc} Ingrese el nombre del dominio (ej: reprobados.com): "
    read -r nuevo_dominio

    # Validar dominio
    if ! validate_domain "$nuevo_dominio"; then
        print_warning "Dominio inválido, cancelando operación"
        return 1
    fi

    # Verificar si el dominio ya existe en named.conf
    if grep -q "zone \"$nuevo_dominio\"" "$named_conf" 2>/dev/null; then
        print_warning "El dominio $nuevo_dominio ya está configurado"
        return 1
    fi

    # Pedir IP del dominio
    echo -ne "${azul}[i]${nc} Ingrese la IP para $nuevo_dominio: "
    read -r nueva_ip

    # Validar IP
    if ! validar_IP "$nueva_ip"; then
        print_warning "IP inválida, cancelando operación"
        return 1
    fi

    # Crear archivo de zona
    local zone_file="$ZONES_DIR/${nuevo_dominio}.zone"
    local serial=$(date +%Y%m%d01)

    print_info "Creando archivo de zona: $zone_file"

    cat > "$zone_file" <<EOF
\$TTL 86400
@   IN  SOA ns1.$nuevo_dominio. admin.$nuevo_dominio. (
            $serial ; Serial
            3600        ; Refresh
            1800        ; Retry
            604800      ; Expire
            86400 )     ; Minimum TTL

; Name Server
@           IN  NS      ns1.$nuevo_dominio.

; Registros A
@           IN  A       $nueva_ip
ns1         IN  A       $nueva_ip

; Registro CNAME
www         IN  CNAME   $nuevo_dominio.
EOF

    # Verificar sintaxis del archivo de zona
    if ! named-checkzone "$nuevo_dominio" "$zone_file" &>/dev/null; then
        print_warning "Error en la sintaxis del archivo de zona"
        rm -f "$zone_file"
        return 1
    fi

    print_success "Archivo de zona creado correctamente"

    # Agregar zona a named.conf
    print_info "Agregando zona a $named_conf..."

    cat >> "$named_conf" <<EOF

zone "$nuevo_dominio" {
    type master;
    file "$zone_file";
};
EOF

    # Verificar sintaxis de named.conf
    if ! named-checkconf "$named_conf" &>/dev/null; then
        print_warning "Error en la sintaxis de named.conf"
        return 1
    fi

    print_success "Zona agregada a named.conf correctamente"

    # Recargar BIND9 para aplicar cambios
    print_info "Recargando servicio BIND9..."
    if systemctl reload named &>/dev/null; then
        print_success "Servicio recargado correctamente"
    else
        print_warning "No se pudo recargar el servicio, intente: systemctl reload named"
    fi

    echo ""
    print_success "Dominio $nuevo_dominio agregado exitosamente"
    print_info "  - IP configurada: $nueva_ip"
    print_info "  - Registro A: $nuevo_dominio → $nueva_ip"
    print_info "  - Registro CNAME: www.$nuevo_dominio → $nuevo_dominio"
    print_info "  - Archivo de zona: $zone_file"
}

eliminar_dominio() {
    print_info "Eliminar Dominio"

    # Listar dominios disponibles
    listar_dominios
    echo ""

    # Pedir dominio a eliminar
    echo -ne "${azul}[i]${nc} Ingrese el dominio a eliminar: "
    read -r dominio_eliminar

    # Verificar que el dominio existe
    if ! grep -q "zone \"$dominio_eliminar\"" "$named_conf" 2>/dev/null; then
        print_warning "El dominio $dominio_eliminar no existe en la configuración"
        return 1
    fi

    # Pedir confirmación
    echo ""
    print_warning "¿Está seguro de eliminar el dominio $dominio_eliminar? [y/n]: "
    read -r confirmacion

    if [[ ! "$confirmacion" =~ ^[Yy]$ ]]; then
        print_info "Operación cancelada por el usuario"
        return 0
    fi

    local zone_file="$ZONES_DIR/${dominio_eliminar}.zone"

    # Eliminar entrada de named.conf
    print_info "Eliminando entrada de named.conf..."

    # Eliminar bloque de la zona en named.conf
    sed -i "/zone \"$dominio_eliminar\"/,/^};/d" "$named_conf"

    # Verificar sintaxis de named.conf
    if named-checkconf "$named_conf" &>/dev/null; then
        print_success "Entrada eliminada de named.conf"
    else
        print_warning "Error en named.conf después de eliminar, revise manualmente"
        return 1
    fi

    # Eliminar archivo de zona
    if [[ -f "$zone_file" ]]; then
        print_info "Eliminando archivo de zona: $zone_file"
        rm -f "$zone_file"
        print_success "Archivo de zona eliminado"
    else
        print_warning "Archivo de zona no encontrado: $zone_file"
    fi

    # Recargar BIND9
    print_info "Recargando servicio BIND9..."
    if systemctl reload named 2>/dev/null; then
        print_success "Servicio recargado correctamente"
    else
        # Si reload falla, intentar restart
        print_warning "reload falló, intentando restart..."
        if systemctl restart named 2>/dev/null; then
            print_success "Servicio reiniciado correctamente"
        else
            print_warning "No se pudo recargar el servicio"
            print_warning "Ejecute manualmente: systemctl restart named"
        fi
    fi

    print_success "Dominio $dominio_eliminar eliminado exitosamente"
}

listar_dominios() {
    print_info "Dominios Configurados"

    # Verificar que named.conf existe
    if [[ ! -f "$named_conf" ]]; then
        print_warning "No se encontró el archivo $named_conf"
        return 1
    fi

    # Extraer zonas configuradas
    local dominios=($(grep "^zone " "$named_conf" | awk -F'"' '{print $2}' | grep -v "localhost\|0.in-addr\|127.in-addr"))

    if [[ ${#dominios[@]} -eq 0 ]]; then
        print_warning "No hay dominios configurados"
        return 0
    fi

    # Encabezado de tabla
    echo ""
    printf "%-30s %-20s %-15s$\n" "DOMINIO" "IP CONFIGURADA" "ESTADO"
    echo "──────────────────────────────────────────────────────────────"

    # Mostrar cada dominio con su IP
    for dominio in "${dominios[@]}"; do
        local zone_file="$ZONES_DIR/${dominio}.zone"
        local ip="N/A"
        local estado="${rojo}Sin archivo de zona${nc}"

        if [[ -f "$zone_file" ]]; then
            # Extraer IP del registro A del dominio raíz
            ip=$(grep "^@\s*IN\s*A\|^@\t*IN\t*A" "$zone_file" 2>/dev/null | awk '{print $NF}')
            [[ -z "$ip" ]] && ip="N/A"
            estado="${verde}Activo${nc}"
        fi

        printf "%-30s %-20s " "$dominio" "$ip"
        echo -e "$estado"
    done

    echo ""
    print_info "Total de dominios: ${#dominios[@]}"
}

monitoreo() {
    while true; do
        echo ""
        echo -e "${cyan}"
        echo "╔════════════════════════════════════════════════════════════╗"
        echo "║              Menú de Monitoreo DNS                        ║"
        echo "╚════════════════════════════════════════════════════════════╝"
        echo -e "${nc}"

        echo -e "  ${verde}1)${nc} Agregar dominio"
        echo -e "  ${rojo}2)${nc} Eliminar dominio"
        echo -e "  ${azul}3)${nc} Listar dominios"
        echo -e "  ${amarillo}0)${nc} Salir"
        echo ""
        echo -ne "Opcion: "
        read -r opcion

        case $opcion in
            1) agregar_dominio ;;
            2) eliminar_dominio ;;
            3) listar_dominios ;;
            0)
                print_info "Saliendo del menú de monitoreo"
                break
                ;;
            *)
                print_warning "Opcion inválida: $opcion"
                ;;
        esac
    done
}

# ---------- Main ----------
case $1 in
    -v | --verify) verificar_Instalacion ;;
    -i | --install) install_bind9 ;;
    -m | --monitor) monitoreo ;;
    # -r | --restart) reiniciar_DHCP ;;
    # -c | --config) configurar_DHCP ;;
    -? | --help) ayuda ;;
esac