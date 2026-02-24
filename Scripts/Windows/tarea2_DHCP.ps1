#Tarea 2 - Automatizacion y gestion del servidor DHCP

# ---------- Variables globales ----------
$verde    = "Green"
$amarillo = "Yellow"
$azul     = "Cyan"
$rojo     = "Red"
$nc       = "White"

# ---------- Funciones ----------

function validar_IP {
    param([string]$ip)

    if ($ip -notmatch '^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$') {
        Write-Host "Direccion IP invalida, tiene que contener un formato X.X.X.X unicamente con numeros positivos" -ForegroundColor $rojo
        return $false
    }

    $octetos = $ip -split '\.'
    $a = [int]$octetos[0]
    $b = [int]$octetos[1]
    $c = [int]$octetos[2]
    $d = [int]$octetos[3]

    if ($a -eq 0 -or $d -eq 0) {
        Write-Host "Direccion IP invalida, no puede ser 0.X.X.X ni X.X.X.0" -ForegroundColor $rojo
        return $false
    }

    foreach ($octeto in $octetos) {
        if ($octeto.Length -gt 1 -and $octeto.StartsWith("0")) {
            Write-Host "Direccion IP invalida, no se pueden poner 0 a la izquierda a menos que sea 0" -ForegroundColor $rojo
            return $false
        }
        $valor = [int]$octeto
        if ($valor -lt 0 -or $valor -gt 255) {
            Write-Host "Direccion IP invalida, no puede ser mayor a 255 ni menor a 0" -ForegroundColor $rojo
            return $false
        }
    }

    if ($ip -eq "0.0.0.0" -or $ip -eq "255.255.255.255") {
        Write-Host "Direccion IP invalida, no puede ser 0.0.0.0 ni 255.255.255.255" -ForegroundColor $rojo
        return $false
    }

    if ($a -eq 127) {
        Write-Host "Direccion IP invalida, las direcciones 127.x.x.x estan reservadas para host local" -ForegroundColor $rojo
        return $false
    }

    if ($a -ge 224 -and $a -le 239) {
        Write-Host "Direccion IP invalida, las direcciones 224.x.x.x-239.x.x.x estan reservadas para multicast" -ForegroundColor $rojo
        return $false
    }

    if ($a -ge 240 -and $a -lt 255) {
        Write-Host "Direccion IP invalida, las direcciones 240.x.x.x-254.x.x.x estan reservadas para usos experimentales" -ForegroundColor $rojo
        return $false
    }

    return $true
}

function validarMascara {
    param([string]$masc)

    if ($masc -notmatch '^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$') {
        Write-Host "Mascara invalida" -ForegroundColor $rojo
        return $false
    }

    $mascarasValidas = @(
        "255.0.0.0",     "255.128.0.0",   "255.192.0.0",   "255.224.0.0",
        "255.240.0.0",   "255.248.0.0",   "255.252.0.0",   "255.254.0.0",
        "255.255.0.0",   "255.255.128.0", "255.255.192.0", "255.255.224.0",
        "255.255.240.0", "255.255.248.0", "255.255.252.0", "255.255.254.0",
        "255.255.255.0", "255.255.255.128","255.255.255.192","255.255.255.224",
        "255.255.255.240","255.255.255.248","255.255.255.252"
    )

    if ($mascarasValidas -contains $masc) {
        return $true
    }
    else {
        Write-Host "Mascara no valida" -ForegroundColor $rojo
        return $false
    }
}

function calcularRango {
    param([string]$ip1, [string]$ip2)

    $oct1 = $ip1 -split '\.'
    $oct2 = $ip2 -split '\.'

    $num1 = ([int]$oct1[0] * 16777216) + ([int]$oct1[1] * 65536) + ([int]$oct1[2] * 256) + [int]$oct1[3]
    $num2 = ([int]$oct2[0] * 16777216) + ([int]$oct2[1] * 65536) + ([int]$oct2[2] * 256) + [int]$oct2[3]

    return [Math]::Abs($num2 - $num1)
}

