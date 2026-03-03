# ============================================================================
# Script de Automatización de Servidor FTP - Windows Server 2025
# Administración de Sistemas
# Servidor: IIS con FTP Service
# ============================================================================

# ============================================================================
# Colores y utilidades
# ============================================================================
function Print-Info    { param($msg) Write-Host "[INFO]  $msg" -ForegroundColor Cyan }
function Print-Ok      { param($msg) Write-Host "[OK]    $msg" -ForegroundColor Green }
function Print-Error   { param($msg) Write-Host "[ERROR] $msg" -ForegroundColor Red }
function Print-Titulo  { param($msg) Write-Host "`n=== $msg ===`n" -ForegroundColor Yellow }

# ============================================================================
# Variables Globales
# ============================================================================
$FTP_ROOT          = "C:\ftp"
$GRUPO_REPROBADOS  = "reprobados"
$GRUPO_RECURSADORES = "recursadores"
$FTP_SITE_NAME     = "ServidorFTP"
$FTP_PORT          = 21

# ============================================================================
# FUNCIÓN: Mostrar ayuda
# ============================================================================
function Mostrar-Ayuda {
    Write-Host "Uso del script: .\ftp_server.ps1 [opcion]"
    Write-Host "Opciones:"
    Write-Host "  -verify    Verifica si IIS y FTP estan instalados"
    Write-Host "  -install   Instala y configura el servidor FTP"
    Write-Host "  -users     Gestionar usuarios FTP"
    Write-Host "  -restart   Reiniciar servidor FTP"
    Write-Host "  -status    Verificar estado del servidor FTP"
    Write-Host "  -list      Listar usuarios y estructura FTP"
    Write-Host "  -help      Muestra esta ayuda"
}

# ============================================================================
# FUNCIÓN: Verificar instalación de IIS y FTP
# ============================================================================
function Verificar-Instalacion {
    Print-Info "Verificando instalacion de IIS y FTP..."

    $iis = Get-WindowsFeature -Name "Web-Server" -ErrorAction SilentlyContinue
    $ftp = Get-WindowsFeature -Name "Web-Ftp-Server" -ErrorAction SilentlyContinue

    if ($iis.Installed -and $ftp.Installed) {
        Print-Ok "IIS y FTP Service ya estan instalados"
        return $true
    }

    if (-not $iis.Installed) {
        Print-Error "IIS (Web-Server) no esta instalado"
    }
    if (-not $ftp.Installed) {
        Print-Error "FTP Service (Web-Ftp-Server) no esta instalado"
    }

    return $false
}

# ============================================================================
# FUNCIÓN: Configurar SELinux - No aplica en Windows
# En Windows el equivalente sería Windows Defender / Firewall
# ============================================================================
function Configurar-Firewall {
    Print-Info "Configurando firewall para FTP..."

    # Puerto 21 FTP
    $rule21 = Get-NetFirewallRule -DisplayName "FTP Puerto 21" -ErrorAction SilentlyContinue
    if (-not $rule21) {
        New-NetFirewallRule -DisplayName "FTP Puerto 21" `
            -Direction Inbound -Protocol TCP -LocalPort 21 `
            -Action Allow | Out-Null
        Print-Ok "Puerto 21 abierto"
    } else {
        Print-Info "Regla puerto 21 ya existe"
    }

    # Puertos pasivos 40000-40100
    $rulePasv = Get-NetFirewallRule -DisplayName "FTP Pasivo 40000-40100" -ErrorAction SilentlyContinue
    if (-not $rulePasv) {
        New-NetFirewallRule -DisplayName "FTP Pasivo 40000-40100" `
            -Direction Inbound -Protocol TCP -LocalPort 40000-40100 `
            -Action Allow | Out-Null
        Print-Ok "Puertos pasivos 40000-40100 abiertos"
    } else {
        Print-Info "Regla puertos pasivos ya existe"
    }

    Print-Ok "Firewall configurado"
}

# ============================================================================
# FUNCIÓN: Crear grupos locales
# ============================================================================
function Crear-Grupos {
    Print-Info "Verificando grupos del sistema..."

    foreach ($grupo in @($GRUPO_REPROBADOS, $GRUPO_RECURSADORES)) {
        $g = Get-LocalGroup -Name $grupo -ErrorAction SilentlyContinue
        if (-not $g) {
            New-LocalGroup -Name $grupo -Description "Grupo FTP $grupo" | Out-Null
            Print-Ok "Grupo '$grupo' creado"
        } else {
            Print-Info "Grupo '$grupo' ya existe"
        }
    }

    Print-Ok "Grupos configurados"
}

