# Instalar OpenSSH Server
Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0

# Habilitar y arrancar el servicio
Set-Service -Name sshd -StartupType Automatic
Start-Service sshd

# Abrir puerto 22 en el firewall
New-NetFirewallRule -Name "OpenSSH-Server" `
    -DisplayName "OpenSSH Server (sshd)" `
    -Enabled True `
    -Direction Inbound `
    -Protocol TCP `
    -Action Allow `
    -LocalPort 22

Write-Host "SSH habilitado. Conectate con: ssh Administrador@$(Get-NetIPAddress -AddressFamily IPv4 | Where-Object {$_.IPAddress -notlike '127.*'} | Select-Object -First 1 -Expand IPAddress)" -ForegroundColor Green