function calcularMascara {
    param([string]$ipIni, [string]$ipFin)

    $rango = calcularRango -ip1 $ipIni -ip2 $ipFin

    if     ($rango -le 254)   { return "255.255.255.0" }
    elseif ($rango -le 510)   { return "255.255.254.0" }
    elseif ($rango -le 1022)  { return "255.255.252.0" }
    elseif ($rango -le 2046)  { return "255.255.248.0" }
    elseif ($rango -le 4094)  { return "255.255.240.0" }
    elseif ($rango -le 8190)  { return "255.255.224.0" }
    elseif ($rango -le 16382) { return "255.255.192.0" }
    elseif ($rango -le 32766) { return "255.255.128.0" }
    elseif ($rango -le 65534) { return "255.255.0.0"   }
    else                      { return "255.0.0.0"     }
}

function validarIPMascara {
    param([string]$ipIni, [string]$ipFin, [string]$masc)

    $octIni  = $ipIni -split '\.'
    $octFin  = $ipFin  -split '\.'
    $octMasc = $masc  -split '\.'

    $redIni = @()
    $redFin = @()

    for ($i = 0; $i -lt 4; $i++) {
        $redIni += [int]$octIni[$i] -band [int]$octMasc[$i]
        $redFin += [int]$octFin[$i] -band [int]$octMasc[$i]
    }

    if (($redIni -join '.') -eq ($redFin -join '.')) {
        return $true
    }
    else {
        Write-Host "Las IPs no pertenecen a la misma red con la mascara proporcionada" -ForegroundColor $rojo
        return $false
    }
}

function calcularBits {
    param([string]$masc)

    $bits = 0
    foreach ($oct in ($masc -split '\.')) {
        $num = [int]$oct
        while ($num -gt 0) {
            if ($num -band 1) { $bits++ }
            $num = $num -shr 1
        }
    }
    return $bits
}

function configurar_IP_Estatica {
    param(
        [string]$ipInicial,
        [string]$mascara,
        [string]$gateway 
    )

    Write-Host "`n--- Configuracion de IP Estatica del Servidor ---" -ForegroundColor $amarillo

    $octetos   = $ipInicial -split '\.'
    $ultimoOct = [int]$octetos[3]

    if ($ultimoOct -eq 0) {
        $ipServidor = $ipInicial
    }
    else {
        $ipServidor = "$($octetos[0]).$($octetos[1]).$($octetos[2]).$($ultimoOct - 1)"
    }
    $prefixLen  = calcularBits -masc $mascara

    Write-Host "IP que se asignara al servidor: " -NoNewline
    Write-Host "$ipServidor/$prefixLen" -ForegroundColor $verde

    # ---- Mostrar interfaces disponibles ------------------------
    Write-Host "`nInterfaces de red disponibles:" -ForegroundColor $amarillo
    $adaptadores = Get-NetAdapter | Where-Object { $_.Status -eq "Up" }

    if (-not $adaptadores) {
        Write-Host "No se encontraron interfaces activas" -ForegroundColor $rojo
        return $false
    }

    $adaptadores | Select-Object Name, InterfaceDescription, LinkSpeed | Format-Table -AutoSize

    # ---- Pedir interfaz al usuario -----------------------------
    $interfaz = ""
    do {
        $interfaz = Read-Host "Ingrese el nombre exacto de la interfaz a usar"
        $ifObj    = Get-NetAdapter -Name $interfaz -ErrorAction SilentlyContinue

        if (-not $ifObj) {
            Write-Host "Interfaz '$interfaz' no encontrada, intente de nuevo" -ForegroundColor $rojo
            $interfaz = ""
        }
    } while ($interfaz -eq "")

    # ---- Eliminar IPs anteriores en esa interfaz ---------------
    Write-Host "`nEliminando configuracion IP anterior en '$interfaz'..." -ForegroundColor $amarillo

    $ifIndex = (Get-NetAdapter -Name $interfaz).ifIndex

    # Quitar IPs unicast existentes (IPv4)
    Get-NetIPAddress -InterfaceIndex $ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Remove-NetIPAddress -Confirm:$false -ErrorAction SilentlyContinue

    # Quitar gateway por defecto en esa interfaz
    Get-NetRoute -InterfaceIndex $ifIndex -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue |
        Remove-NetRoute -Confirm:$false -ErrorAction SilentlyContinue

    # ---- Asignar nueva IP estática -----------------------------
    Write-Host "Asignando IP estatica $ipServidor/$prefixLen a '$interfaz'..." -ForegroundColor $amarillo

    try {
        New-NetIPAddress `
            -InterfaceIndex  $ifIndex `
            -IPAddress       $ipServidor `
            -PrefixLength    $prefixLen `
            -AddressFamily   IPv4 `
            -ErrorAction     Stop | Out-Null

        Write-Host "IP estatica asignada correctamente" -ForegroundColor $verde
    }
    catch {
        Write-Host "Error al asignar la IP estatica: $_" -ForegroundColor $rojo
        return $false
    }

    # ---- Asignar gateway si se proporcionó ---------------------
    if ($gateway -ne "") {
        Write-Host "Configurando gateway $gateway en '$interfaz'..." -ForegroundColor $amarillo
        try {
            New-NetRoute `
                -InterfaceIndex    $ifIndex `
                -DestinationPrefix "0.0.0.0/0" `
                -NextHop           $gateway `
                -ErrorAction       Stop | Out-Null

            Write-Host "Gateway configurado correctamente" -ForegroundColor $verde
        }
        catch {
            Write-Host "Advertencia: no se pudo configurar el gateway: $_" -ForegroundColor $amarillo
        }
    }

    # ---- Verificar que quedó activa ----------------------------
    Start-Sleep -Seconds 1
    $ipActual = Get-NetIPAddress -InterfaceIndex $ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
                    Where-Object { $_.IPAddress -eq $ipServidor }

    if ($ipActual) {
        Write-Host "`nVerificacion exitosa — IP $ipServidor activa en '$interfaz'" -ForegroundColor $verde
    }
    else {
        Write-Host "Advertencia: no se pudo verificar la IP asignada" -ForegroundColor $amarillo
    }

    # ---- Devolver ip_Servidor para usarla en DHCP --------------
    # (se guarda en variable de script para que configuracionDHCP la lea)
    $script:ipServidor = $ipServidor
    return $true
}

