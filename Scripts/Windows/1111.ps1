Write-Host "`nConfiguracion Dinamica`n" -ForegroundColor Cyan

# Nombre del scope
$scope = Read-Host "Nombre descriptivo del Ambito"

# Mascara (opcional)
$mascara = Read-Host "Mascara (En blanco para 255.255.255.0)"
if ([string]::IsNullOrWhiteSpace($mascara)) {
    $mascara = "255.255.255.0"
}

# IP Inicial
$ipInicial = Read-Host "Rango inicial de la IP (La primera IP se usara para el servidor)"
$octetos = $ipInicial -split '\.'
$ipServidor = $ipInicial
$octetos[3] = ([int]$octetos[3] + 1)
$ipInicial = $octetos -join '.'

# IP Final
$ipFinal = Read-Host "Rango final de la IP"

# Tiempo de sesión
$leaseTime = Read-Host "Tiempo de la sesion (segundos)"

# Gateway
$gateway = Read-Host "Gateway"

# DNS
$dns = Read-Host "DNS principal (puede quedar vacio)"
$dnsAlt = Read-Host "DNS alternativo (puede quedar vacio)"

# Interfaces disponibles
Write-Host "`nInterfaces de red disponibles:" -ForegroundColor Yellow
Get-NetAdapter | Where-Object {$_.Status -eq "Up"} | 
Select-Object Name, InterfaceDescription | Format-Table -AutoSize

$interfaz = Read-Host "Ingrese el nombre de la interfaz de red a usar"

# ==============================
# Calcular Red y Broadcast
# ==============================

$octetosIP = $ipInicial -split '\.'
$octetosMasc = $mascara -split '\.'

$red = @()
$broadcast = @()

for ($i = 0; $i -lt 4; $i++) {
    $red += [int]$octetosIP[$i] -band [int]$octetosMasc[$i]
    $broadcast += [int]$octetosIP[$i] -bor (255 - [int]$octetosMasc[$i])
}

$redStr = $red -join '.'
$broadcastStr = $broadcast -join '.'

Write-Host "`nRed calculada: $redStr" -ForegroundColor Yellow
Write-Host "Broadcast calculado: $broadcastStr" -ForegroundColor Yellow

# ==============================
# Crear Scope DHCP
# ==============================

Write-Host "`nCreando Scope DHCP..." -ForegroundColor Yellow

Add-DhcpServerv4Scope `
    -Name $scope `
    -StartRange $ipInicial `
    -EndRange $ipFinal `
    -SubnetMask $mascara `
    -State Active

# Configurar opciones DHCP
Set-DhcpServerv4OptionValue -ScopeId $redStr -OptionId 3 -Value $gateway
Set-DhcpServerv4OptionValue -ScopeId $redStr -OptionId 1 -Value $mascara

if ($dns -and $dnsAlt) {
    Set-DhcpServerv4OptionValue -ScopeId $redStr -OptionId 6 -Value @($dns,$dnsAlt)
}
elseif ($dns) {
    Set-DhcpServerv4OptionValue -ScopeId $redStr -OptionId 6 -Value $dns
}

# Tiempo de concesión
$duracion = New-TimeSpan -Seconds $leaseTime
Set-DhcpServerv4Scope -ScopeId $redStr -LeaseDuration $duracion

# ==============================
# Configurar IP estática al servidor
# ==============================

Write-Host "`nConfigurando IP estática $ipServidor en $interfaz..." -ForegroundColor Yellow

# Calcular Prefijo CIDR desde máscara
$binMasc = ($octetosMasc | ForEach-Object {
    [Convert]::ToString([int]$_,2).PadLeft(8,'0')
}) -join ""

$prefijo = ($binMasc.ToCharArray() | Where-Object {$_ -eq "1"}).Count

# Eliminar IPs previas
Get-NetIPAddress -InterfaceAlias $interfaz -ErrorAction SilentlyContinue | 
Remove-NetIPAddress -Confirm:$false -ErrorAction SilentlyContinue

# Asignar nueva IP
New-NetIPAddress `
    -InterfaceAlias $interfaz `
    -IPAddress $ipServidor `
    -PrefixLength $prefijo `
    -DefaultGateway $gateway

# Configurar DNS en la interfaz
if ($dns -and $dnsAlt) {
    Set-DnsClientServerAddress -InterfaceAlias $interfaz -ServerAddresses @($dns,$dnsAlt)
}
elseif ($dns) {
    Set-DnsClientServerAddress -InterfaceAlias $interfaz -ServerAddresses $dns
}

# Reiniciar servicio DHCP
Restart-Service DHCPServer

Write-Host "`nServidor DHCP configurado correctamente!" -ForegroundColor Green
Get-DhcpServerv4Scope -ScopeId $redStr | Format-List
