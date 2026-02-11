#Tarea 2 - Automatizacion y gestion del servidor DHCP'

# ----------Colores para que sea mas intuitivo ----------
rojo='\033[0;31m'
amarillo='\033[1;33m'
verde='\033[0;32m'
azul='\033[1;34m'
nc='\033[0m'

# ---------- Variables globales ----------

# ---------- Funciones ----------

ayuda() {
    # Todas las opciones
    echo "Uso del scrpit: $0"
    echo "Opciones:"
    echo -e "  ${azul}-v, --verify       ${nc}Verifica si esta instalada la paqueteria DHCP"
    echo -e "  ${azul}-i, --install      ${nc}Instala la paquteria DHCP"
    echo -e "  ${azul}-c, --configurar   ${nc}Configurar servidor DHCP"
    echo -e "  ${azul}-?, --help         ${nc}Muestra esta ayuda/menu"
}

calcular_Rango(){
	local ip1=$1
	local ip2=$2
	local n=0
	local rango1=0
	local rango2=0
	local rangof=0
	local pot=0

	IFS='.' read -ra octetosIni <<< "$ip1"
	IFS='.' read -ra octetosFin <<< "$ip2"

	for ((i=3; i>=0; i--)); do
		pot=$(( 255 ** n ))
		rango1=$(( (${octetosIni[i]} * pot) + rango1))
		rango2=$(( (${octetosFin[i]} * pot) + rango2))
		n=$(( n + 1 ))
	done

	echo $(( rango2 - rango1 ))
}

calcular_Bits(){
	local masc="$1"
	count=0
	IFS='.' read -r a b c d <<< "$masc"
	for octeto in $d $c $b $a; do
		n=255
		if [ $octeto -eq 0 ]; then
			count=$(( count + 8 ))
			continue
		elif [ $octeto -eq 255 ]; then
			echo $count
			return 0
		else
		for i in {0..7}; do
			n=$(( n - (2 ** i) ))
			count=$(( count + 1 ))
			if [[ $n -eq $octeto ]]; then
				echo $count
				return 0
			fi
		done
		fi
	done
	return 0
}

validar_IP_Masc(){
	local comp=""
	local mascRang="$3"
	local n=255
	local count=0¿

	local rango=$(calcular_Rango "$1" "$2")
	mascRang=$(calcular_Bits "$mascRang")
	mascRang=$(( (2 ** mascRang) - 2 ))
	if [ $rango -gt $mascRang ]; then
		echo -e "${rojo}La mascara $3 no es suficiente para el rango de IPs que desea asginar${nc}"
		return 1
	fi
	return 0
}