function configuracionDHCP {
    Write-Host "`n=== Configuracion de DHCP ===" -ForegroundColor $amarillo

    $usoMas = $false

    Write-Host "`nConfiguracion Dinamica`n" -ForegroundColor $azul

    # Nombre del scope
    $scope = Read-Host "Nombre descriptivo del Ambito"

    # Mascara
    $mascValida = $false
    do {
        $mascara = Read-Host "Mascara (En blanco para asignar automaticamente)"
        if ($mascara -ne "") {
            if (validarMascara -masc $mascara) {
                $usoMas     = $true
                $mascValida = $true
            }
        }
        else {
            $mascValida = $true
        }
    } while (-not $mascValida)

    # IP Inicial  —  la primera IP se reserva para el servidor (igual que bash)
    $ipValida = $false
    do {
        $ipInicialServidor = Read-Host "Rango inicial de la IP (esta IP se usara para el servidor)"

        # validar_IP rechaza X.X.X.0, asi que extraemos octetos antes de validar
        $octetos   = $ipInicialServidor -split '\.'
        $ultimoOct = if ($octetos.Count -eq 4) { [int]$octetos[3] } else { -1 }
        $formatoOk = $ipInicialServidor -match '^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$'

        if (-not $formatoOk) {
            Write-Host "Formato de IP invalido" -ForegroundColor $rojo
        }
        elseif ($ultimoOct -eq 255) {
            Write-Host "No use X.X.X.255 como ultimo octeto" -ForegroundColor $rojo
        }
        elseif ($ultimoOct -ge 254) {
            Write-Host "El ultimo octeto debe dejar espacio para al menos una IP de rango encima" -ForegroundColor $rojo
        }
        elseif ($ultimoOct -eq 0) {
            # Caso especial: X.X.X.0 es la IP del servidor, rango DHCP empieza en X.X.X.1
            $ipInicial = "$($octetos[0]).$($octetos[1]).$($octetos[2]).1"
            if (validar_IP -ip $ipInicial) {
                $ipValida = $true
                Write-Host "IP del servidor : $ipInicialServidor (X.X.X.0 permitido)" -ForegroundColor $verde
                Write-Host "Rango DHCP desde: $ipInicial" -ForegroundColor $verde
            }
        }
        elseif (validar_IP -ip $ipInicialServidor) {
            # Caso normal: rango DHCP empieza en ip_Servidor + 1
            $nuevoUltimo = $ultimoOct + 1
            $ipInicial   = "$($octetos[0]).$($octetos[1]).$($octetos[2]).$nuevoUltimo"

            if (validar_IP -ip $ipInicial) {
                $ipValida = $true
                Write-Host "IP del servidor : $ipInicialServidor" -ForegroundColor $verde
                Write-Host "Rango DHCP desde: $ipInicial"         -ForegroundColor $verde
            }
        }

        if (-not $ipValida) { Write-Host "Intentando nuevamente..." -ForegroundColor $amarillo }
    } while (-not $ipValida)

    # IP Final
    $ipValida = $false
    do {
        $ipFinal = Read-Host "Rango final de la IP"

        if (validar_IP -ip $ipFinal) {
            $rango = calcularRango -ip1 $ipInicial -ip2 $ipFinal

            if ($rango -gt 2) {
                if ($usoMas) {
                    if (validarIPMascara -ipIni $ipInicial -ipFin $ipFinal -masc $mascara) {
                        $ipValida = $true
                    }
                }
                else {
                    $mascara  = calcularMascara -ipIni $ipInicial -ipFin $ipFinal
                    Write-Host "Mascara calculada automaticamente: $mascara" -ForegroundColor $verde
                    $ipValida = $true
                }
            }
            else {
                Write-Host "El rango debe ser mayor a 2 IPs" -ForegroundColor $rojo
            }
        }

        if (-not $ipValida) { Write-Host "Intentando nuevamente..." -ForegroundColor $amarillo }
    } while (-not $ipValida)

    # Tiempo de sesion
    do {
        $leaseTime    = Read-Host "Tiempo de la sesion (segundos)"
        $leaseTimeNum = $leaseTime -as [int]

        if ($null -eq $leaseTimeNum -or $leaseTimeNum -le 0) {
            Write-Host "Debe ingresar un numero positivo" -ForegroundColor $rojo
            $leaseTimeValido = $false
        }
        else {
            $leaseTimeValido = $true
        }
    } while (-not $leaseTimeValido)

    # Gateway
    $octetos         = $ipInicial -split '\.'
    $ultimoOcteto    = [int]$octetos[3]
    $gatewaySugerido = if ($ultimoOcteto -eq 1) {
        "$($octetos[0]).$($octetos[1]).$($octetos[2]).254"
    } else {
        "$($octetos[0]).$($octetos[1]).$($octetos[2]).1"
    }

    $comp = $false
    do {
        Write-Host "Gateway sugerido: " -NoNewline -ForegroundColor $amarillo
        Write-Host $gatewaySugerido -ForegroundColor $verde
        $gateway = Read-Host "Gateway (Enter para usar sugerido, vacio para omitir)"

        if ($gateway -eq "") {
            $usarSugerido = Read-Host "Usar gateway sugerido? (s/N)"
            if ($usarSugerido -match '^[Ss]$') {
                $gateway = $gatewaySugerido
            }
            else {
                $gateway = ""
                Write-Host "Sin gateway - red aislada" -ForegroundColor $amarillo
            }
            $comp = $true
        }
        elseif (validar_IP -ip $gateway) {
            $comp = $true
        }

        if (-not $comp) { Write-Host "Intentando nuevamente..." -ForegroundColor $amarillo }
    } while (-not $comp)

    # DNS Principal
    $comp = $false
    do {
        $dns = Read-Host "DNS principal (puede quedar vacio)"

        if ($dns -eq "") {
            $comp   = $true
            $dnsAlt = ""
        }
        elseif (validar_IP -ip $dns) {
            $comp = $true
        }

        if (-not $comp) { Write-Host "Intentando nuevamente..." -ForegroundColor $amarillo }
    } while (-not $comp)

    # DNS Alternativo
    if ($dns -ne "") {
        $comp = $false
        do {
            $dnsAlt = Read-Host "DNS alternativo (puede quedar vacio)"

            if ($dnsAlt -eq "") {
                $comp = $true
            }
            elseif (validar_IP -ip $dnsAlt) {
                $comp = $true
            }

            if (-not $comp) { Write-Host "Intentando nuevamente..." -ForegroundColor $amarillo }
        } while (-not $comp)
    }
    else {
        $dnsAlt = ""
    }

    # Resumen
    Write-Host "`nLa configuracion final es:" -ForegroundColor $azul
    Write-Host "Nombre del ambito  : " -NoNewline; Write-Host $scope               -ForegroundColor $verde
    Write-Host "IP del servidor    : " -NoNewline; Write-Host $ipInicialServidor    -ForegroundColor $verde
    Write-Host "Rango DHCP inicial : " -NoNewline; Write-Host $ipInicial            -ForegroundColor $verde
    Write-Host "Rango DHCP final   : " -NoNewline; Write-Host $ipFinal              -ForegroundColor $verde
    Write-Host "Mascara            : " -NoNewline; Write-Host $mascara              -ForegroundColor $verde
    Write-Host "Tiempo de concesion: " -NoNewline; Write-Host "$leaseTime segundos" -ForegroundColor $verde
    Write-Host "Gateway            : " -NoNewline; Write-Host $(if ($gateway -eq "") { "(sin gateway)" } else { $gateway }) -ForegroundColor $verde
    Write-Host "DNS primario       : " -NoNewline; Write-Host $(if ($dns    -eq "") { "(vacio)"       } else { $dns })     -ForegroundColor $verde
    Write-Host "DNS alternativo    : " -NoNewline; Write-Host $(if ($dnsAlt -eq "") { "(vacio)"       } else { $dnsAlt })  -ForegroundColor $verde

    $opc = Read-Host "`nAcepta esta configuracion? (y/n)"

    if ($opc -ne "y") {
        Write-Host "Configuracion cancelada, volviendo al menu..." -ForegroundColor $amarillo
        Start-Sleep -Seconds 2
        return
    }

    $resultado = configurar_IP_Estatica -ipInicial $ipInicialServidor -mascara $mascara -gateway $gateway

    if (-not $resultado) {
        Write-Host "No se pudo configurar la IP estatica. Abortando configuracion DHCP." -ForegroundColor $rojo
        return
    }

    try {
        $octetosIP   = $ipInicial -split '\.'
        $octetosMasc = $mascara   -split '\.'

        $red       = @(); for ($i = 0; $i -lt 4; $i++) { $red       += [int]$octetosIP[$i] -band [int]$octetosMasc[$i] }
        $broadcast = @(); for ($i = 0; $i -lt 4; $i++) { $broadcast += [int]$octetosIP[$i] -bor (255 - [int]$octetosMasc[$i]) }

        $redStr       = $red       -join '.'
        $broadcastStr = $broadcast -join '.'

        Write-Host "Red calculada      : $redStr"       -ForegroundColor $amarillo
        Write-Host "Broadcast calculado: $broadcastStr" -ForegroundColor $amarillo

        Write-Host "`nCreando scope DHCP..." -ForegroundColor $amarillo
        Add-DhcpServerv4Scope `
            -Name        $scope `
            -StartRange  $ipInicial `
            -EndRange    $ipFinal `
            -SubnetMask  $mascara `
            -State       Active
        Write-Host "Scope creado" -ForegroundColor $verde

        if ($gateway -ne "") {
            Set-DhcpServerv4OptionValue -ScopeId $redStr -OptionId 3 -Value $gateway
        }

        if ($dns -ne "" -and $dnsAlt -ne "") {
            Set-DhcpServerv4OptionValue -ScopeId $redStr -OptionId 6 -Value @($dns, $dnsAlt)
        }
        elseif ($dns -ne "") {
            Set-DhcpServerv4OptionValue -ScopeId $redStr -OptionId 6 -Value $dns
        }

        $duracion = New-TimeSpan -Seconds $leaseTime
        Set-DhcpServerv4Scope -ScopeId $redStr -LeaseDuration $duracion

        Write-Host "Reiniciando servicio DHCP..." -ForegroundColor $amarillo
        Restart-Service DHCPServer
        Start-Sleep -Seconds 2

        $servicio = Get-Service DHCPServer
        if ($servicio.Status -eq "Running") {
            Write-Host "`n¡Servidor DHCP configurado y funcionando correctamente!" -ForegroundColor $verde
            Write-Host "`nDetalles del Scope:" -ForegroundColor $azul
            Get-DhcpServerv4Scope -ScopeId $redStr | Format-List
        }
        else {
            Write-Host "Error al iniciar el servicio DHCP" -ForegroundColor $rojo
            Get-Service DHCPServer | Format-List
        }
    }
    catch {
        Write-Host "Error durante la configuracion: $_" -ForegroundColor $rojo
        Write-Host "Detalles: $($_.Exception.Message)"  -ForegroundColor $amarillo
    }
}