# ============================================================================
# FUNCIÓN: Crear estructura de directorios
# ============================================================================
function Crear-Estructura-Base {
    Print-Info "Creando estructura de directorios FTP..."

    $dirs = @(
        $FTP_ROOT,
        "$FTP_ROOT\general",
        "$FTP_ROOT\reprobados",
        "$FTP_ROOT\recursadores",
        "$FTP_ROOT\personal",
        "$FTP_ROOT\usuarios"
    )

    foreach ($dir in $dirs) {
        if (-not (Test-Path $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
            Print-Ok "Directorio creado: $dir"
        }
    }

    # Permisos carpeta general: todos los usuarios autenticados pueden escribir
    # El anonimo puede leer
    $acl = Get-Acl "$FTP_ROOT\general"
    $acl.SetAccessRuleProtection($true, $false)

    # SYSTEM y Administradores control total
    $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule(
        "SYSTEM", "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow")))
    $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule(
        "Administrators", "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow")))

    # Usuarios autenticados pueden leer y escribir
    $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule(
        "Usuarios", "Modify", "ContainerInherit,ObjectInherit", "None", "Allow")))

    # Anonimo (IUSR) solo lectura
    $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule(
        "IUSR", "ReadAndExecute", "ContainerInherit,ObjectInherit", "None", "Allow")))

    Set-Acl "$FTP_ROOT\general" $acl
    Print-Ok "Permisos de general configurados"

    # Permisos carpeta reprobados: solo miembros del grupo
    foreach ($grupo in @($GRUPO_REPROBADOS, $GRUPO_RECURSADORES)) {
        $acl = Get-Acl "$FTP_ROOT\$grupo"
        $acl.SetAccessRuleProtection($true, $false)
        $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule(
            "SYSTEM", "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow")))
        $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule(
            "Administrators", "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow")))
        $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule(
            $grupo, "Modify", "ContainerInherit,ObjectInherit", "None", "Allow")))
        Set-Acl "$FTP_ROOT\$grupo" $acl
        Print-Ok "Permisos de $grupo configurados"
    }

    # Raiz FTP: solo administradores
    $acl = Get-Acl $FTP_ROOT
    $acl.SetAccessRuleProtection($true, $false)
    $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule(
        "SYSTEM", "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow")))
    $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule(
        "Administrators", "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow")))
    Set-Acl $FTP_ROOT $acl

    Print-Ok "Estructura base configurada"
}

