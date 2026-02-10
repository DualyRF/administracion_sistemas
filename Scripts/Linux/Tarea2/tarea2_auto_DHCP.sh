#Tarea 2 - Automatizacion y gestion del servidor DHCP'

#Colores para que sea mas intuitivo
rojo='\033[0;31m'
amarillo='\033[1;33m'
verde='\033[0;32m'
nc='\033[0m'

#Variables globales
nombre_IP=""
ip_Inicial=""
ip_Final=""
tiempo_Sesion=""
gateway=""
dns=""

#Funciones
validar_IP() {
    	local ip="$1"
	
    	# Validar formato X.X.X.X solo con numeros
    	if ! [[ "$ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
    	    echo -e "${rojo}Direccion IP invalida, tiene que contener un formato X.X.X.X unicamente con numeros positivos${nc}"
        	return 1
   	fi

	# Validar que no sea 0.0.0.0 ni 255.255.255.255
	if [ "$ip" = "0.0.0.0" || "$ip" = "255.255.255.255"]; then
		echo -e "${rojo}Direccion IP invalida, no puede ser 0.0.0.0 ni 255.255.255.255${nc}"
	fi 
	
	# Validar cada octeto entre 0 y 255
    	IFS='.' read -r a b c d <<< "$ip"

    	for octeto in $a $b $c $d; do
        	if (( octeto < 0 || octeto > 255 )); then
            	echo -e "${rojo}Direccion IP invalida, no puede ser mayor a 255 ni menor a 0${nc}"
            	return 1
        	fi
    	done

    	return 0
}  

bucle_Verificacion(){
	msg=("Rango inicial de la IP:",  "Rango final de la IP:")
	if [ "$opc" -e 1]; then
		
	fi else
}

verificar_Instalacion(){
	# Entregable 1
	# Comprobar si esta instalada la paqueteria de DHCP
	
	echo -e "${amarillo}Verificando paqueteria DHCP...${nc}"
	if ! zypper search --installed-only | grep -q dhcp; then
		echo -e "${rojo}DHCP no esta instalado${nc}"
		read -p "Desea instalarlo?" opc
		if ! zypper search --installed-only | grep -q dhcp; then
			echo -e "${rojo}Tiene que instalar dhcp para poder continuar, vuelvalo a intentar...${nc}"
			exit
		fi
	fi
}

instalar_DHCP(){
	sudo zypper --non-interactive install dhcp-server
	echo -e "${verde}DHCP esta instalado, continuando con la configuracion...${nc}"
}

configurar_DHCP(){
	# Entregable 2
	local ip_Valida="no"

	echo -e "\nConfiguracion Dinamica\n"

	read -p "Nombre descriptivo del Ambito: " nombre_IP
	until
		read -p "Rango inicial de la IP: " ip_Inicial && \
		validar_IP "$ip_Inicial"
	do
		echo -e "Intentando nuevamente..."
	done

	until  [ "$ip_Valida" = "si" ]; do
		read -p "Rango final de la IP:" ip_Final
		if validar_IP "$ip_Final" then
			if [ $(echo "$ip_Final" | cut -d'.' -f4) -gt $(echo "$ip_Inicio" | cut -d'.' -f4) ] && \
			   [ $(echo "$ip_Final" | cut -d'.' -f1-3) -e $(echo "$ip_Inicio" | cut -d'.' -f1-3) ]; then
				ip_Valida="si"
			else
				echo -e "${rojo}La IP no concuerda con el rango incial${nc}"
			fi
		fi
		
		if "$ip_Valida" = "no"; then
			echo -e "Intendo nuevamente..."
		fi
	done

	read -p "Tiempo de la sesion: " tiempo_Sesion

	until
		read -p "Gateway: " gateway && \
		validar_IP "$gateway"
	do
		echo -e "Intentado nuevamente..."
	done
	until	
		read -p "DNS: " dns && \
		validar_IP "$dns"
	do
		echo -e "Intentado nuevamente..."
	done
}

configurar_DHCP