function configuracionDHCP_Predeterminada {
    Write-Host "`nAplicando configuracion predeterminada de DHCP..." -ForegroundColor $verde

    try {
        $scope      = "Red Predeterminada"
        $ipServidor = "192.168.1.99"   # primera IP del rango - 1
        $ipInicial  = "192.168.1.100"
        $ipFinal    = "192.168.1.200"
        $mascara    = "255.255.255.0"
        $gateway    = "192.168.1.1"
        $dns        = "8.8.8.8"
        $dnsAlt     = "8.8.4.4"
        $leaseTime  = 600
        $redStr     = "192.168.1.0"

        Write-Host "Red: 192.168.1.0/24"                    -ForegroundColor $azul
        Write-Host "IP del servidor: $ipServidor"           -ForegroundColor $azul
        Write-Host "Rango DHCP: $ipInicial - $ipFinal"      -ForegroundColor $azul
        Write-Host "Gateway: $gateway"                      -ForegroundColor $azul
        Write-Host "DNS: $dns, $dnsAlt`n"                   -ForegroundColor $azul

        # Configurar IP estatica primero
        $resultado = configurar_IP_Estatica -ipInicial $ipServidor -mascara $mascara -gateway $gateway
        if (-not $resultado) {
            Write-Host "No se pudo configurar la IP estatica. Abortando." -ForegroundColor $rojo
            return
        }

        Add-DhcpServerv4Scope `
            -Name       $scope `
            -StartRange $ipInicial `
            -EndRange   $ipFinal `
            -SubnetMask $mascara `
            -State      Active

        Set-DhcpServerv4OptionValue -ScopeId $redStr -OptionId 3 -Value $gateway
        Set-DhcpServerv4OptionValue -ScopeId $redStr -OptionId 6 -Value @($dns, $dnsAlt)

        $duracion = New-TimeSpan -Seconds $leaseTime
        Set-DhcpServerv4Scope -ScopeId $redStr -LeaseDuration $duracion

        Restart-Service DHCPServer
        Start-Sleep -Seconds 2

        Write-Host "Configuracion predeterminada aplicada exitosamente" -ForegroundColor $verde
        Get-DhcpServerv4Scope -ScopeId $redStr | Format-List
    }
    catch {
        Write-Host "Error al aplicar configuracion predeterminada: $_" -ForegroundColor $rojo
    }
}

function instalacionDHCP {
    Write-Host "`n--- Instalacion de DHCP Server ---" -ForegroundColor $amarillo

    $dhcpEstado = Get-WindowsFeature -Name DHCP

    if ($dhcpEstado.InstallState -eq "Installed") {
        Write-Host "DHCP server ya esta instalado" -ForegroundColor $azul
    }
    else {
        Write-Host "DHCP server no esta instalado, iniciando instalacion..." -ForegroundColor $amarillo

        try {
            $job = Start-Job -ScriptBlock { Install-WindowsFeature -Name DHCP -IncludeManagementTools }

            Write-Host -NoNewline "DHCP se esta instalando"
            while ($job.State -eq "Running") {
                Write-Host -NoNewline "."
                Start-Sleep -Milliseconds 500
            }
            Write-Host ""

            $result = Receive-Job -Job $job
            Remove-Job  -Job $job

            if ($result.Success) {
                Write-Host "DHCP server instalado correctamente" -ForegroundColor $verde
            }
            else {
                Write-Host "Error en la instalacion de DHCP" -ForegroundColor $rojo
                return
            }
        }
        catch {
            Write-Host "Error durante la instalacion: $_" -ForegroundColor $rojo
            return
        }
    }

    Write-Host ""

    $scopesExistentes = Get-DhcpServerv4Scope -ErrorAction SilentlyContinue
    if ($scopesExistentes) {
        Write-Host "Se detecto una configuracion previa de DHCP" -ForegroundColor $amarillo
        Write-Host "Scopes existentes:" -ForegroundColor $amarillo
        $scopesExistentes | Format-Table -AutoSize

        $sobreescribir = Read-Host "`nDeseas sobreescribir la configuracion existente? (s/N)"

        if ($sobreescribir -notmatch '^[Ss]$') {
            Write-Host "Manteniendo configuracion existente" -ForegroundColor $azul
            return
        }

        Write-Host "`nEliminando configuracion anterior..." -ForegroundColor $amarillo
        foreach ($s in $scopesExistentes) {
            Remove-DhcpServerv4Scope -ScopeId $s.ScopeId -Force
        }
    }

    Write-Host ""
    Write-Host "Deseas configurar DHCP manualmente o usar configuracion predeterminada?" -ForegroundColor $amarillo
    Write-Host "1) Configurar manualmente"
    Write-Host "2) Usar configuracion predeterminada"
    Write-Host ""

    $opcion = Read-Host "Selecciona una opcion [1-2]"

    switch ($opcion) {
        "1" {
            Write-Host "`nIniciando configuracion manual de DHCP..." -ForegroundColor $verde
            configuracionDHCP
        }
        "2" { configuracionDHCP_Predeterminada }
        default {
            Write-Host "Opcion no valida, usando configuracion predeterminada" -ForegroundColor $rojo
            configuracionDHCP_Predeterminada
        }
    }

    Write-Host "`n--- Configuracion de DHCP completada ---" -ForegroundColor $verde
}

function verificar_Instalacion {
    $dhcpEstado = Get-WindowsFeature -Name DHCP

    if ($dhcpEstado.InstallState -eq "Installed") {
        Write-Host "DHCP ya se encuentra instalado" -ForegroundColor $verde

        $scopes = Get-DhcpServerv4Scope -ErrorAction SilentlyContinue
        if ($scopes) {
            Write-Host "`nScopes configurados:" -ForegroundColor $azul
            $scopes | Format-Table -AutoSize
        }

        $servicio = Get-Service DHCPServer
        Write-Host "`nEstado del servicio: " -NoNewline
        if ($servicio.Status -eq "Running") {
            Write-Host "Funcionando" -ForegroundColor $verde
        }
        else {
            Write-Host "Detenido" -ForegroundColor $rojo
        }
    }
    else {
        Write-Host "DHCP no se encuentra instalado" -ForegroundColor $rojo
        $opcc = Read-Host "`nDesea instalarlo? (S/N)"

        if ($opcc -match '^[Ss]$') {
            instalacionDHCP
        }
        else {
            Write-Host "Entendido, regresando al menu..." -ForegroundColor $amarillo
            Start-Sleep -Seconds 2
        }
    }
}

function mostrarMenu {
    Clear-Host
    Write-Host "--- Gestion de Servidor DHCP ---"          -ForegroundColor $verde
    Write-Host ""
    Write-Host "1. Verificar Instalacion"              -ForegroundColor $amarillo
    Write-Host "2. Instalar y Configurar DHCP"         -ForegroundColor $amarillo
    Write-Host "3. Configurar DHCP"                    -ForegroundColor $amarillo
    Write-Host "4. Ver Scopes Activos"                 -ForegroundColor $amarillo
    Write-Host "5. Salir"                              -ForegroundColor $amarillo
    Write-Host ""

    $opcion = Read-Host "Selecciona una opcion"

    switch ($opcion) {
        "1" {
            verificar_Instalacion
            Read-Host "`nPresiona Enter para continuar"
            mostrarMenu
        }
        "2" {
            instalacionDHCP
            Read-Host "`nPresiona Enter para continuar"
            mostrarMenu
        }
        "3" {
            $dhcpEstado = Get-WindowsFeature -Name DHCP
            if ($dhcpEstado.InstallState -eq "Installed") {
                configuracionDHCP
            }
            else {
                Write-Host "DHCP no esta instalado. Instalelo primero." -ForegroundColor $rojo
            }
            Read-Host "`nPresiona Enter para continuar"
            mostrarMenu
        }
        "4" {
            $scopes = Get-DhcpServerv4Scope -ErrorAction SilentlyContinue
            if ($scopes) {
                $scopes | Format-Table -AutoSize
            }
            else {
                Write-Host "No hay scopes configurados" -ForegroundColor $amarillo
            }
            Read-Host "`nPresiona Enter para continuar"
            mostrarMenu
        }
        "5" {
            Write-Host "`nSaliendo..." -ForegroundColor $verde
            exit
        }
        default {
            Write-Host "Opcion no valida" -ForegroundColor $rojo
            Start-Sleep -Seconds 2
            mostrarMenu
        }
    }
}

# ---------- Main ----------
param(
    [switch]$v,
    [switch]$i,
    [switch]$c
)

if ($v)      { verificar_Instalacion }
elseif ($i)  { instalacionDHCP       }
elseif ($c)  { configuracionDHCP     }
else         { mostrarMenu           }