# ============================================================================
# FUNCIÓN: Configurar IIS y sitio FTP
# ============================================================================
function Configurar-FTP {
    Print-Info "Configurando sitio FTP en IIS..."

    Import-Module WebAdministration -ErrorAction SilentlyContinue

    # Eliminar sitio FTP si ya existe para reconfigurar
    $sitio = Get-WebSite -Name $FTP_SITE_NAME -ErrorAction SilentlyContinue
    if ($sitio) {
        Remove-WebSite -Name $FTP_SITE_NAME
        Print-Info "Sitio FTP anterior eliminado"
    }

    # Crear nuevo sitio FTP
    New-WebFtpSite -Name $FTP_SITE_NAME -Port $FTP_PORT -PhysicalPath $FTP_ROOT | Out-Null
    Print-Ok "Sitio FTP creado: $FTP_SITE_NAME"

    # Configurar aislamiento de usuarios (User Isolation)
    # IsolateAllDirectories: cada usuario ve solo su carpeta y las compartidas
    Set-ItemProperty "IIS:\Sites\$FTP_SITE_NAME" `
        -Name ftpServer.userIsolation.mode -Value 3
    Print-Ok "Aislamiento de usuarios configurado"

    # Habilitar acceso anonimo (solo lectura a general)
    Set-ItemProperty "IIS:\Sites\$FTP_SITE_NAME" `
        -Name ftpServer.security.authentication.anonymousAuthentication.enabled `
        -Value $true
    Print-Ok "Autenticacion anonima habilitada"

    # Habilitar autenticacion basica para usuarios locales
    Set-ItemProperty "IIS:\Sites\$FTP_SITE_NAME" `
        -Name ftpServer.security.authentication.basicAuthentication.enabled `
        -Value $true
    Print-Ok "Autenticacion basica habilitada"

    # Deshabilitar SSL (entorno controlado)
    Set-ItemProperty "IIS:\Sites\$FTP_SITE_NAME" `
        -Name ftpServer.security.ssl.controlChannelPolicy -Value 0
    Set-ItemProperty "IIS:\Sites\$FTP_SITE_NAME" `
        -Name ftpServer.security.ssl.dataChannelPolicy -Value 0
    Print-Ok "SSL deshabilitado"

    # Configurar modo pasivo
    Set-WebConfigurationProperty -PSPath "IIS:\" `
        -Filter "system.ftpServer/firewallSupport" `
        -Name "lowDataChannelPort" -Value 40000
    Set-WebConfigurationProperty -PSPath "IIS:\" `
        -Filter "system.ftpServer/firewallSupport" `
        -Name "highDataChannelPort" -Value 40100
    Print-Ok "Puertos pasivos configurados: 40000-40100"

    # Regla de autorización: anonimo solo lectura a general
    Add-WebConfiguration -PSPath "IIS:\Sites\$FTP_SITE_NAME" `
        -Filter "system.ftpServer/security/authorization" `
        -Value @{
            accessType  = "Allow"
            users       = "?"
            permissions = "Read"
        }

    # Regla de autorización: usuarios autenticados lectura y escritura
    Add-WebConfiguration -PSPath "IIS:\Sites\$FTP_SITE_NAME" `
        -Filter "system.ftpServer/security/authorization" `
        -Value @{
            accessType  = "Allow"
            users       = "*"
            permissions = "Read,Write"
        }

    Print-Ok "Reglas de autorización FTP configuradas"

    # Iniciar sitio FTP
    Start-WebSite -Name $FTP_SITE_NAME
    Print-Ok "Sitio FTP iniciado"
}

# ============================================================================
# FUNCIÓN: Crear carpeta personal del usuario
# ============================================================================
function Crear-Carpeta-Personal {
    param(
        [string]$usuario,
        [string]$grupo
    )

    $carpeta = "$FTP_ROOT\personal\$usuario"

    if (-not (Test-Path $carpeta)) {
        New-Item -ItemType Directory -Path $carpeta -Force | Out-Null

        $acl = Get-Acl $carpeta
        $acl.SetAccessRuleProtection($true, $false)
        $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule(
            "SYSTEM", "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow")))
        $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule(
            "Administrators", "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow")))
        $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule(
            $usuario, "Modify", "ContainerInherit,ObjectInherit", "None", "Allow")))
        Set-Acl $carpeta $acl

        Print-Ok "Carpeta personal creada: $carpeta"
    }
}

# ============================================================================
# FUNCIÓN: Construir jaula del usuario
# IIS User Isolation requiere estructura:
# C:\ftp\LocalUser\<usuario>\ como raiz del usuario
# ============================================================================
function Construir-Jaula-Usuario {
    param(
        [string]$usuario,
        [string]$grupo
    )

    Print-Info "Construyendo jaula FTP para '$usuario'..."

    # IIS con User Isolation usa C:\ftp\LocalUser\<usuario>
    $jaula = "$FTP_ROOT\LocalUser\$usuario"
    New-Item -ItemType Directory -Path $jaula -Force | Out-Null

    # Permisos raiz jaula: solo administradores y el usuario
    $acl = Get-Acl $jaula
    $acl.SetAccessRuleProtection($true, $false)
    $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule(
        "SYSTEM", "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow")))
    $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule(
        "Administrators", "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow")))
    $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule(
        $usuario, "ReadAndExecute", "ContainerInherit,ObjectInherit", "None", "Allow")))
    Set-Acl $jaula $acl

    # Crear junction points (equivalente a bind mounts en Linux)
    # general -> C:\ftp\general
    $jGeneral = "$jaula\general"
    if (-not (Test-Path $jGeneral)) {
        cmd /c "mklink /J `"$jGeneral`" `"$FTP_ROOT\general`"" | Out-Null
        Print-Ok "Junction: general"
    }

    # grupo -> C:\ftp\<grupo>
    $jGrupo = "$jaula\$grupo"
    if (-not (Test-Path $jGrupo)) {
        cmd /c "mklink /J `"$jGrupo`" `"$FTP_ROOT\$grupo`"" | Out-Null
        Print-Ok "Junction: $grupo"
    }

    # carpeta personal -> C:\ftp\personal\<usuario>
    $jPersonal = "$jaula\$usuario"
    if (-not (Test-Path $jPersonal)) {
        cmd /c "mklink /J `"$jPersonal`" `"$FTP_ROOT\personal\$usuario`"" | Out-Null
        Print-Ok "Junction: $usuario (personal)"
    }

    Print-Ok "Jaula lista: $jaula"
}

