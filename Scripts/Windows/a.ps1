Import-Module WebAdministration

# Eliminar los Virtual Directories que no funcionan
foreach ($user in @("user1", "user2", "user3")) {
    Remove-WebVirtualDirectory -Site "ServidorFTP" -Application "/" -Name "$user/general" -ErrorAction SilentlyContinue
    Remove-WebVirtualDirectory -Site "ServidorFTP" -Application "/" -Name "$user/reprobados" -ErrorAction SilentlyContinue
    Remove-WebVirtualDirectory -Site "ServidorFTP" -Application "/" -Name "$user/recursadores" -ErrorAction SilentlyContinue
}

# Crear junctions fisicas dentro de cada home
foreach ($user in @("user1", "user2", "user3")) {
    $jaula = "C:\ftp\LocalUser\$user"
    
    # Junction general
    if (-not (Test-Path "$jaula\general")) {
        cmd /c "mklink /J `"$jaula\general`" `"C:\ftp\LocalUser\Public\general`""
    }
}

# Para user1 (reprobados)
if (-not (Test-Path "C:\ftp\LocalUser\user1\reprobados")) {
    cmd /c "mklink /J `"C:\ftp\LocalUser\user1\reprobados`" `"C:\ftp\LocalUser\reprobados`""
}

# Para user2 (recursadores)  
if (-not (Test-Path "C:\ftp\LocalUser\user2\recursadores")) {
    cmd /c "mklink /J `"C:\ftp\LocalUser\user2\recursadores`" `"C:\ftp\LocalUser\recursadores`""
}

# Para user3 (reprobados)
if (-not (Test-Path "C:\ftp\LocalUser\user3\reprobados")) {
    cmd /c "mklink /J `"C:\ftp\LocalUser\user3\reprobados`" `"C:\ftp\LocalUser\reprobados`""
}