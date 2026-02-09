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
ip_Correcta(){
	local ip1=0
	local ip2="$1"
	if [[ ! "$ip2" =~ ^[0-9]+\.+[0-9]+\.[0-9]+\.[0-9]+$ ]] then
		echo -e "${rojo}Direccion IP invalida, tiene que contener un formato X.X.X.X unicamente con numeros positivos${nc}"
		return 1
	fi	

	for i in {1..4}; do
		ip1=$(echo "$ip2" | cut -d'.' -f1)
		ip2=${ip2#*.}
		if [[ "$ip1" -gt 255 || "$ip1" -lt 0 ]]; then
			echo -e "${rojo}Direccion IP invalida, no puede ser mayor a 255 ni menor a 0${nc}"
			return 1
		fi
	done
	return 0
}

# Entregable 1
#Comprobar si esta instalada la paqueteria de DHCP
echo -e "${amarillo}Verificando paqueteria DHCP...${nc}"
if ! zypper search --installed-only | grep -q dhcp; then
	echo -e "${rojo}DHCP no esta instalado, instalando...${nc}"
	sudo zypper install dhcp-server
	if ! zypper search --installed-only | grep -q dhcp; then
		echo -e "${rojo}Tiene que instalar dhcp para poder continuar, vuelvalo a intentar...${nc}"
		exit
	fi
fi
echo -e "${verde}DHCP esta instalado, continuando...${nc}"
 
# Entregable 2
echo -e "\nConfiguracion Dinamica\n"
read -p "Nombre descriptivo del Ambito: " nombre_IP
until
	read -p "Rango inicial de la IP: " ip_Inicial
	ip_Correcta "$ip_Inicial"
do
	echo -e "Intentando nuevamente..."
done
until	
	read -p "Rango final de la IP:" ip_Final
	ip_Correcta "$ip_Final"
do
	echo -e "Intendo nuevamente..."
done
read -p "Tiempo de la sesion: " tiempo_Sesion
until
	read -p "Gateway: " gateway
	ip_Correcta "$gateway"
do
	echo -e "Intentado nuevamente..."
done
until	
	read -p "DNS: " dns
	ip_Correcta "$dns"
do
	echo -e "Intentado nuevamente..."
done
