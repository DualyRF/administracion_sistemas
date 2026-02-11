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
mascara=""

#Funciones
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
	local cont=0
	local masc=255.255.255.255
	
	for i in {1..32}; do
		if [[ $n -ge $(( rango + 2 )) ]]; then
			break;
		else
			n=$(( 2 ** i ))
			cont=$(( cont + 1 ))
		fi
	done
	IFS='.' read -r -a a_masc <<< "$masc"
	for ((i=${#a_masc[@]}-1; i>=0; i--)); do
		octeto=$a_masc[i]

		for ((p=n; p>=0; p--)); do
			echo "$p"
			if [[ $octeto -eq 0  || $n -eq 0 ]]; then
				n=$p
				break;
			else
				octeto=$(( octeto - (2 ** p )))
			fi
		done
		a_masc[i]=$octeto
		echo -e "$octeto"
	done
	echo $masc
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
	# ------------------------------------------- Validaciones -------------------------------------------
	local ip_Valida="no"

	echo -e "\nConfiguracion Dinamica\n"

	read -p "Nombre descriptivo del Ambito: " nombre_IP
	until [ "$masc_valida" = "si" ]; do
		read -p "Mascara (En blanco para usar predeterminada): " mascara
		if [ "$mascara" != "" ]; then
			if validar_Mascara "$mascara"; then
				masc_valida="si"
			fi
		else
			masc_valida="si"
		fi
	done
	until [ "$ip_Valida" = "si" ]; do
		read -p "Rango inicial de la IP (La primera IP se usara para asignarla al servidor): " ip_Inicial
		ip_Res=$(echo "$ip_Inicial" | cut -d'.' -f4)
		if [ $ip_Res -lt 255 ]; then
			ip_Res=$(( ip_Res + 1 ))
			ip_Inicial=$(echo "$ip_Inicial" | cut -d'.' -f1-3)
			ip_Inicial="$ip_Inicial.$ip_Res"
			if validar_IP "$ip_Inicial"; then
				ip_Valida="si"
			fi
		else
			echo -e "No use X.X.X.225 como ultimo octeto por temas de rendimiento"
			echo -e "Intentando nuevamente..."	
		fi
	done

	ip_Valida="no"

	until [ "$ip_Valida" = "si" ]; do
		read -p "Rango final de la IP: " ip_Final
		if validar_IP "$ip_Final"; then
			if [ 1 -gt 0 ]; then
    			if [ "$mascara" != "" ]; then
					if validar_IP_Masc "$ip_Inicial" "$ip_Final" "$mascara"; then
						ip_Valida="si"
					fi
				else
					mascara=$(crear_Mascara "$ip_Inicial" "$ip_Final")
					echo -e "$mascara"
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

	read -p "Tiempo de la sesion (segundos): " tiempo_Sesion

	until
		read -p "Gateway: " gateway
		validar_IP "$gateway"
	do
		echo -e "Intentado nuevamente..."
	done
	until	
		read -p "DNS: " dns
		validar_IP "$dns"
	do
		echo -e "Intentado nuevamente..."
	done
}

configurar_DHCP