validar_IP(){
	# Variable
	local ip="$1"
	echo -e "${rojo}"

	# Validar formato X.X.X.X solo con numeros
	if ! [[ "$ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
		echo -e "Direccion IP invalida, tiene que contener un formato X.X.X.X unicamente con numeros positivos${nc}"
    	return 1
   	fi
	
	# Validar cada octeto entre 0 y 255
    	IFS='.' read -r a b c d <<< "$ip"
	if [[ "$a" -eq 0  || "$d" -eq 0 ]]; then
		echo -e "Direccion IP invalida, no puede ser 0.X.X.X ni X.X.X.0${nc}"
		return 1
	fi
	
	# Validar que no tenga 0 al izquierda y que no pasen los rangos de 8 bits
	for octeto in $a $b $c $d; do
	if [[ "$octeto" =~ ^0[0-9]+ ]]; then
		echo -e "Direccion IP invalida, no se pueden poner 0 a la izquierda a menos que sea 0${nc}"
		return 1
	fi
		if [[ "$octeto" -lt 0 || "$octeto" -gt 255 ]]; then
				echo -e "Direccion IP invalida, no puede ser mayor a 255 ni menor a 0${nc}"
				return 1
		fi
	done

	# Validar que no sea 0.0.0.0 ni 255.255.255.255
	if [[ "$ip" = "0.0.0.0" || "$ip" = "255.255.255.255" ]]; then
		echo -e "Direccion IP invalida, no puede ser 0.0.0.0 ni 255.255.255.255${nc}"
		return 1
	fi

    # Validar los espacios reservados para uso experimental (127.0.0.1-127.255.255.255)
	if [[ "$a" -eq 127 ]]; then
		echo -e "Direccion IP invalida, las direcciones del rango 127.0.0.1 al 127.255.255.255 estan reservadas para host local${nc}"
		return 1
	fi

	# Validar los espacios reservados para uso experimental (240.0.0.0-255.255.255.254)
	if [[ "$a" -gt 240 && "$a" -lt 255 ]]; then
		echo -e "Direccion IP invalida, las direcciones del rango 240.0.0.0 al 255.255.255.254 estan reservadas para usos experimentales${nc}"
		return 1
	fi

	# Validar los espacios reservados para multicast (224.0.0.0-239.255.255.255)
	if [[ "$a" -gt 224 && "$a" -lt 239 ]]; then
		echo -e "Direccion IP invalida, las direcciones del rango 224.0.0.0 al 239.255.255.255 estan reservadas para multicast${nc}"
		return 1
	fi

	echo -e "${nc}"
    	return 0
}

validar_Mascara(){
	local masc="$1"
	echo -e "${rojo}"
	
	# Validar formato X.X.X.X solo con numeros
    	if ! [[ "$masc" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
    		echo -e "Mascara invalida, tiene que contener un formato X.X.X.X unicamente con numeros positivos${nc}"
        	return 1
   	fi

	# Validar cada octeto entre 0 y 255
    	IFS='.' read -r a b c d <<< "$masc"
	if [ "$a" -eq 0 ]; then
		echo -e "Mascara invalida, no puede ser 0.X.X.X${nc}"
		return 1
	fi
	
	# Validar que no tenga 0 al izquierda y que no pasen los rangos de 8 bits
    	for octeto in $a $b $c $d; do
		if [[ "$octeto" =~ ^0[0-9]+ ]]; then
			echo -e "Mascara invalida, no se pueden poner 0 a la izquierda a menos que sea 0${nc}"
			return 1
		fi
        	if [[ "$octeto" -lt 0 || "$octeto" -gt 255 ]]; then
            		echo -e "Mascara invalida, no puede ser mayor a 255 ni menor a 0${nc}"
            		return 1
        	fi
    	done

	# Validar los bits de la mascara
	if [ "$a" -lt 255 ]; then
		for octeto in $b $c $d; do
			if [ "$octeto" -gt 0 ]; then
				echo -e "Mascara invalida, ocupas acabar los bits del primer octeto (255.X.X.X)${nc}"
				return 1
			fi
		done
	elif [ "$b" -lt 255 ]; then
		for octeto in $c $d; do
			if [ "$octeto" -gt 0 ]; then
				echo -e "Mascara invalida, ocupas acabar los bits del segundo octeto (255.255.X.X)${nc}"
				return 1
			fi
		done
	elif [ "$c" -lt 255 ]; then
		for octeto in $d; do
			if [ "$octeto" -gt 0 ]; then
				echo -e "Mascara invalida, ocupas acabar los bits del tercer octeto (255.255.255.X)${nc}"
				return 1
			fi
		done
	elif [ "$d" -gt 252 ]; then
		echo -e "Mascara invalida, no puede superar 255.255.255.252${nc}"
		return 1
	fi

	echo -e "${nc}"
	return 0
}

crear_Mascara(){
	local rango=$(calcular_Rango "$1" "$2")
	local n=0
	local bits=0
    local p=0
	local masc=255.255.255.255
    local octeto=0
	
	for i in {1..32}; do
		if [[ $n -ge $(( rango + 2 )) ]]; then
			break;
		else
			n=$(( 2 ** i ))
			bits=$(( bits + 1 ))
		fi
	done
	IFS='.' read -r -a a_masc <<< "$masc"
	for ((i=${#a_masc[@]}-1; i>=0; i--)); do
		octeto=${a_masc[i]}
        p=0
        until [ $octeto -eq 0 ] || [ $p -eq $bits ]; do
            octeto=$(( octeto - (2 ** p )))
            p=$(( p + 1 ))
        done
        if [ $p -eq $bits ]; then
            a_masc[i]=$octeto
            break;
        fi
        
        bits=$(( bits - 8))
		a_masc[i]=$octeto
	done
    IFS=" "
    octeto="${a_masc[*]}"
    octeto=${octeto// /.}
    echo "$octeto"
}

verificar_Instalacion(){
	# Comprobar si esta instalada la paqueteria de DHCP
	local opc

	echo -e "${amarillo}Verificando paqueteria DHCP...${nc}"
	if ! zypper search --installed-only | grep -q dhcp; then
		echo -e "${rojo}DHCP no esta instalado${nc}"
		read -p "Desea instalarlo? (y/n): " opc
		if [[ $opc = "y" ]]; then
            instalar_DHCP
			exit
		fi
	fi
}

instalar_DHCP(){
    # Instalar DHCP
	sudo zypper --non-interactive install dhcp-server
	echo -e "${verde}DHCP esta instalado, continuando con la configuracion...${nc}"
}

configurar_DHCP(){
	local ip_Valida=""
    local uso_Mas=""
    local comp=""

	echo -e "\nConfiguracion Dinamica\n"

	read -p "Nombre descriptivo del Ambito: " scope
	until [ "$masc_valida" = "si" ]; do
		read -p "Mascara (En blanco para asignar automaticamente): " mascara
		if [ "$mascara" != "" ]; then
			if validar_Mascara "$mascara"; then
                uso_Mas="si"
				masc_valida="si"
			fi
		else
			masc_valida="si"
		fi
	done
    
	until [ "$ip_Valida" = "si" ]; do
		read -p "Rango inicial de la IP (La primera IP se usara para asignarla al servidor): " ip_Inicial
		ip_Res=$(echo "$ip_Inicial" | cut -d'.' -f4)
		if [ $ip_Res -ne 255 ]; then
			ip_Res=$(( ip_Res + 1 ))
			ip_Inicial=$(echo "$ip_Inicial" | cut -d'.' -f1-3)
			ip_Inicial="$ip_Inicial.$ip_Res"
			if validar_IP "$ip_Inicial"; then
				ip_Valida="si"
			fi
		else
			echo -e "No use X.X.X.255 como ultimo octeto por temas de rendimiento"
			echo -e "Intentando nuevamente..."	
		fi
	done

	ip_Valida="no"

	until [ "$ip_Valida" = "si" ]; do
		read -p "Rango final de la IP: " ip_Final
		if validar_IP "$ip_Final"; then
			if [ 1 -gt 0 ]; then
    			if [ "$uso_Mas" = "si" ]; then
					if validar_IP_Masc "$ip_Inicial" "$ip_Final" "$mascara"; then
						ip_Valida="si"
					fi
				else
					mascara=$(crear_Mascara "$ip_Inicial" "$ip_Final")
					ip_Valida="si"
				fi
			else
    			echo -e "${rojo}La IP no concuerda con el rango inicial${nc}"
			fi   
		fi
		
		if [ "$ip_Valida" = "no" ]; then
			echo -e "Intendo nuevamente..."
		fi
	done

	read -p "Tiempo de la sesion (segundos): " lease_Time

	until
		read -p "Gateway: " gateway
		validar_IP "$gateway" 
	do
		echo -e "Intentado nuevamente..."
	done
	until [[ "$comp" = "si" ]]; do
		read -p "DNS principal (puede quedar vacio): " dns
        if [ "$dns" = "" ]; then
            dns=8.8.8.8
		    break;
        else   
            validar_IP "dns"
        fi
		echo -e "Intentado nuevamente..."
	done
    until [[ "$comp" = "si" ]]; do
		read -p "DNS alternativo (puede quedar vacio): " dns_Alt
        if [ "$dns_Alt" = "" ]; then
            dns_Alt=8.8.8.4
		    break;
        else   
            validar_IP "dns_Alt"
        fi
		echo -e "Intentado nuevamente..."
	done

    echo -e "La configuracion final es: \nNombre del ambito: $scope \nMascara: $mascara \nIP inicial: $ip_Inicial \nIP final: $ip_Final \nTiempo de consesion: $lease_Time \nGateway: $gateway \nDNS primario: $dns \nDNS alternativo: $dns_Alt"
    read -p "Acepta esta configuarcion? (y/n): " opc
    if [ $opc = "y" ]; then
    cat > /etc/dhcp/dhcpd.conf << EOF
    subnet 192.168.1.0 netmask $mascara {
        range $ip_Inicio $ip_Final;
        option routers $gateway;
        option domain-name-servers $dns, $dns_Alt;
        default-lease-time $lease_Time;
        max-lease-time $lease_Time;
        authoritative;
    }
    EOF

    systemctl restart isc-dhcp-server
    else
        echo -e "Volviendo a configfurar..."
        configurar_DHCP
    fi
}

# ---------- Main ----------
case $1 in
    -v | --verify) verificar_Instalacion ;;
    -i | --install) instalar_DHCP ;;
    -c | --config) configurar_DHCP ;;
    -? | --help) ayuda ;;
esac