# startDNS.ps1
# Libreria para inicializar IP estatica del servidor DNS
# Funciones: InitDNS

function InitDNS {

    # ---- Verificar IP --------------------------------
    $interfaz = Get-NetAdapter | Where-Object { $_.Name -eq "Ethernet 2" -and $_.Status -eq "Up" }

    if ($null -eq $interfaz) {
        $interfaz = Get-NetAdapter | Where-Object { $_.Status -eq "Up" -and $_.Name -notlike "*Bluetooth*" } | Select-Object -First 1
    }

    if ($null -eq $interfaz) {
        Write-Host "DNS: Sin interfaz activa | Servicio: -" -ForegroundColor Red
        return $false
    }

    $ipActual = Get-NetIPAddress -InterfaceAlias $interfaz.Name -AddressFamily IPv4 -ErrorAction SilentlyContinue | Select-Object -First 1

    if ($null -eq $ipActual) {
        Write-Host "DNS: Sin IP | Servicio: -" -ForegroundColor Red
        return $false
    }

    # Si es DHCP o APIPA, configurar IP fija
    if ($ipActual.PrefixOrigin -eq "Dhcp" -or $ipActual.IPAddress -like "169.254.*") {
        Write-Host "DNS: IP dinamica detectada - se requiere IP fija" -ForegroundColor Yellow
        $confirmar = Read-Host "Deseas configurarla ahora? (S/N)"

        if ($confirmar -ne "S") {
            Write-Host "DNS: $($ipActual.IPAddress) (dinamica) | Servicio: pendiente" -ForegroundColor Yellow
        }
        else {
            $nuevaIP = Read-Host "IP Estatica (ej. 192.168.1.10)"
            $prefijo = Read-Host "Prefijo (ej. 24)"
            $gateway = Read-Host "Gateway (ej. 192.168.1.1)"

            try {
                New-NetIPAddress -InterfaceAlias $interfaz.Name -IPAddress $nuevaIP -PrefixLength $prefijo -DefaultGateway $gateway -Confirm:$false -ErrorAction Stop
                $ipActual = Get-NetIPAddress -InterfaceAlias $interfaz.Name -AddressFamily IPv4 | Select-Object -First 1
            }
            catch {
                Write-Host "DNS: Error al configurar IP - $($_.Exception.Message)" -ForegroundColor Red
                return $false
            }
        }
    }

    $ip = $ipActual.IPAddress

    # ---- Verificar servicio DNS --------------------------------
    $svc = Get-Service -Name "DNS" -ErrorAction SilentlyContinue

    if ($null -eq $svc) {
        Write-Host "DNS: $ip | Servicio: No instalado" -ForegroundColor Red
        return $false
    }

    if ($svc.Status -ne "Running") {
        try {
            Start-Service -Name "DNS" -ErrorAction Stop
            Start-Sleep -Seconds 2
            $svc = Get-Service -Name "DNS"
        }
        catch {
            Write-Host "DNS: $ip | Servicio: Error al iniciar" -ForegroundColor Red
            return $false
        }
    }

    if ($svc.Status -eq "Running") {
        Write-Host "DNS: $ip | Servicio: Activo" -ForegroundColor Green
        return $true
    }
    else {
        Write-Host "DNS: $ip | Servicio: Inactivo" -ForegroundColor Red
        return $false
    }
}