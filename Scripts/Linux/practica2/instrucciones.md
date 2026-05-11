# Practica 2
Objetivo
Se diseñará e implementará una solución automatizada mediante scripts (Bash y PowerShell) para instalar, configurar y monitorear un servidor DHCP en entornos Windows y Linux. El sistema deberá ser capaz de gestionar el direccionamiento dinámico de una red interna, garantizando la integridad de los parámetros entregados a un nodo cliente.

Requerimientos Técnicos
Servidor Linux: Uso del demonio isc-dhcp-server.
Servidor Windows: Implementación del rol DHCP Server mediante módulos de PowerShell.
Segmento de Red: 192.168.100.0 /24.
Rango de Asignación: 192.168.100.50 al 192.168.100.150.
Parámetros Adicionales: Puerta de enlace (192.168.100.1) y DNS (IP del servidor configurado en la Práctica 1).

Entregables
1. Implementación de la Lógica de Instalación (Idempotencia :) )
El script debe verificar de forma autónoma la presencia del servicio. En caso de no existir, procederá con una instalación desatendida:
Linux: Gestión de paquetes con apt-get o similar de acuerdo a distribución en modo no interactivo.
Windows: Despliegue de características con Install-WindowsFeature -IncludeManagementTools.

2. Orquestación de Configuración Dinámica
La automatización no debe limitarse a valores fijos. El script solicitará interactivamente los siguientes parámetros, validando que cumplan con el formato de red IPv4:
Nombre descriptivo del Ámbito (Scope).
Rango inicial y final de direcciones IP.
Tiempo de concesión (Lease Time).
Opciones de servidor (Router/Gateway y DNS).

3. Módulo de Monitoreo y Validación de Estado
Se debe integrar una función de diagnóstico que permita al administrador:
Consultar el estado del servicio en tiempo real.
Listar las concesiones (leases) activas para identificar equipos conectados.

Prueba de Cliente: Ejecutar una renovación forzada (release/renew) desde el cliente para validar la correcta recepción de datos.

Comandos básicos para la práctica
Administración en Linux (Bash):
Configuración: /etc/dhcp/dhcpd.conf
Logs y Concesiones: /var/lib/dhcp/dhcpd.leases
Sintaxis: dhcpd -t (validador de archivos de configuración).