# ============================================================================
# FUNCIÓN: Destruir jaula del usuario
# ============================================================================
function Destruir-Jaula-Usuario {
    param([string]$usuario)

    $jaula = "$FTP_ROOT\LocalUser\$usuario"

    Print-Info "Eliminando jaula de '$usuario'..."

    # Eliminar junction points antes que las carpetas
    foreach ($punto in @("general", $GRUPO_REPROBADOS, $GRUPO_RECURSADORES, $usuario)) {
        $path = "$jaula\$punto"
        if (Test-Path $path) {
            cmd /c "rmdir `"$path`"" | Out-Null
            Print-Ok "Junction eliminado: $path"
        }
    }

    if (Test-Path $jaula) {
        Remove-Item -Path $jaula -Recurse -Force
        Print-Ok "Jaula eliminada"
    }
}

# ============================================================================
# FUNCIÓN: Validar nombre de usuario
# ============================================================================
function Validar-Usuario {
    param([string]$usuario)

    if ([string]::IsNullOrEmpty($usuario)) {
        Print-Error "El nombre no puede estar vacio"
        return $false
    }

    if ($usuario.Length -lt 3 -or $usuario.Length -gt 32) {
        Print-Error "El nombre debe tener entre 3 y 32 caracteres"
        return $false
    }

    if ($usuario -notmatch '^[a-z][a-z0-9_-]*$') {
        Print-Error "Solo letras minusculas, numeros, - y _. Debe iniciar con letra."
        return $false
    }

    $existe = Get-LocalUser -Name $usuario -ErrorAction SilentlyContinue
    if ($existe) {
        Print-Error "El usuario '$usuario' ya existe"
        return $false
    }

    return $true
}

# ============================================================================
# FUNCIÓN: Crear usuario FTP
# ============================================================================
function Crear-Usuario-FTP {
    param(
        [string]$usuario,
        [string]$password,
        [string]$grupo
    )

    Print-Info "Creando usuario '$usuario' en grupo '$grupo'..."

    # Crear usuario local
    $securePass = ConvertTo-SecureString $password -AsPlainText -Force
    New-LocalUser -Name $usuario -Password $securePass `
        -PasswordNeverExpires $true `
        -UserMayNotChangePassword $false `
        -Description "Usuario FTP - $grupo" | Out-Null

    if (-not $?) {
        Print-Error "Error al crear el usuario '$usuario'"
        return $false
    }
    Print-Ok "Usuario del sistema creado"

    # Agregar al grupo correspondiente
    Add-LocalGroupMember -Group $grupo -Member $usuario
    Print-Ok "Usuario agregado al grupo '$grupo'"

    # Crear carpeta personal
    Crear-Carpeta-Personal -usuario $usuario -grupo $grupo

    # Construir jaula
    Construir-Jaula-Usuario -usuario $usuario -grupo $grupo

    Write-Host ""
    Print-Ok "═══════════════════════════════════════════════"
    Print-Ok "  Usuario '$usuario' creado"
    Print-Ok "═══════════════════════════════════════════════"
    Print-Info "  Carpetas disponibles al conectar:"
    Print-Info "    /general/          (publica)"
    Print-Info "    /$grupo/           (su grupo)"
    Print-Info "    /$usuario/         (personal)"
    Print-Ok "═══════════════════════════════════════════════"

    return $true
}

# ============================================================================
# FUNCIÓN: Cambiar usuario de grupo
# ============================================================================
function Cambiar-Grupo-Usuario {
    param([string]$usuario)

    $u = Get-LocalUser -Name $usuario -ErrorAction SilentlyContinue
    if (-not $u) {
        Print-Error "El usuario '$usuario' no existe"
        return
    }

    # Detectar grupo actual
    $grupoActual = ""
    foreach ($g in @($GRUPO_REPROBADOS, $GRUPO_RECURSADORES)) {
        $miembros = Get-LocalGroupMember -Group $g -ErrorAction SilentlyContinue
        if ($miembros | Where-Object { $_.Name -like "*\$usuario" -or $_.Name -eq $usuario }) {
            $grupoActual = $g
            break
        }
    }

    Print-Info "Grupo actual de '$usuario': $grupoActual"

    Write-Host ""
    Write-Host "Grupos disponibles:"
    Write-Host "  1) $GRUPO_REPROBADOS"
    Write-Host "  2) $GRUPO_RECURSADORES"
    $opcion = Read-Host "Seleccione el nuevo grupo [1-2]"

    $nuevoGrupo = switch ($opcion) {
        "1" { $GRUPO_REPROBADOS }
        "2" { $GRUPO_RECURSADORES }
        default {
            Print-Error "Opcion invalida"
            return
        }
    }

    if ($grupoActual -eq $nuevoGrupo) {
        Print-Info "El usuario ya pertenece a '$nuevoGrupo'"
        return
    }

    Print-Info "Cambiando '$usuario': '$grupoActual' -> '$nuevoGrupo'..."

    # Preguntar si mover archivos personales
    $carpetaActual = "$FTP_ROOT\personal\$usuario"
    $mover = "n"
    if ((Test-Path $carpetaActual) -and (Get-ChildItem $carpetaActual).Count -gt 0) {
        Write-Host ""
        Print-Info "La carpeta personal contiene archivos."
        $mover = Read-Host "Desea conservarlos en la nueva ubicacion? [s/N]"
    }

    # Destruir jaula actual
    Destruir-Jaula-Usuario -usuario $usuario

    # Quitar del grupo anterior
    if ($grupoActual -ne "") {
        Remove-LocalGroupMember -Group $grupoActual -Member $usuario -ErrorAction SilentlyContinue
        Print-Ok "Removido del grupo '$grupoActual'"
    }

    # Si no se mueven archivos, conservarlos donde estan (no borrar)
    if ($mover -notmatch '^[Ss]$') {
        Print-Info "Archivos conservados en $carpetaActual (sin acceso FTP hasta reasignacion)"
    }

    # Agregar al nuevo grupo
    Add-LocalGroupMember -Group $nuevoGrupo -Member $usuario
    Print-Ok "Agregado al grupo '$nuevoGrupo'"

    # Reconstruir jaula con nuevo grupo
    Construir-Jaula-Usuario -usuario $usuario -grupo $nuevoGrupo

    Write-Host ""
    Print-Ok "Usuario '$usuario' movido a '$nuevoGrupo'"
    Print-Info "  Nueva estructura FTP:"
    Print-Info "  ├── general/"
    Print-Info "  ├── $nuevoGrupo/"
    Print-Info "  └── $usuario/"
}

# ============================================================================
# FUNCIÓN: Instalar y configurar servidor FTP
# ============================================================================
function Instalar-FTP {
    Print-Titulo "Instalacion y Configuracion de Servidor FTP"

    if (Verificar-Instalacion) {
        $reconf = Read-Host "IIS y FTP ya estan instalados. Reconfigurar? [s/N]"
        if ($reconf -notmatch '^[Ss]$') {
            Print-Info "Operacion cancelada"
            return
        }
    } else {
        Print-Info "Instalando IIS y FTP Service..."
        Install-WindowsFeature -Name Web-Server, Web-Ftp-Server `
            -IncludeManagementTools | Out-Null
        if ($?) {
            Print-Ok "IIS y FTP Service instalados"
        } else {
            Print-Error "Error en la instalacion"
            return
        }
    }

    Write-Host ""
    Crear-Grupos
    Write-Host ""
    Crear-Estructura-Base
    Write-Host ""
    Configurar-FTP
    Write-Host ""
    Configurar-Firewall
    Write-Host ""

    # Configurar LocalUser para anonimo (IIS User Isolation)
    $anonDir = "$FTP_ROOT\LocalUser\Public"
    if (-not (Test-Path $anonDir)) {
        New-Item -ItemType Directory -Path $anonDir -Force | Out-Null
    }
    # Junction para que anonimo vea solo general
    $jAnonGeneral = "$anonDir\general"
    if (-not (Test-Path $jAnonGeneral)) {
        cmd /c "mklink /J `"$jAnonGeneral`" `"$FTP_ROOT\general`"" | Out-Null
        Print-Ok "Junction anonimo -> general"
    }

    # Obtener IP
    $ip = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object {
        $_.IPAddress -ne "127.0.0.1"
    } | Select-Object -First 1).IPAddress

    Write-Host ""
    Print-Ok "══════════════════════════════════════════════"
    Print-Ok "  Servidor FTP listo"
    Print-Ok "══════════════════════════════════════════════"
    Print-Info "  IP               : $ip"
    Print-Info "  Puerto           : 21"
    Print-Info "  Acceso anonimo   : ftp://$ip  (solo lectura)"
    Print-Info "  Jaulas usuarios  : $FTP_ROOT\LocalUser\<nombre>\"
    Print-Ok "══════════════════════════════════════════════"
    Write-Host ""
    Print-Info "Cree usuarios con: .\ftp_server.ps1 -users"
}

# ============================================================================
# FUNCIÓN: Gestionar usuarios FTP
# ============================================================================
function Gestionar-Usuarios {
    Print-Titulo "Gestion de Usuarios FTP"

    if (-not (Verificar-Instalacion)) {
        Print-Error "IIS/FTP no instalado. Ejecute: .\ftp_server.ps1 -install"
        return
    }

    Write-Host "Opciones:"
    Write-Host "  1) Crear nuevos usuarios"
    Write-Host "  2) Cambiar grupo de un usuario"
    Write-Host "  3) Eliminar usuario"
    Write-Host "  4) Volver"
    Write-Host ""
    $opcion = Read-Host "Seleccione una opcion [1-4]"

    switch ($opcion) {
        "1" {
            Write-Host ""
            $num = Read-Host "Cuantos usuarios desea crear?"

            if (-not ($num -match '^\d+$') -or [int]$num -lt 1) {
                Print-Error "Numero invalido"
                return
            }

            for ($i = 1; $i -le [int]$num; $i++) {
                Write-Host ""
                Print-Titulo "Usuario $i de $num"

                do {
                    $usuario = Read-Host "Nombre de usuario"
                } while (-not (Validar-Usuario -usuario $usuario))

                do {
                    $password = Read-Host "Contrasena (min. 8 caracteres)" -AsSecureString
                    $passPlain = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
                        [Runtime.InteropServices.Marshal]::SecureStringToBSTR($password))
                    if ($passPlain.Length -lt 8) {
                        Print-Error "La contrasena debe tener al menos 8 caracteres"
                        $passPlain = ""
                    } else {
                        $pass2 = Read-Host "Confirmar contrasena" -AsSecureString
                        $pass2Plain = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
                            [Runtime.InteropServices.Marshal]::SecureStringToBSTR($pass2))
                        if ($passPlain -ne $pass2Plain) {
                            Print-Error "Las contrasenas no coinciden"
                            $passPlain = ""
                        }
                    }
                } while ([string]::IsNullOrEmpty($passPlain))

                Write-Host ""
                Write-Host "A que grupo pertenece?"
                Write-Host "  1) $GRUPO_REPROBADOS"
                Write-Host "  2) $GRUPO_RECURSADORES"
                $gOpcion = Read-Host "Seleccione el grupo [1-2]"

                $grupo = switch ($gOpcion) {
                    "1" { $GRUPO_REPROBADOS }
                    "2" { $GRUPO_RECURSADORES }
                    default {
                        Print-Error "Opcion invalida, asignando a '$GRUPO_REPROBADOS'"
                        $GRUPO_REPROBADOS
                    }
                }

                Crear-Usuario-FTP -usuario $usuario -password $passPlain -grupo $grupo
            }

            Write-Host ""
            Print-Info "Reiniciando servicio FTP..."
            Restart-WebSite -Name $FTP_SITE_NAME
            Print-Ok "Servicio reiniciado"
        }

        "2" {
            Write-Host ""
            Listar-Usuarios-FTP
            Write-Host ""
            $usuario = Read-Host "Usuario a cambiar de grupo"
            Cambiar-Grupo-Usuario -usuario $usuario
            Restart-WebSite -Name $FTP_SITE_NAME
            Print-Ok "Servicio reiniciado"
        }

        "3" {
            Write-Host ""
            Listar-Usuarios-FTP
            Write-Host ""
            $usuario = Read-Host "Usuario a eliminar"

            $u = Get-LocalUser -Name $usuario -ErrorAction SilentlyContinue
            if (-not $u) {
                Print-Error "El usuario '$usuario' no existe"
                return
            }

            $confirmar = Read-Host "Confirma eliminar '$usuario'? [s/N]"
            if ($confirmar -match '^[Ss]$') {
                Destruir-Jaula-Usuario -usuario $usuario
                Remove-Item -Path "$FTP_ROOT\personal\$usuario" -Recurse -Force -ErrorAction SilentlyContinue
                Remove-LocalUser -Name $usuario
                Print-Ok "Usuario '$usuario' eliminado"
                Restart-WebSite -Name $FTP_SITE_NAME
                Print-Ok "Servicio reiniciado"
            } else {
                Print-Info "Operacion cancelada"
            }
        }

        "4" { return }
        default { Print-Error "Opcion invalida" }
    }
}

