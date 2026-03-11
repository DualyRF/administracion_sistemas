#!/bin/bash
# =============================================================================
# main.sh — Script principal de aprovisionamiento web
# Proyecto : Aprovisionamiento Web Automatizado
# SO       : OpenSUSE Leap
# Uso      : sudo bash main.sh
# =============================================================================

source ./lib/utils.sh
source ./lib/http_functions.sh

# -----------------------------------------------------------------------------
# MENÚ PRINCIPAL
# -----------------------------------------------------------------------------
menu_principal() {
    while true; do
        print_title "Aprovisionamiento Web Automatizado"
        print_menu "  [1] Apache2"
        print_menu "  [2] Nginx      (próximamente)"
        print_menu "  [3] Tomcat     (próximamente)"
        print_menu "  [0] Salir"
        echo ""
        echo -ne "${cyan}Selecciona un servidor: ${nc}"
        read -r opcion

        case "$opcion" in
            1) setup_apache  ;;
            2) print_info "[INFO] Nginx aún no implementado." ;;
            3) print_info "[INFO] Tomcat aún no implementado." ;;
            0) print_success "Saliendo..."; exit 0 ;;
            *) print_warning "[ERROR] Opción inválida." ;;
        esac

        echo ""
        echo -ne "${cyan}¿Volver al menú? [s/n]: ${nc}"
        read -r respuesta
        [[ "$respuesta" != "s" ]] && break
    done
}

# -----------------------------------------------------------------------------
# INICIO
# -----------------------------------------------------------------------------
verificar_root
menu_principal