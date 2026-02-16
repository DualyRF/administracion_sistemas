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

# ---------- Funciones ----------

ayuda() {
    # Todas las opciones
    echo "Uso del script: $0"
    echo "Opciones:"
    echo -e "  ${azul}-v, --verify       ${nc}Verifica si esta instalado BIND9"
    echo -e "  ${azul}-i, --install      ${nc}Instala BIND9"
    echo -e "  ${azul}-m, --monitor      ${nc}Monitorear servidor DNS"
    echo -e "  ${azul}-r, --restart      ${nc}Reiniciar servidor DHCP"
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
    return 0

	# Validar los espacios reservados para uso experimental (240.0.0.0-255.255.255.254)
	if [[ "$a" -gt 240 && "$a" -lt 255 ]]; then
		print_warning "Direccion IP invalida, las direcciones del rango 240.0.0.0 al 255.255.255.254 estan reservadas para usos experimentales"
		return 1
	fi
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
    
    # Verificar que no esté ya instalado
    if verificar_Instalacion; then
        print_info "BIND9 ya está instalado, omitiendo instalación"
        return 0
    fi
    
    print_info "Instalando BIND9 y utilidades..."
    
    # Refrescar repositorios
    print_info "Actualizando repositorios..."
    zypper refresh &>/dev/null
    
    # Instalar paquetes necesarios
    print_info "Instalando paquete bind..."
    if zypper install -y bind &>/dev/null; then
        print_success "Paquete bind instalado correctamente"
    else
        print_warning "Error al instalar bind"
        return 1
    fi
    
    print_info "Instalando paquete bind-utils (herramientas DNS)..."
    if zypper install -y bind-utils &>/dev/null; then
        print_success "Paquete bind-utils instalado correctamente"
    else
        print_warning "Error al instalar bind-utils"
    fi
    
    # Verificar instalación
    if verificar_Instalacion; then
        print_success "BIND9 instalado exitosamente"
        
        # Mostrar versión instalada
        local version=$(rpm -q bind --queryformat '%{VERSION}')
        print_info "Versión instalada: $version"
        
        return 0
    else
        print_warning "La instalación parece haber fallado"
        return 1
    fi
}

# ---------- Main ----------
case $1 in
    -v | --verify) verificar_Instalacion ;;
    -i | --install) install_bind9 ;;
    # -m | --monitor) monitorear_Clientes ;;
    # -r | --restart) reiniciar_DHCP ;;
    # -c | --config) configurar_DHCP ;;
    -? | --help) ayuda ;;
esac