# ============================================================================
# FUNCIÓN: Listar usuarios FTP
# ============================================================================
function Listar-Usuarios-FTP {
    Print-Titulo "Usuarios FTP Configurados"

    $usuarios = @()
    foreach ($grupo in @($GRUPO_REPROBADOS, $GRUPO_RECURSADORES)) {
        $miembros = Get-LocalGroupMember -Group $grupo -ErrorAction SilentlyContinue
        foreach ($m in $miembros) {
            $nombre = $m.Name -replace ".*\\", ""
            $usuarios += [PSCustomObject]@{
                Usuario = $nombre
                Grupo   = $grupo
                Jaula   = "$FTP_ROOT\LocalUser\$nombre"
            }
        }
    }

    if ($usuarios.Count -eq 0) {
        Print-Info "No hay usuarios FTP configurados"
        return
    }

    $usuarios | Format-Table -AutoSize
}

# ============================================================================
# FUNCIÓN: Listar estructura FTP
# ============================================================================
function Listar-Estructura {
    Print-Titulo "Estructura del Servidor FTP"

    if (-not (Test-Path $FTP_ROOT)) {
        Print-Error "No existe: $FTP_ROOT"
        return
    }

    $ip = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object {
        $_.IPAddress -ne "127.0.0.1"
    } | Select-Object -First 1).IPAddress

    Print-Info "Raiz : $FTP_ROOT"
    Print-Info "IP   : $ip"
    Write-Host ""

    Get-ChildItem $FTP_ROOT -Depth 2 | Format-Table FullName, Mode, LastWriteTime -AutoSize

    Write-Host ""
    Listar-Usuarios-FTP
}

