# Crear directorio con permisos correctos
sudo mkdir -p /var/www/nginx
sudo cp /srv/www/nginx/index.html /var/www/nginx/
sudo chown -R nginx:nginx /var/www/nginx
sudo chmod -R 755 /var/www/nginx
sudo chcon -R -t httpd_sys_content_t /var/www/nginx

# Cambiar el root en nginx.conf
sudo sed -i 's|/srv/www/nginx|/var/www/nginx|g' /etc/nginx/nginx.conf

# Reiniciar
sudo systemctl restart nginx

# Probar
curl -sk https://127.0.0.1:8443