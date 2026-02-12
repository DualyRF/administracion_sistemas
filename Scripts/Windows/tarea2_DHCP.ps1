#Tarea 2 - Automatizacion y gestion del servidor DHCP'

# ---------- Variables globales ----------

# ---------- Funciones ----------
function instalacionDHCP{
	Install-WindowsFeature -Name DHCP -IncludeManagementTools
	Start-Sleep -Seconds 3
    	Write-Host "DHCP ha sido instalado correctamente :D" -ForegroundColor Green
}

function verficar_Instalacion {
    $dhcpEstado= Get-WindowsFeature -Name DHCP

    if ($dhcpEstado.InstallState -eq "Installed"){
        write-host "DHCP ya se encuentra instalado :)" -ForegroundColor Green
        Start-Sleep -Seconds 4
    }
    else {
        write-host "DHCP no se encuentra instalado :o" -ForegroundColor Red
        $opcc = read-host "Desea instalarlo? (S/N)" 
        if ($opcc -eq "S"){
            instalacionDHCP
        }
        else {
            write-host "Entendido, regresando al menu..."
            Start-Sleep -Seconds 5
        }	
    }
}

# ---------- Main ----------
param(
    [switch]$v,
    [switch]$ip,
    [switch]$d
)


if ($v) {
    verficar_Instalacion 
}
elseif ($ip) {
    Write-Host "IP: $direccionIP"
}
elseif ($d) {
    Write-Host "Espacio usado: $($disco.Used / 1GB) GB"
}
else {
    # Mostrar menú interactivo
    Write-Host "1. Nombre: $nombre"
    Write-Host "2. IP: $direccionIP"
    Write-Host "3. Disco: $($disco.Used / 1GB) GB"
}