# ============================================================================
# FUNCIÓN: Reiniciar servicio FTP
# ============================================================================
function Reiniciar-FTP {
    Print-Info "Reiniciando servidor FTP..."

    Import-Module WebAdministration -ErrorAction SilentlyContinue

    $sitio = Get-WebSite -Name $FTP_SITE_NAME -ErrorAction SilentlyContinue
    if ($sitio) {
        Restart-WebSite -Name $FTP_SITE_NAME
        Print-Ok "Sitio FTP reiniciado"
    } else {
        Print-Error "Sitio FTP '$FTP_SITE_NAME' no encontrado"
    }
}

# ============================================================================
# FUNCIÓN: Ver estado del servidor
# ============================================================================
function Ver-Estado {
    Print-Titulo "ESTADO DEL SERVIDOR FTP"

    Import-Module WebAdministration -ErrorAction SilentlyContinue

    $sitio = Get-WebSite -Name $FTP_SITE_NAME -ErrorAction SilentlyContinue
    if ($sitio) {
        Write-Host "Sitio  : $($sitio.Name)"
        Write-Host "Estado : $($sitio.State)"
        Write-Host "Puerto : $FTP_PORT"
        Write-Host "Ruta   : $($sitio.PhysicalPath)"
    } else {
        Print-Error "Sitio FTP no encontrado"
    }

    Write-Host ""
    Print-Info "Conexiones activas en puerto 21:"
    netstat -an | Select-String ":21 "
}

# ============================================================================
# VERIFICAR ADMINISTRADOR
# ============================================================================
$currentPrincipal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Print-Error "Este script debe ejecutarse como Administrador"
    exit 1
}

# ============================================================================
# PROCESAMIENTO DE ARGUMENTOS
# ============================================================================
param(
    [switch]$verify,
    [switch]$install,
    [switch]$users,
    [switch]$restart,
    [switch]$status,
    [switch]$list,
    [switch]$help
)

if     ($verify)  { Verificar-Instalacion }
elseif ($install) { Instalar-FTP }
elseif ($users)   { Gestionar-Usuarios }
elseif ($restart) { Reiniciar-FTP }
elseif ($status)  { Ver-Estado }
elseif ($list)    { Listar-Estructura }
else              { Mostrar-Ayuda }