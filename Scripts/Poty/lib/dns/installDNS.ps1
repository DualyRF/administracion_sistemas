# installDNS.ps1
# Instalacion de DNS
# Verifica e Instala DNS
. "$PSScriptRoot\..\utils.ps1"

function instalacionDNS {

    # Verificar si ya está instalado
    $dnsEstado = Get-WindowsFeature -Name *DNS*
    
    if ($DNSEstado.InstallState -eq "Installed") {
        return $true
    }
    else {
        Write-Host "DNS server no esta instalado, iniciando instalacion..." -ForegroundColor $amarillo
        
        Write-Host "Instalacion de DNS Server" -ForegroundColor $rosa

        try {
            $job = Start-Job -ScriptBlock {
                Install-WindowsFeature -Name DNS -IncludeManagementTools
            }
            
            Write-Host -NoNewline "DNS se esta instalando"
            while ($job.State -eq "Running") {
                Write-Host -NoNewline "."
                Start-Sleep -Milliseconds 500
            }
            
            $result = Receive-Job -Job $job
            Remove-Job -Job $job
            
            if ($result.Success) {
                Write-Host "DNS server instalado correctamente" -ForegroundColor $verde
                Get-WindowsFeature -Name *DNS*
                Start-Sleep -Seconds 2
                return $true
            }
            else {
                Write-Host "Error en la instalacion de DNS" -ForegroundColor $rojo
                return $false
            }
        }
        catch {
            Write-Host "Error durante la instalacion: $_" -ForegroundColor $rojo
            return $false
        }
    }
}