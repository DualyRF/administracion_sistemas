# Practica 3
Objetivo de la Actividad
Se desarrollará una solución automatizada para la instalación y configuración de un servidor DNS (Domain Name System) en Windows Server y Linux. 
El script deberá establecer una zona de búsqueda directa para el dominio reprobados.com, permitiendo la resolución de nombres tanto para el dominio raíz como para el subdominio www, apuntando dinámicamente a una dirección IP de la red interna.

Requerimientos Técnicos del Entorno

Servidor Linux: Implementación de BIND9 (Berkeley Internet Name Domain).
Servidor Windows: Implementación del rol DNS Server.

Dominio Requerido: reprobados.com

Registros Específicos: * Registro Tipo A para reprobados.com.
Registro Tipo CNAME o A para www.reprobados.com.

Ambos nombres deben resolver hacia la IP de la máquina virtual cliente (o una VM referenciada).

Actividades y Entregables Técnicos
1. Automatización de Instalación e Idempotencia
El script debe detectar si el servicio DNS ya está operando para evitar conflictos de sobrescritura:

Linux: Instalación de bind9, bind9utils y bind9-doc.
Windows: Instalación del servicio mediante Install-WindowsFeature DNS.

2. Configuración de Zona y Registros (Automatización)
El script debe ser capaz de editar o generar los archivos de zona sin intervención manual:

Linux: Generación del archivo /etc/bind/named.conf.local y creación del archivo de zona en /var/cache/bind/db.reprobados.com utilizando plantillas o comandos cat <<EOF.
Windows: Uso de los cmdlets Add-DnsServerPrimaryZone y Add-DnsServerResourceRecordA.

3. Validación y Pruebas de Resolución
El módulo de monitoreo deberá verificar el estado del servicio:

Verificación de Sintaxis: Uso de named-checkconf en Linux.

Prueba de Resolución: Desde el cliente, el script debe ejecutar nslookup reprobados.com y ping www.reprobados.com, capturando la evidencia de que la IP devuelta coincide con la máquina referenciada.

Considerar el script con parámetros para la reutilización futura, seguir agregando las validaciones para los nuevos datos de entrada.
Deberá de hacer una verificación de que si existe una ip fija configurada, si no la tiene, ejecutar proceso para pedir datos y asignar una ip fija.

Estructura Obligatoria del Documento
1. Portada y Control de Versiones
Identificación: Título de la práctica, nombres de los integrantes, fecha de entrega y carrera.
Registro de Cambios: Tabla con: Versión (1.0, 1.1, etc.), 
Fecha, Autor y Descripción de la modificación (ej: "Refactorización de funciones DHCP").

2. Introducción y Topología de Red
Descripción: Resumen del servicio configurado y su importancia en la infraestructura.
Diagrama de Red: Representación visual de la arquitectura. Debe mostrar las IPs estáticas, nombres de host y la interconexión entre el Servidor (Linux/Windows) y el Cliente.

3. Manual de Instalación y Uso (Scripts)
Esta sección debe ser "paso a paso" para el usuario final.
Pre-requisitos: Herramientas necesarias (Git, permisos de root/administrador, conectividad).

Guía de Ejecución: Pasos para clonar el repositorio. Comandos exactos para lanzar el menú principal o los scripts individuales.
Explicación de los parámetros que el script solicitará al usuario (inputs).

4. Bitácora de Desarrollo y Explicación Lógica
No se debe copiar todo el código, sino explicar los bloques clave: Lógica de Idempotencia: Cómo el script verifica si el servicio ya existe.
Manejo de Archivos: Qué comandos se usaron para editar archivos de configuración (ej: sed en Linux o Set-Content en PowerShell).
Captura de Pantalla del Código: Fragmentos relevantes comentados.

5. Protocolo de Pruebas y Validación (Checklist)
Es la evidencia de que la práctica funciona. Se debe presentar en formato de tabla: 
Prueba                     Acción Realizada                   Resultado Esperado  Resultado Obtenido   Estatus (OK/Fail)
Resolución DNS      nslookup reprobados.com  IP: 192.168.x.y              IP: 192.168.x.y               OK
Renovación             IPipconfig /renew                  Recibir IP del rango    Recibió 192.168.x.50   OK

Evidencias Visuales: Capturas de pantalla de la terminal del Cliente demostrando el éxito de las pruebas.

6. Conclusiones Técnicas y Referencias
Análisis de los problemas encontrados y su solución.
Fuentes consultadas (enlaces a documentación oficial).
Se