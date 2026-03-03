# Ver permisos actuales de la carpeta del anonimo
icacls "C:\ftp\LocalUser\Public"
icacls "C:\ftp\LocalUser\Public\general"

# Restaurar acceso de IUSR a Public y general
icacls "C:\ftp\LocalUser\Public" /grant "IUSR:(OI)(CI)(RX)"
icacls "C:\ftp\LocalUser\Public\general" /grant "IUSR:(OI)(CI)(RX)"