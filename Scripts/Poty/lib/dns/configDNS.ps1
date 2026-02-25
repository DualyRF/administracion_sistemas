# configDNS.ps1
# Gestion de dominios en Windows DNS Server
# Equivalente al monitoreo() del dns.sh
. "$PSScriptRoot\..\utils.ps1"
. "$PSScriptRoot\installDNS.ps1"

# ---------- Funciones ----------

function listar_Dominios {
    if (! installDNS) {
        Write-Host "DNS no esta instalado, volviendo..."
        return
    }
    Write-Host "`n--- Dominios Configurados ---" -ForegroundColor $azul

    $zonas = Get-DnsServerZone -ErrorAction SilentlyContinue |
    Where-Object { $_.ZoneName -notmatch "^(localhost|0\.in-addr\.arpa|127\.in-addr\.arpa|255\.in-addr\.arpa|TrustAnchors)" }

    if (-not $zonas) {
        Write-Host "No hay dominios configurados" -ForegroundColor $amarillo
        return
    }

    Write-Host ""
    Write-Host ("{0,-35} {1,-20} {2,-15} {3}" -f "DOMINIO", "IP (@)", "TIPO", "ESTADO") -ForegroundColor $azul
    Write-Host ("─" * 85)

    foreach ($zona in $zonas) {
        $ip     = "N/A"
        $estado = "Activo"
        $color  = $verde

        try {
            $registroA = Get-DnsServerResourceRecord -ZoneName $zona.ZoneName -RRType A -Name "@" -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($registroA) {
                $ip = $registroA.RecordData.IPv4Address.ToString()
            }
        }
        catch { }

        if ($zona.ZoneType -eq "Secondary") {
            $estado = "Secundaria"
            $color  = $amarillo
        }
        elseif ($zona.IsPaused) {
            $estado = "Pausada"
            $color  = $rojo
        }

        Write-Host ("{0,-35} {1,-20} {2,-15}" -f $zona.ZoneName, $ip, $zona.ZoneType) -NoNewline
        Write-Host $estado -ForegroundColor $color
    }

    Write-Host ""
    Write-Host "Total de dominios: $($zonas.Count)" -ForegroundColor $azul
}

function agregar_Dominio {
    Write-Host "`n--- Agregar Dominio ---" -ForegroundColor $azul

    # Nombre del dominio
    $domValido = $false
    do {
        $dominio = Read-Host "Nombre del dominio (ej: reprobados.com)"

        if ($dominio -notmatch '^[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z]{2,})+$') {
            Write-Host "Dominio invalido, use formato: nombre.extension" -ForegroundColor $rojo
        }
        else {
            $existe = Get-DnsServerZone -Name $dominio -ErrorAction SilentlyContinue
            if ($existe) {
                Write-Host "El dominio '$dominio' ya esta configurado" -ForegroundColor $rojo
            }
            else {
                $domValido = $true
            }
        }
    } while (-not $domValido)

    # IP del dominio
    $ipValida = $false
    do {
        $ip = Read-Host "IP a la que apuntara $dominio"
        if (validar_IP -ip $ip) {
            $ipValida = $true
        }
    } while (-not $ipValida)

    # Crear zona primaria
    try {
        Add-DnsServerPrimaryZone -Name $dominio -ZoneFile "$dominio.dns" -ErrorAction Stop
        Write-Host "Zona '$dominio' creada correctamente" -ForegroundColor $verde
    }
    catch {
        Write-Host "Error al crear la zona: $($_.Exception.Message)" -ForegroundColor $rojo
        return
    }

    # Agregar registros A
    try {
        Add-DnsServerResourceRecordA -Name "@"   -ZoneName $dominio -IPv4Address $ip -ErrorAction Stop
        Add-DnsServerResourceRecordA -Name "ns1" -ZoneName $dominio -IPv4Address $ip -ErrorAction Stop
        Add-DnsServerResourceRecordA -Name "www" -ZoneName $dominio -IPv4Address $ip -ErrorAction Stop
        Write-Host "Registros creados: @ → $ip, ns1 → $ip, www → $ip" -ForegroundColor $verde
    }
    catch {
        Write-Host "Error al crear registros: $($_.Exception.Message)" -ForegroundColor $rojo
        return
    }

    # Recargar servicio
    try {
        Restart-Service DNS -ErrorAction Stop
        Write-Host "Servicio DNS recargado" -ForegroundColor $verde
    }
    catch {
        Write-Host "Advertencia: no se pudo recargar el servicio DNS" -ForegroundColor $amarillo
    }

    Write-Host ""
    Write-Host "Dominio '$dominio' agregado exitosamente" -ForegroundColor $verde
    Write-Host "  IP configurada : $ip"                  -ForegroundColor $azul
    Write-Host "  Registro A     : $dominio -> $ip"      -ForegroundColor $azul
    Write-Host "  Registro A     : www.$dominio -> $ip"  -ForegroundColor $azul
}

function eliminar_Dominio {
    Write-Host "`n═══ Eliminar Dominio ═══" -ForegroundColor $azul

    listar_Dominios

    $dominio = Read-Host "`nNombre del dominio a eliminar"

    $existe = Get-DnsServerZone -Name $dominio -ErrorAction SilentlyContinue
    if (-not $existe) {
        Write-Host "El dominio '$dominio' no existe" -ForegroundColor $rojo
        return
    }

    $confirmar = Read-Host "Estas seguro de eliminar '$dominio'? (s/N)"
    if ($confirmar -notmatch '^[Ss]$') {
        Write-Host "Operacion cancelada" -ForegroundColor $amarillo
        return
    }

    try {
        Remove-DnsServerZone -Name $dominio -Force -ErrorAction Stop
        Write-Host "Dominio '$dominio' eliminado correctamente" -ForegroundColor $verde
    }
    catch {
        Write-Host "Error al eliminar: $($_.Exception.Message)" -ForegroundColor $rojo
        return
    }

    try {
        Restart-Service DNS -ErrorAction Stop
        Write-Host "Servicio DNS recargado" -ForegroundColor $verde
    }
    catch {
        Write-Host "Advertencia: no se pudo recargar el servicio DNS" -ForegroundColor $amarillo
    }
}