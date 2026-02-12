#Tarea 2 - Automatizacion y gestion del servidor DHCP'

# ---------- Variables globales ----------

# ---------- Funciones ----------
Function validarIP {
    param ([string]$ip)

    # Validar formato X.X.X.X solo con números
    if (-not ($ip -match "^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$")) {
        Write-Host "Dirección IP inválida, tiene que contener un formato X.X.X.X únicamente con números positivos" -ForegroundColor Red
        Start-Sleep -Seconds 2
        return $false
    }

    # Separar octetos
    $octetos = $ip -split '\.'
    
    # Validar que no sea 0.X.X.X ni X.X.X.0
    if ($octetos[0] -eq 0 -or $octetos[3] -eq 0) {
        Write-Host "Dirección IP inválida, no puede ser 0.X.X.X ni X.X.X.0" -ForegroundColor Red
        Start-Sleep -Seconds 2
        return $false
    }

    # Validar cada octeto
    foreach ($octeto in $octetos) {
        # No permitir 0 a la izquierda (excepto si es solo "0")
        if ($octeto -match "^0[0-9]+") {
            Write-Host "Dirección IP inválida, no se pueden poner 0 a la izquierda a menos que sea 0" -ForegroundColor Red
            Start-Sleep -Seconds 2
            return $false
        }
        
        # Validar rango 0-255
        $num = [int]$octeto
        if ($num -lt 0 -or $num -gt 255) {
            Write-Host "Dirección IP inválida, no puede ser mayor a 255 ni menor a 0" -ForegroundColor Red
            Start-Sleep -Seconds 2
            return $false
        }
    }

    # Validar que no sea 0.0.0.0 ni 255.255.255.255
    if ($ip -eq "0.0.0.0" -or $ip -eq "255.255.255.255") {
        Write-Host "Dirección IP inválida, no puede ser 0.0.0.0 ni 255.255.255.255" -ForegroundColor Red
        Start-Sleep -Seconds 2
        return $false] -eq 127) {
        Write-Host "Dirección IP inválida, las direcciones del rango 127.0.0.1 al 127.255.255.255 están reservadas para host local" -ForegroundColor Red
        Start-Sleep -Seconds 2
        return $false
    }

    # Validar espacio reservado experimental (240.0.0.0-255.255.255.254)
    if ([int]$octetos[0] -gt 240 -and [int]$octetos[0] -lt 255) {
        Write-Host "Dirección IP inválida, las direcciones del rango 240.0.0.0 al 255.255.255.254 están reservadas para usos experimentales" -ForegroundColor Red
        Start-Sleep -Seconds 2
        return $false
    }

    # Validar espacio reservado multicast (224.0.0.0-239.255.255.255)
    if ([int]$octetos[0] -ge 224 -and [int]$octetos[0] -le 239) {
        Write-Host "Dirección IP inválida, las direcciones del rango 224.0.0.0 al 239.255.255.255 están reservadas para multicast" -ForegroundColor Red
        Start-Sleep -Seconds 2
        return $false
    }

    # Validar si la IP está en uso (tu validación original)
    $chequeo = Get-DhcpServerv4Lease -ScopeId 192.168.100.0 | Where-Object IPAddress -eq $ip
    if ($chequeo) {
        Write-Host "Esa IP ya está en uso por $($chequeo.ClientId)" -ForegroundColor Yellow
        Start-Sleep -Seconds 4
        return $false
    }

    # Validar rango específico (tu validación original)
    $regexRango = "^192\.168\.100\.([5-9]\d|1[0-4]\d|150)$"
    if ($ip -match $regexRango) {
        Write-Host "IP dentro del rango" -ForegroundColor Green
        Start-Sleep -Seconds 1
        return $true
    }
    else {
        Write-Host "Rango incorrecto ://" -ForegroundColor Red
        Start-Sleep -Seconds 2
        return $false
    }
}

