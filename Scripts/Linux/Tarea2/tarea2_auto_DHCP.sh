#Colores para que sea mas intuitivo
rojo='\033[0;31m'
amarillo='\033[1;33m'
verde='\033[0;32m'
nc='\033[0m'

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
 