function configuracionDHCP{
    Write-Host "Configurando DHCP..." -ForegroundColor Yellow
    # Variables locales
    $ipValida = $false
    $usoMas = $false
    $comp = $false

    Write-Host "`nConfiguracion Dinamica`n" -ForegroundColor Cyan

    # Nombre del scope
    $scope = Read-Host "Nombre descriptivo del Ambito"

    # Máscara
    $mascValida = $false
    do {
        $mascara = Read-Host "Mascara (En blanco para asignar automaticamente)"
        if ($mascara -ne "") {
            if (validarMascara -masc $mascara) {
                $usoMas = $true
                $mascValida = $true
            }
        }
        else {
            $mascValida = $true
        }
    } while (-not $mascValida)

    # IP Inicial
    $ipValida = $false
    do {
        $ipInicial = Read-Host "Rango inicial de la IP (La primera IP se usara para asignarla al servidor)"
        $octetos = $ipInicial -split '\.'
        $ipRes = [int]$octetos[3]
        
        if ($ipRes -ne 255) {
            $ipServidor = $ipInicial
            $ipRes = $ipRes + 1
            $octetos[3] = $ipRes
            $ipInicial = $octetos -join '.'
            
            if (validarIP -ip $ipInicial) {
                $ipValida = $true
            }
        }
        else {
            Write-Host "No use X.X.X.255 como ultimo octeto por temas de rendimiento" -ForegroundColor Yellow
            Write-Host "Intentando nuevamente..." -ForegroundColor Yellow
        }
    } while (-not $ipValida)

    # IP Final
    $ipValida = $false
    do {
        $ipFinal = Read-Host "Rango final de la IP"
        
        if (validarIP -ip $ipFinal) {
            $rango = calcularRango -ip1 $ipInicial -ip2 $ipFinal
            
            if ($rango -gt 2) {
                if ($usoMas) {
                    if (validarIPMascara -ipIni $ipInicial -ipFin $ipFinal -masc $mascara) {
                        $ipValida = $true
                    }
                }
                else {
                    $mascara = calcularMascara -ipIni $ipInicial -ipFin $ipFinal
                    $ipValida = $true
                }
            }
            else {
                Write-Host "La IP no concuerda con el rango inicial" -ForegroundColor Red
            }
        }
        
        if (-not $ipValida) {
            Write-Host "Intentando nuevamente..." -ForegroundColor Yellow
        }
    } while (-not $ipValida)

    # Tiempo de sesión
    $leaseTime = Read-Host "Tiempo de la sesion (segundos)"

    # Gateway
    do {
        $gateway = Read-Host "Gateway"
        $gatewayValido = validarIP -ip $gateway
        
        if (-not $gatewayValido) {
            Write-Host "Intentando nuevamente..." -ForegroundColor Yellow
        }
    } while (-not $gatewayValido)

    # DNS Principal
    $comp = $false
    do {
        $dns = Read-Host "DNS principal (puede quedar vacio)"
        
        if ($dns -eq "") {
            $comp = $true
        }
        elseif (validarIP -ip $dns) {
            $comp = $true
        }
        
        if (-not $comp) {
            Write-Host "Intentando nuevamente..." -ForegroundColor Yellow
        }
    } while (-not $comp)

    # DNS Alternativo
    $comp = $false
    do {
        $dnsAlt = Read-Host "DNS alternativo (puede quedar vacio)"
        
        if ($dnsAlt -eq "") {
            $comp = $true
        }
        elseif (validarIP -ip $dnsAlt) {
            $comp = $true
        }
        
        if (-not $comp) {
            Write-Host "Intentando nuevamente..." -ForegroundColor Yellow
        }
    } while (-not $comp)

    # Mostrar interfaces de red disponibles (PowerShell)
    Write-Host "`nInterfaces de red disponibles:" -ForegroundColor Yellow
    Get-NetAdapter | Where-Object {$_.Status -eq "Up"} | Select-Object Name, InterfaceDescription | Format-Table -AutoSize
    $interfaz = Read-Host "Ingrese el nombre de la interfaz de red a usar"

    # Resumen de configuración
    Write-Host "`nLa configuracion final es:" -ForegroundColor Blue
    Write-Host "Nombre del ambito: " -NoNewline; Write-Host $scope -ForegroundColor Green
    Write-Host "Mascara: " -NoNewline; Write-Host $mascara -ForegroundColor Green
    Write-Host "IP del servidor: " -NoNewline; Write-Host $ipServidor -ForegroundColor Green
    Write-Host "IP inicial: " -NoNewline; Write-Host $ipInicial -ForegroundColor Green
    Write-Host "IP final: " -NoNewline; Write-Host $ipFinal -ForegroundColor Green
    Write-Host "Tiempo de consesion: " -NoNewline; Write-Host "$leaseTime segundos" -ForegroundColor Green
    Write-Host "Gateway: " -NoNewline; Write-Host $gateway -ForegroundColor Green
    Write-Host "DNS primario: " -NoNewline; Write-Host $(if($dns -eq ""){"(vacio)"}else{$dns}) -ForegroundColor Green
    Write-Host "DNS alternativo: " -NoNewline; Write-Host $(if($dnsAlt -eq ""){"(vacio)"}else{$dnsAlt}) -ForegroundColor Green
    Write-Host "Interfaz: " -NoNewline; Write-Host "$interfaz`n" -ForegroundColor Green

    $opc = Read-Host "Acepta esta configuracion? (y/n)"
    if ($opc -eq "y") {
        try {
            # Calcular la dirección de red correctamente
            $octetosIP = $ipInicial -split '\.'
            $octetosMasc = $mascara -split '\.'
            
            # AND bit a bit entre IP y máscara para obtener la red
            $red = @()
            for ($i = 0; $i -lt 4; $i++) {
                $red += [int]$octetosIP[$i] -band [int]$octetosMasc[$i]
            }
            $redStr = $red -join '.'
            
            # Calcular broadcast
            $broadcast = @()
            for ($i = 0; $i -lt 4; $i++) {
                $broadcast += [int]$octetosIP[$i] -bor (255 - [int]$octetosMasc[$i])
            }
            $broadcastStr = $broadcast -join '.'
            
            Write-Host "Red calculada: $redStr" -ForegroundColor Yellow
            Write-Host "Broadcast calculado: $broadcastStr" -ForegroundColor Yellow
            
            # Crear configuración DHCP
            Write-Host "Creando configuración DHCP..." -ForegroundColor Yellow
            
            # Crear el scope
            Add-DhcpServerv4Scope `
                -Name $scope `
                -StartRange $ipInicial `
                -EndRange $ipFinal `
                -SubnetMask $mascara `
                -State Active
            
            # Configurar Gateway (Opción 3)
            Write-Host "Configurando Gateway..." -ForegroundColor Yellow
            Set-DhcpServerv4OptionValue -ScopeId $redStr -OptionId 3 -Value $gateway
            
            # Configurar Máscara de subred (Opción 1)
            Set-DhcpServerv4OptionValue -ScopeId $redStr -OptionId 1 -Value $mascara
            
            # Configurar DNS (Opción 6)
            if ($dns -ne "" -and $dnsAlt -ne "") {
                Write-Host "Configurando DNS principal y alternativo..." -ForegroundColor Yellow
                Set-DhcpServerv4OptionValue -ScopeId $redStr -OptionId 6 -Value @($dns, $dnsAlt)
            }
            elseif ($dns -ne "") {
                Write-Host "Configurando DNS principal..." -ForegroundColor Yellow
                Set-DhcpServerv4OptionValue -ScopeId $redStr -OptionId 6 -Value $dns
            }
            
            # Configurar tiempo de concesión
            Write-Host "Configurando tiempo de concesión..." -ForegroundColor Yellow
            $duracion = New-TimeSpan -Seconds $leaseTime
            Set-DhcpServerv4Scope -ScopeId $redStr -LeaseDuration $duracion
            
            # Configurar IP estática en la interfaz de red
            Write-Host "Configurando IP estática $ipServidor en la interfaz $interfaz..." -ForegroundColor Yellow
            
            # Calcular la longitud del prefijo (CIDR)
            $bits = calcularBits -masc $mascara
            $prefijo = 32 - $bits
            
            # Remover IPs anteriores de la interfaz
            Remove-NetIPAddress -InterfaceAlias $interfaz -Confirm:$false -ErrorAction SilentlyContinue
            
            # Asignar la nueva IP estática
            New-NetIPAddress `
                -InterfaceAlias $interfaz `
                -IPAddress $ipServidor `
                -PrefixLength $prefijo `
                -DefaultGateway $gateway `
                -ErrorAction Stop
            
            # Configurar DNS en la interfaz
            if ($dns -ne "") {
                if ($dnsAlt -ne "") {
                    Set-DnsClientServerAddress -InterfaceAlias $interfaz -ServerAddresses @($dns, $dnsAlt)
                }
                else {
                    Set-DnsClientServerAddress -InterfaceAlias $interfaz -ServerAddresses $dns
                }
            }
            
            Write-Host "IP estática $ipServidor configurada en $interfaz" -ForegroundColor Green
            
            # Reiniciar servicio DHCP
            Write-Host "Reiniciando servicio DHCP..." -ForegroundColor Yellow
            Restart-Service DHCPServer
            
            # Verificar estado del servicio
            Start-Sleep -Seconds 2
            $servicioEstado = Get-Service DHCPServer
            
            if ($servicioEstado.Status -eq "Running") {
                Write-Host "`n¡Servidor DHCP configurado y funcionando correctamente!" -ForegroundColor Green
                Get-Service DHCPServer | Format-List
                Write-Host "`nDetalles del Scope:" -ForegroundColor Cyan
                Get-DhcpServerv4Scope -ScopeId $redStr | Format-List
            }
            else {
                Write-Host "`nError al iniciar el servicio DHCP" -ForegroundColor Red
                Write-Host "Ejecute: Get-EventLog -LogName System -Source DHCPServer -Newest 10" -ForegroundColor Yellow
            }
        }
        catch {
            Write-Host "`nError durante la configuración: $_" -ForegroundColor Red
            Write-Host "Detalles del error: $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }
    else {
        Write-Host "Volviendo a configurar..." -ForegroundColor Yellow
        Start-Sleep -Seconds 2
        # Aquí llamarías recursivamente a tu función principal
        # configScope
    }
}

function instalacionDHCP{
	Install-WindowsFeature -Name DHCP -IncludeManagementTools
	Start-Sleep -Seconds 3
    Write-Host "DHCP ha sido instalado correctamente :D" -ForegroundColor Green
    configuracionDHCP
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
    [switch]$i,
    [switch]$d
)


if ($v) {
    verficar_Instalacion 
}
elseif ($i) {
    Write-Host instalacionDHCP
}
elseif ($d) {
    Write-Host "Espacio usado: $($disco.Used / 1GB) GB"
}
else {
    # Mostrar menú interactivo
    Write-Host "1. Verficar Instalacion" verficar_Instalacion
    Write-Host "2. Instalar" instalacion
    Write-Host "3. Monitoreo"
}